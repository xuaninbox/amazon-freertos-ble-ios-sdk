import CoreBluetooth
import os.log

/// Amazon FreeRTOS Manager.
public class AmazonFreeRTOSManager: NSObject {

    /// Enable debug messages.
    public var isDebug: Bool = false
    /// Debug messages.
    public var debugMessages: String = String()
    /// Service UUIDs in the Advertising Packets.
    public var advertisingServiceUUIDs: [CBUUID] = [AmazonFreeRTOSGattService.DeviceInfo]
    /// Service UUIDs.
    public var serviceUUIDs: [CBUUID] = [AmazonFreeRTOSGattService.DeviceInfo, AmazonFreeRTOSGattService.NetworkConfig]

    /// Shared instence of Amazon FreeRTOS Manager.
    public static let shared = AmazonFreeRTOSManager()

    // BLE Central Manager for the SDK.
    private var central: CBCentralManager?

    /// The peripherals using peripheral identifier as key.
    public var peripherals: [String: CBPeripheral] = [:]
    /// The auto reconnect peripherals using peripheral identifier as key.
    public var reconnectPeripherals: [String: CBPeripheral] = [:]
    /// The mtus for peripherals using peripheral identifier as key.
    public var mtus: [String: Int] = [:]
    /// The networks peripherals scaned using peripheral identifier as key. [0] are saved networks and [1] are scaned networks.
    public var networks: [String: [[ListNetworkResp]]] = [:]

    /**
     Initializes a new Amazon FreeRTOS Manager.

     - Returns: A new Amazon FreeRTOS Manager.
     */
    public override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
    }
}

// This section are the methods for when using the build-in BLE central. It includes the BLE Helpers to scan and connect to the peripheral, methods to start the Mqtt Proxy Service and methods to operate the Network Config Service.
extension AmazonFreeRTOSManager {

    // BLE Helper

    /**
     Start scan for FreeRTOS peripherals.

     - Precondition: `central` is ready and not scanning.
     */
    public func startScanForPeripherals() {
        if let central = central, !central.isScanning {
            central.scanForPeripherals(withServices: advertisingServiceUUIDs, options: nil)
        }
    }

    /**
     Stop scan for FreeRTOS peripherals.

     - Precondition: `central` is ready and is scanning.
     */
    public func stopScanForPeripherals() {
        if let central = central, central.isScanning {
            central.stopScan()
        }
    }

    /// Disconnect and rescan for FreeRTOS peripherals and clear all contexts.
    public func rescanForPeripherals() {
        stopScanForPeripherals()

        for peripheral in peripherals.values where peripheral.state == .connected {
            disconnectPeripheral(peripheral)
        }

        peripherals.removeAll()
        reconnectPeripherals.removeAll()
        mtus.removeAll()
        networks.removeAll()

        startScanForPeripherals()
    }

    /**
     Connect to FreeRTOS `peripheral`.

     - Parameters:
        - peripheral: The FreeRTOS peripheral.
        - reconnect: Peripheral should auto reconnect on non-explicit disconnect.
     - Precondition: `central` is ready and `peripheral` must be disconnected, otherwise it will be ignored.
     */
    public func connectPeripheral(_ peripheral: CBPeripheral, reconnect: Bool) {
        if reconnect {
            reconnectPeripherals[peripheral.identifier.uuidString] = peripheral
        }
        if let central = central, peripheral.state == .disconnected {
            central.connect(peripheral, options: nil)
        }
    }

    /**
     Disconnect from FreeRTOS `peripheral`.

     - Parameter peripheral: The FreeRTOS peripheral.
     - Precondition: `central` is ready and `peripheral` must be connected, otherwise it will be ignored.
     */
    public func disconnectPeripheral(_ peripheral: CBPeripheral) {
        reconnectPeripherals.removeValue(forKey: peripheral.identifier.uuidString)
        if let central = central, peripheral.state == .connected {
            central.cancelPeripheralConnection(peripheral)
        }
    }

