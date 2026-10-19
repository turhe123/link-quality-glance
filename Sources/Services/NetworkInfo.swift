import AppKit
import CoreLocation
import CoreWLAN
import Foundation
import SystemConfiguration

/// Snapshot of the current Wi-Fi interface metrics read from CoreWLAN.
struct WiFiDetails: Equatable {
    var interfaceName: String
    var ssid: String?
    var rssi: Int
    var noise: Int
    var transmitRate: Double
    var channel: String

    /// Signal-to-noise ratio in dB.
    var snr: Int { rssi - noise }
}

/// Reads routing state from SystemConfiguration and Wi-Fi metrics from CoreWLAN.
enum NetworkInfo {
    private static let store = SCDynamicStoreCreate(nil, "LinkQualityGlance" as CFString, nil, nil)

    /// Returns the default gateway and the primary (default-route) interface name.
    /// When a VPN owns the default route without a router, falls back to the Wi-Fi service's router.
    static func routing(wifiInterface: String?) -> (gateway: String?, primaryInterface: String?) {
        guard let store else { return (nil, nil) }
        let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        let primary = global?["PrimaryInterface"] as? String
        if let router = global?["Router"] as? String, !router.isEmpty {
            return (router, primary)
        }
        let pattern = "State:/Network/Service/.*/IPv4" as CFString
        let keys = (SCDynamicStoreCopyKeyList(store, pattern) as? [String]) ?? []
        for key in keys {
            guard let dict = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                  let router = dict["Router"] as? String else { continue }
            let name = dict["InterfaceName"] as? String
            if wifiInterface == nil || name == wifiInterface { return (router, primary) }
        }
        return (nil, primary)
    }

    /// Reads the current Wi-Fi metrics, or `nil` when Wi-Fi is off or not associated.
    static func wifi() -> WiFiDetails? {
        guard let iface = CWWiFiClient.shared().interface(), iface.powerOn(),
              let channel = iface.wlanChannel(), iface.rssiValue() != 0 else { return nil }
        let band: String
        switch channel.channelBand {
        case .band2GHz: band = "2.4 GHz"
        case .band5GHz: band = "5 GHz"
        case .band6GHz: band = "6 GHz"
        default: band = "?"
        }
        let width: String
        switch channel.channelWidth {
        case .width20MHz: width = "20 MHz"
        case .width40MHz: width = "40 MHz"
        case .width80MHz: width = "80 MHz"
        case .width160MHz: width = "160 MHz"
        default: width = ""
        }
        let channelText = "\(channel.channelNumber) (\(band)\(width.isEmpty ? "" : ", \(width)"))"
        return WiFiDetails(interfaceName: iface.interfaceName ?? "Wi-Fi",
                           ssid: iface.ssid(),
                           rssi: iface.rssiValue(),
                           noise: iface.noiseMeasurement(),
                           transmitRate: iface.transmitRate(),
                           channel: channelText)
    }

    /// Name of the Wi-Fi interface (e.g. `en0`) even when not associated.
    static var wifiInterfaceName: String? { CWWiFiClient.shared().interface()?.interfaceName }
}

/// Tracks Location authorization, which macOS requires before revealing the Wi-Fi network name.
/// The verdict works without it, so the name is purely optional.
final class LocationPermission: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var status: CLAuthorizationStatus
    private let manager = CLLocationManager()

    override init() {
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    var isAuthorized: Bool { status == .authorizedAlways || status == .authorized }
    var isDenied: Bool { status == .denied || status == .restricted }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { self.status = manager.authorizationStatus }
    }
}
