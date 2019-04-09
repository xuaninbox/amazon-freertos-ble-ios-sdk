/// Network security types.
public enum NetworkSecurityType: Int {
    /// Open.
    case open = 0
    /// Wep.
    case wep = 1
    /// Wpa.
    case wpa = 2
    /// Wpa 2.
    case wpa2 = 3
    /// Not Supported.
    case notSupported = 4
}

/// Network statuses.
public enum NetworkOpStatus: Int {
    /// Success.
    case success = 0
    /// Failure.
    case failure = 1
    /// Timeout.
    case timeout = 2
    /// Not Supported.
    case notSupported = 3
}

/// Keys for cbor.
public enum CborKey: String {
    /// bssid.
    case bssid = "b"
    /// connected.
    case connected = "e"
    /// hidden.
    case hidden = "f"
    /// index.
    case index = "g"
    /// maxNetworks.
    case maxNetworks = "h"
    /// newIndex.
    case newIndex = "j"
    /// psk.
    case psk = "m"
    /// rssi.
    case rssi = "p"
    /// security.
    case security = "q"
    /// ssid.
    case ssid = "r"
    /// status.
    case status = "s"
    /// timeout.
    case timeout = "t"
    /// connect.
    case connect = "y"
}