    // Device Info Service

    /**
     Get afrVersion of the Amazon FreeRTOS `peripheral`.

     - Parameter peripheral: The FreeRTOS peripheral.
     - Precondition: `central` is ready and `peripheral` must be connected.
     */
    public func getAfrVersionOfPeripheral(_ peripheral: CBPeripheral) {

        debugPrint("↓ get afrVersion")

        guard let characteristic = peripheral.serviceOf(uuid: AmazonFreeRTOSGattService.DeviceInfo)?.characteristicOf(uuid: AmazonFreeRTOSGattCharacteristic.AfrVersion) else {
            debugPrint("Error (getAfrVersionOfPeripheral): DeviceInfo service or AfrVersion characteristic doesn't exist")
            return
        }
        peripheral.readValue(for: characteristic)
    }

    /**
     Get mqtt broker endpoint of the Amazon FreeRTOS `peripheral`.

     - Parameter peripheral: The FreeRTOS peripheral.
     - Precondition: `central` is ready and `peripheral` must be connected.
     */
    public func getBrokerEndpointOfPeripheral(_ peripheral: CBPeripheral) {

        debugPrint("↓ get brokerEndpoint")

        guard let characteristic = peripheral.serviceOf(uuid: AmazonFreeRTOSGattService.DeviceInfo)?.characteristicOf(uuid: AmazonFreeRTOSGattCharacteristic.BrokerEndpoint) else {
            debugPrint("Error (getBrokerEndpointOfPeripheral): DeviceInfo service or BrokerEndpoint characteristic doesn't exist")
            return
        }
        peripheral.readValue(for: characteristic)
    }

    /**
     Get BLE mtu of the Amazon FreeRTOS `peripheral`.

     - Parameter peripheral: The FreeRTOS peripheral.
     - Precondition: `central` is ready and `peripheral` must be connected.
     */
    public func getMtuOfPeripheral(_ peripheral: CBPeripheral) {

        debugPrint("↓ get mtu")

        guard let characteristic = peripheral.serviceOf(uuid: AmazonFreeRTOSGattService.DeviceInfo)?.characteristicOf(uuid: AmazonFreeRTOSGattCharacteristic.Mtu) else {
            debugPrint("Error (getMtuOfPeripheral): DeviceInfo service or Mtu characteristic doesn't exist")
            return
        }
        peripheral.readValue(for: characteristic)
    }

    // Network Config Service

