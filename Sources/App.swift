import AppKit
import SwiftUI

/// App entry point: a menu bar extra showing the verdict, plus a Settings scene.
@main
struct LinkQualityGlanceApp: App {
    @StateObject private var monitor = LinkMonitor()
    @StateObject private var location = LocationPermission()

    var body: some Scene {
        MenuBarExtra {
            ContentView(monitor: monitor, location: location)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(location: location)
        }
    }
}

/// Opens the donation page.
enum Support {
    static func openDonate() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}

/// Menu bar icon: a Wi-Fi glyph tinted with the verdict colour and an optional latency number.
struct MenuBarLabel: View {
    @ObservedObject var monitor: LinkMonitor
    @AppStorage(Keys.showLatency) private var showLatency = true

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: icon)
            if showLatency, monitor.verdict >= .good, let avg = monitor.outsideStats?.average {
                Text("\(Int(avg.rounded())) ms")
            }
        }
        .accessibilityLabel("Link quality: \(monitor.verdict.title)")
    }

    private var icon: NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            .applying(.init(paletteColors: [monitor.verdict.nsColor]))
        let image = NSImage(systemSymbolName: monitor.verdict.symbol, accessibilityDescription: monitor.verdict.title)?
            .withSymbolConfiguration(config) ?? NSImage()
        image.isTemplate = false
        return image
    }
}
