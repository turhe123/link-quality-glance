# LinkQualityGlance — specification

**Tagline:** A menu bar verdict on your Wi-Fi health from gateway latency, packet loss, jitter and signal quality.

**Category:** System Monitoring

**Inspired by (paid):** MacWiFi ($10 one-time)

**Frameworks:** SwiftUI, AppKit, CoreWLAN, Network, SystemConfiguration, CoreLocation

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: MacWiFi is a menu bar Wi-Fi diagnostics app sold for about 10 dollars as a one-time purchase after a free trial. It measures latency, packet loss and jitter and condenses them into a simple Good, Check or Poor verdict, so people on video calls can tell whether the problem is their Wi-Fi or the internet. It is repeatedly recommended in lists of menu bar network tools, showing real demand. Our clean-room version offers the same quick diagnosis.

Feature set: every two seconds the app sends a tiny probe to the default gateway and to a user chosen outside host, records the round trip time, and keeps a rolling window of the last 60 samples for each. From these it calculates average latency, jitter as mean difference between consecutive samples, and loss percentage for timeouts. It also reads Wi-Fi signal strength, noise, transmit rate and channel from the current interface. A rules engine labels the link Good when loss is below 1 percent and latency under 50 milliseconds, Check for moderate values, and Poor otherwise, with a one line explanation such as high jitter on the gateway, which hints at Wi-Fi trouble, versus loss only on the outside host, which hints at the provider. Thresholds are editable.

UI spec: a MenuBarExtra whose icon is a colored Wi-Fi glyph matching the verdict and an optional latency number. The dropdown window shows the verdict and explanation at the top, two live sparklines (gateway and outside host), a table of key numbers, and the Wi-Fi details block. Footer entries: Pause, Settings, Quit. Settings fields: outside host (default a public DNS address), probe interval (1 to 10 seconds), thresholds for Good and Poor, show latency in menu bar, notify when verdict becomes Poor, launch at login. Empty state: when not connected to Wi-Fi, show Offline and a hint to join a network. Shortcut: Command comma for Settings.

Technical approach: ICMP needs raw sockets, so probe with a short TCP connection using NWConnection to port 53 or 443 and time the handshake, with a 1 second timeout counted as loss. Find the gateway address with SystemConfiguration by reading the global IPv4 state through SCDynamicStoreCopyValue for the router key. Wi-Fi metrics come from CWWiFiClient.shared().interface() properties rssiValue, noiseMeasurement, transmitRate and wlanChannel. Reading the network name needs Location authorization via CLLocationManager and a usage description string, but the verdict works without it, so make the name optional. Watch connectivity changes with NWPathMonitor to reset the window. Notifications use UserNotifications with a cooldown of 5 minutes. Settings persist in AppStorage and launch at login uses SMAppService.mainApp. The sandbox needs the outgoing network client entitlement.

Edge cases: when the Mac sleeps, pause probes and clear the window on wake to avoid false loss. If the gateway refuses TCP connections, a refused response still counts as a successful round trip because it proves reachability. VPNs may change the default route, so show the active interface name. Guard against divide by zero when fewer than three samples exist by showing Measuring. Ethernet connections omit Wi-Fi details but still show latency.