    /**
     List saved and scanned wifi networks of `peripheral`. Wifi networks are returned one by one, saved wifi ordered by priority and scanned wifi ordered by signal strength (rssi).

     - Parameters:
        - peripheral: The FreeRTOS peripheral.
        - listNetworkReq: The list network request.
     */
    public func listNetworkOfPeripheral(_ peripheral: CBPeripheral, listNetworkReq: ListNetworkReq) {

        debugPrint("↓ \(listNetworkReq)")

        // reset networks list for the peripheral
        networks[peripheral.identifier.uuidString] = [[], []]

        guard let data = encode(listNetworkReq) else {
            debugPrint("Error (listNetworkOfPeripheral): Invalid ListNetworkReq")
            return
        }
        guard let characteristic = peripheral.serviceOf(uuid: AmazonFreeRTOSGattService.NetworkConfig)?.characteristicOf(uuid: AmazonFreeRTOSGattCharacteristic.ListNetwork) else {
            debugPrint("Error (listNetworkOfPeripheral): NetworkConfig service or ListNetwork characteristic doesn't exist")
            return
        }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    /**
     Save wifi network to `peripheral`.

     - Parameters:
        - peripheral: The FreeRTOS peripheral.
        - saveNetworkReq: The save network request.
     */
    public func saveNetworkToPeripheral(_ peripheral: CBPeripheral, saveNetworkReq: SaveNetworkReq) {

        debugPrint("↓ \(saveNetworkReq)")

        guard let data = encode(saveNetworkReq) else {
            debugPrint("Error (saveNetworkToPeripheral): Invalid SaveNetworkReq")
            return
        }
        guard let characteristic = peripheral.serviceOf(uuid: AmazonFreeRTOSGattService.NetworkConfig)?.characteristicOf(uuid: AmazonFreeRTOSGattCharacteristic.SaveNetwork) else {
            debugPrint("Error (saveNetworkToPeripheral): NetworkConfig service or SaveNetwork characteristic doesn't exist")
            return
        }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    /**
     Edit wifi network of `peripheral`. Currently only support priority change.

     - Parameters:
        - peripheral: The FreeRTOS peripheral.
        - editNetworkReq: The edit network request.
     */
    public func editNetworkOfPeripheral(_ peripheral: CBPeripheral, editNetworkReq: EditNetworkReq) {

        debugPrint("↓ \(editNetworkReq)")

        guard let data = encode(editNetworkReq) else {
            debugPrint("Error (editNetworkOfPeripheral): Invalid EditNetworkReq")
            return
        }
        guard let characteristic = peripheral.serviceOf(uuid: AmazonFreeRTOSGattService.NetworkConfig)?.characteristicOf(uuid: AmazonFreeRTOSGattCharacteristic.EditNetwork) else {
            debugPrint("Error (editNetworkOfPeripheral): NetworkConfig service or EditNetwork characteristic doesn't exist")
            return
        }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    /**
     Delete saved wifi network from `peripheral`.

     - Parameters:
        - peripheral: The FreeRTOS peripheral.
        - deleteNetworkReq: The delete network request.
     */
    public func deleteNetworkFromPeripheral(_ peripheral: CBPeripheral, deleteNetworkReq: DeleteNetworkReq) {

        debugPrint("↓ \(deleteNetworkReq)")

        guard let data = encode(deleteNetworkReq) else {
            debugPrint("Error (deleteNetworkFromPeripheral): Invalid DeleteNetworkReq")
            return
        }
        guard let characteristic = peripheral.serviceOf(uuid: AmazonFreeRTOSGattService.NetworkConfig)?.characteristicOf(uuid: AmazonFreeRTOSGattCharacteristic.DeleteNetwork) else {
            debugPrint("Error (deleteNetworkFromPeripheral): NetworkConfig service or DeleteNetwork characteristic doesn't exist")
            return
        }
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
}

// This section are the methods for CBCentralManagerDelegate.
extension AmazonFreeRTOSManager: CBCentralManagerDelegate {

    // BLE state change

    /// CBCentralManagerDelegate
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            startScanForPeripherals()
            return
        }
        stopScanForPeripherals()
        NotificationCenter.default.post(name: .afrCentralManagerDidUpdateState, object: nil, userInfo: ["state": central.state])
    }

    // Discover

    /// CBCentralManagerDelegate
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi _: NSNumber) {
        debugPrint("→ \(advertisementData)")
        if peripherals.keys.contains(peripheral.identifier.uuidString) {
            debugPrint("Error (central_didDiscoverPeripheral): Duplicate Peripheral")
            return
        }
        peripherals[peripheral.identifier.uuidString] = peripheral
        NotificationCenter.default.post(name: .afrCentralManagerDidDiscoverPeripheral, object: nil, userInfo: ["peripheral": peripheral.identifier])
    }

    // Connection

    /// CBCentralManagerDelegate
    public func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        networks[peripheral.identifier.uuidString] = [[], []]
        peripheral.delegate = self
        peripheral.discoverServices(serviceUUIDs)
        NotificationCenter.default.post(name: .afrCentralManagerDidConnectPeripheral, object: nil, userInfo: ["peripheral": peripheral.identifier])
    }

