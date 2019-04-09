import CoreBluetooth

/// BLE services used by the SDK.
public struct AmazonFreeRTOSGattService {
    /// Device Info Service. This is a required service for Amazon FreeRTOS.
    static let DeviceInfo = CBUUID(string: "8a7f1168-48af-4efb-83b5-e679f932ff00")
    /// Network Config Service.
    static let NetworkConfig = CBUUID(string: "3113a187-4b9f-4f9a-aa83-c614e11bff00")
}

/// BLE characteristics used by the SDK.
public struct AmazonFreeRTOSGattCharacteristic {
    /// The version of the Amazon FreeRTOS.
    static let AfrVersion = CBUUID(string: "8a7f1168-48af-4efb-83b5-e679f932ff01")
    /// The broker endpoint of the mqtt.
    static let BrokerEndpoint = CBUUID(string: "8a7f1168-48af-4efb-83b5-e679f932ff02")
    /// The mtu of the device.
    static let Mtu = CBUUID(string: "8a7f1168-48af-4efb-83b5-e679f932ff03")

    /// List saved and scanned wifi networks.
    static let ListNetwork = CBUUID(string: "3113a187-4b9f-4f9a-aa83-c614e11bff01")
    /// Save wifi network.
    static let SaveNetwork = CBUUID(string: "3113a187-4b9f-4f9a-aa83-c614e11bff02")
    /// Edit wifi network.
    static let EditNetwork = CBUUID(string: "3113a187-4b9f-4f9a-aa83-c614e11bff03")
    /// Delete saved wifi network.
    static let DeleteNetwork = CBUUID(string: "3113a187-4b9f-4f9a-aa83-c614e11bff04")
}
