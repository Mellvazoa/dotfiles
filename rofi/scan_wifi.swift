import Foundation
import CoreWLAN

guard let iface = CWWiFiClient.shared().interface() else { exit(0) }
let currentSSID = iface.ssid() ?? ""

do {
    let networks = try iface.scanForNetworks(withSSID: nil)
    var seen = Set<String>()
    let sorted = networks.sorted { $0.rssiValue > $1.rssiValue }
    for net in sorted {
        guard let ssid = net.ssid, !ssid.isEmpty, !seen.contains(ssid) else { continue }
        seen.insert(ssid)
        let isCurrent = (ssid == currentSSID) ? "1" : "0"
        let sec = net.supportsSecurity(.wpa3Personal) ? "WPA3" :
                  (net.supportsSecurity(.wpa2Personal) ? "WPA2" :
                  (net.supportsSecurity(.none) ? "Open" : "Secured"))
        print("\(ssid)\t\(net.rssiValue)\t\(sec)\t\(isCurrent)")
    }
} catch {
    exit(1)
}