    /// CBCentralManagerDelegate
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            debugPrint("Error (central_didDisconnectPeripheral): \(error.localizedDescription)")
        }
        networks.removeValue(forKey: peripheral.identifier.uuidString)
        NotificationCenter.default.post(name: .afrCentralManagerDidDisconnectPeripheral, object: nil, userInfo: ["peripheral": peripheral.identifier])
        if let peripheral = reconnectPeripherals[peripheral.identifier.uuidString] {
            central.connect(peripheral, options: nil)
        }
    }

    /// CBCentralManagerDelegate
    public func centralManager(_: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if let error = error {
            debugPrint("Error (central_didFailToConnect): \(error.localizedDescription)")
        }
        NotificationCenter.default.post(name: .afrCentralManagerDidFailToConnectPeripheral, object: nil, userInfo: ["peripheral": peripheral.identifier])
    }
}

// This section are the methods for CBPeripheralDelegate.
extension AmazonFreeRTOSManager: CBPeripheralDelegate {

    // Discover

    /// CBPeripheralDelegate
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            debugPrint("Error (peripheral_didDiscoverServices): \(error.localizedDescription)")
            return
        }
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
        NotificationCenter.default.post(name: .afrPeripheralDidDiscoverServices, object: nil, userInfo: ["peripheral": peripheral.identifier])
    }

    /// CBPeripheralDelegate
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error = error {
            debugPrint("Error (peripheral_didDiscoverCharacteristicsForService): \(error.localizedDescription)")
            return
        }
        for characteristic in service.characteristics ?? [] {
            peripheral.setNotifyValue(true, for: characteristic)
        }
        NotificationCenter.default.post(name: .afrPeripheralDidDiscoverCharacteristics, object: nil, userInfo: ["peripheral": peripheral.identifier, "service": service.uuid])
    }

    // Read

    /// CBPeripheralDelegate
    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {

        if let error = error {
            debugPrint("Error (peripheral_didUpdateValueForCharacteristic): \(error.localizedDescription)")
            return
        }

        switch characteristic.uuid {

            // Device Info Service

        case AmazonFreeRTOSGattCharacteristic.AfrVersion:
            didUpdateValueForAfrVersion(peripheral: peripheral, characteristic: characteristic)

        case AmazonFreeRTOSGattCharacteristic.BrokerEndpoint:
            didUpdateValueForBrokerEndpoint(peripheral: peripheral, characteristic: characteristic)

        case AmazonFreeRTOSGattCharacteristic.Mtu:
            didUpdateValueForMtu(peripheral: peripheral, characteristic: characteristic)

            // Network Config Service

        case AmazonFreeRTOSGattCharacteristic.ListNetwork:
            didUpdateValueForListNetwork(peripheral: peripheral, characteristic: characteristic)

        case AmazonFreeRTOSGattCharacteristic.SaveNetwork:
            didUpdateValueForSaveNetwork(peripheral: peripheral, characteristic: characteristic)

        case AmazonFreeRTOSGattCharacteristic.EditNetwork:
            didUpdateValueForEditNetwork(peripheral: peripheral, characteristic: characteristic)

        case AmazonFreeRTOSGattCharacteristic.DeleteNetwork:
            didUpdateValueForDeleteNetwork(peripheral: peripheral, characteristic: characteristic)

        default:
            debugPrint("Error (peripheral_didUpdateValueForCharacteristic): Unsupported Characteristic")
            return
        }
    }

    // write

    /// CBPeripheralDelegate
    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {

        if let error = error {
            debugPrint("Error (peripheral_didWriteValueForCharacteristic): \(error.localizedDescription)")
            return
        }
    }
}

// This section are the methods for processing the data.
extension AmazonFreeRTOSManager {

    // Device Info Service

