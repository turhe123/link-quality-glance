import SwiftUI

/// Dropdown window: verdict and explanation, sparklines, key numbers, Wi-Fi details and footer actions.
struct ContentView: View {
    @ObservedObject var monitor: LinkMonitor
    @ObservedObject var location: LocationPermission
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if monitor.verdict == .offline {
                Label("Join a Wi-Fi network from the Wi-Fi menu to start measuring.", systemImage: "wifi.exclamationmark")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                charts
                numbers
                wifiBlock
            }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: monitor.verdict.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(monitor.verdict.color)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(monitor.verdict.title).font(.title2.bold())
                Text(monitor.explanation).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var charts: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gateway \(monitor.gateway ?? "not found")").font(.caption).foregroundStyle(.secondary)
            Sparkline(samples: monitor.gatewayWindow.samples, capacity: monitor.gatewayWindow.capacity, color: .accentColor)
            Text("Outside host \(monitor.outsideHost)").font(.caption).foregroundStyle(.secondary)
            Sparkline(samples: monitor.outsideWindow.samples, capacity: monitor.outsideWindow.capacity, color: .purple)
        }
    }

    private var numbers: some View {
        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 4) {
            GridRow {
                Text("").gridColumnAlignment(.leading)
                Text("Latency"); Text("Jitter"); Text("Loss")
            }
            .font(.caption.bold()).foregroundStyle(.secondary)
            statsRow("Gateway", monitor.gatewayStats)
            statsRow("Outside", monitor.outsideStats)
        }
        .font(.callout.monospacedDigit())
    }

    private func statsRow(_ title: String, _ stats: LinkStats?) -> some View {
        GridRow {
            Text(title)
            if let stats {
                Text(stats.average.map { String(format: "%.0f ms", $0) } ?? "—")
                Text(stats.jitter.map { String(format: "%.1f ms", $0) } ?? "—")
                Text(String(format: "%.0f%%", stats.loss))
            } else {
                Text("Measuring").foregroundStyle(.secondary).gridCellColumns(3)
            }
        }
    }

    @ViewBuilder private var wifiBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Interface: \(monitor.activeInterface ?? "—")").font(.caption).foregroundStyle(.secondary)
            if let wifi = monitor.wifi {
                detail("Network", wifi.ssid ?? "Hidden (needs Location)")
                detail("Signal", "\(wifi.rssi) dBm  ·  noise \(wifi.noise) dBm  ·  SNR \(wifi.snr) dB")
                detail("Tx rate", String(format: "%.0f Mbps", wifi.transmitRate))
                detail("Channel", wifi.channel)
                if wifi.ssid == nil { locationHint }
            } else {
                Text("Not on Wi-Fi — Wi-Fi details unavailable.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var locationHint: some View {
        if location.isDenied {
            Button("Allow Location in System Settings to show the name") { location.openSystemSettings() }
                .buttonStyle(.link).font(.caption)
        } else if !location.isAuthorized {
            Button("Show network name…") { location.request() }
                .buttonStyle(.link).font(.caption)
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            Text(value).textSelection(.enabled)
        }
        .font(.callout)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button { Support.openDonate() } label: {
                Label("Support / Donate ❤️", systemImage: "heart.fill").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            HStack {
                Button(monitor.isPaused ? "Resume" : "Pause") { monitor.isPaused.toggle() }
                Spacer()
                Button("Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
}