    /**
     Process data of AfrVersion characteristic from `peripheral`.

     - Parameters:
        - peripheral: The FreeRTOS peripheral.
        - characteristic: The AfrVersion characteristic.
     */
    public func didUpdateValueForAfrVersion(peripheral _: CBPeripheral, characteristic: CBCharacteristic) {

        guard let value = characteristic.value, let afrVersion = String(data: value, encoding: .utf8) else {
            debugPrint("Error (didUpdateValueForDeviceInfo): Invalid AfrVersion")
            return
        }
        debugPrint("→ \(afrVersion)")
        NotificationCenter.default.post(name: .afrDeviceInfoAfrVersion, object: nil, userInfo: ["afrVersion": afrVersion])
    }

    /**
     Process data of BrokerEndpoint characteristic from `peripheral`.

     - Parameters:
        - peripheral: The FreeRTOS peripheral.
        - characteristic: The BrokerEndpoint characteristic.
     */
    public func didUpdateValueForBrokerEndpoint(peripheral _: CBPeripheral, characteristic: CBCharacteristic) {

        guard let value = characteristic.value, let brokerEndpoint = String(data: value, encoding: .utf8) else {
            debugPrint("Error (didUpdateValueForDeviceInfo): Invalid BrokerEndpoint")
            return
        }
        debugPrint("→ \(brokerEndpoint)")
        NotificationCenter.default.post(name: .afrDeviceInfoBrokerEndpoint, object: nil, userInfo: ["brokerEndpoint": brokerEndpoint])
    }

    /**
     Process data of Mtu characteristic from `peripheral`. It will also triger on mtu value change.

     - Parameters:
        - peripheral: The FreeRTOS peripheral.
        - characteristic: The Mtu characteristic.
     */
    public func didUpdateValueForMtu(peripheral: CBPeripheral, characteristic: CBCharacteristic) {

        guard let value = characteristic.value, let mtuStr = String(data: value, encoding: .utf8), let mtu = Int(mtuStr), mtu > 3 else {
            debugPrint("Error (didUpdateValueForDeviceInfo): Invalid Mtu")
            return
        }
        mtus[peripheral.identifier.uuidString] = mtu
        debugPrint("→ \(mtu)")
        NotificationCenter.default.post(name: .afrDeviceInfoMtu, object: nil, userInfo: ["mtu": mtu])
    }

    // Network Config Service

    /**
     Process data of ListNetwork characteristic from `peripheral`.

     - Parameters:
        - peripheral: The FreeRTOS peripheral.
        - characteristic: The ListNetwork characteristic.
     */
    public func didUpdateValueForListNetwork(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard let value = characteristic.value, let listNetworkResp = decode(ListNetworkResp.self, from: value) else {
            debugPrint("Error (didUpdateValueForListNetwork): Invalid Message")
            return
        }
        debugPrint("→ \(listNetworkResp)")

        if listNetworkResp.index < 0 {

            // Scaned networks also include saved networks so we filter that out when ssid and security are the same, update the saved network with the scaned bssid, rssi and hidden prams.

            if let indexSaved = networks[peripheral.identifier.uuidString]?[0].firstIndex(where: { network -> Bool in
                network.ssid == listNetworkResp.ssid && network.security == listNetworkResp.security
            }) {
                if let rssi = networks[peripheral.identifier.uuidString]?[0][indexSaved].rssi, rssi < listNetworkResp.rssi {
                    networks[peripheral.identifier.uuidString]?[0][indexSaved].status = listNetworkResp.status
                    networks[peripheral.identifier.uuidString]?[0][indexSaved].bssid = listNetworkResp.bssid
                    networks[peripheral.identifier.uuidString]?[0][indexSaved].rssi = listNetworkResp.rssi
                    networks[peripheral.identifier.uuidString]?[0][indexSaved].hidden = listNetworkResp.hidden
                }
                return
            }

            // Scaned networks sorted by rssi, if ssid and security are same, choose the network with stronger rssi.

            if let indexScaned = networks[peripheral.identifier.uuidString]?[1].firstIndex(where: { network -> Bool in
                network.ssid == listNetworkResp.ssid && network.security == listNetworkResp.security
            }) {
                if let rssi = networks[peripheral.identifier.uuidString]?[1][indexScaned].rssi, rssi < listNetworkResp.rssi {
                    networks[peripheral.identifier.uuidString]?[1][indexScaned] = listNetworkResp
                }
            } else {
                networks[peripheral.identifier.uuidString]?[1].append(listNetworkResp)
            }
            networks[peripheral.identifier.uuidString]?[1].sort(by: { networkA, networkB -> Bool in
                networkA.rssi > networkB.rssi
            })

        } else {

            // Saved networks sorted by index

            networks[peripheral.identifier.uuidString]?[0].append(listNetworkResp)
            networks[peripheral.identifier.uuidString]?[0].sort(by: { networkA, networkB -> Bool in
                networkA.index < networkB.index
            })
        }
        NotificationCenter.default.post(name: .afrDidListNetwork, object: nil, userInfo: ["peripheral": peripheral.identifier, "listNetworkResp": listNetworkResp])
    }

    /**
     Process data of SaveNetwork characteristic from `peripheral`.

     - Parameters:
        - peripheral: The FreeRTOS peripheral.
        - characteristic: The SaveNetwork characteristic.
     */
    public func didUpdateValueForSaveNetwork(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard let value = characteristic.value, let saveNetworkResp = decode(SaveNetworkResp.self, from: value) else {
            debugPrint("Error (didUpdateValueForSaveNetwork): Invalid Message")
            return
        }
        debugPrint("→ \(saveNetworkResp)")
        NotificationCenter.default.post(name: .afrDidSaveNetwork, object: nil, userInfo: ["peripheral": peripheral.identifier, "saveNetworkResp": saveNetworkResp])
    }

    /**
     Process data of EditNetwork characteristic from `peripheral`.

     - Parameters:
        - peripheral: The FreeRTOS peripheral.
        - characteristic: The EditNetwork characteristic.
     */
    public func didUpdateValueForEditNetwork(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard let value = characteristic.value, let editNetworkResp = decode(EditNetworkResp.self, from: value) else {
            debugPrint("Error (didUpdateValueForEditNetwork): Invalid Message")
            return
        }
        debugPrint("→ \(editNetworkResp)")
        NotificationCenter.default.post(name: .afrDidEditNetwork, object: nil, userInfo: ["peripheral": peripheral.identifier, "editNetworkResp": editNetworkResp])
    }

    /**
     Process data of DeleteNetwork characteristic from `peripheral`.

     - Parameters:
        - peripheral: The FreeRTOS peripheral.
        - characteristic: The DeleteNetwork characteristic.
     */
    public func didUpdateValueForDeleteNetwork(peripheral: CBPeripheral, characteristic: CBCharacteristic) {
        guard let value = characteristic.value, let deleteNetworkResp = decode(DeleteNetworkResp.self, from: value) else {
            debugPrint("Error (didUpdateValueForDeleteNetwork): Invalid Message")
            return
        }
        debugPrint("→ \(deleteNetworkResp)")
        NotificationCenter.default.post(name: .afrDidDeleteNetwork, object: nil, userInfo: ["peripheral": peripheral.identifier, "deleteNetworkResp": deleteNetworkResp])
    }
}

extension AmazonFreeRTOSManager {

    private func encode<T: Encborable>(_ object: T) -> Data? {
        if let encoded = CBOR.encode(object.toDictionary()) {
            return Data(encoded)
        }
        return nil
    }

    private func decode<T: Decborable>(_: T.Type, from data: Data) -> T? {
        if !data.isEmpty, let decoded = CBOR.decode(Array([UInt8](data))) as? NSDictionary {
            return T.toSelf(dictionary: decoded)
        }
        return nil
    }

    private func debugPrint(_ debugMessage: String) {
        guard isDebug else {
            return
        }
        debugMessages += "[\(Date())] \(debugMessage)\n"
        os_log("[FreeRTOS SDK] %@", log: .default, type: .debug, debugMessage)
    }
}
