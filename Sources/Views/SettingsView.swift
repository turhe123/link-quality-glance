import ServiceManagement
import SwiftUI
import UserNotifications

/// Settings window: outside host, probe interval, thresholds, menu bar, notifications and login options.
struct SettingsView: View {
    @ObservedObject var location: LocationPermission
    @AppStorage(Keys.outsideHost) private var outsideHost = Keys.defaultOutsideHost
    @AppStorage(Keys.probeInterval) private var probeInterval = 2.0
    @AppStorage(Keys.showLatency) private var showLatency = true
    @AppStorage(Keys.notifyPoor) private var notifyPoor = false
    @AppStorage(Keys.goodLatency) private var goodLatency = 50.0
    @AppStorage(Keys.goodLoss) private var goodLoss = 1.0
    @AppStorage(Keys.goodJitter) private var goodJitter = 20.0
    @AppStorage(Keys.poorLatency) private var poorLatency = 150.0
    @AppStorage(Keys.poorLoss) private var poorLoss = 5.0
    @AppStorage(Keys.poorJitter) private var poorJitter = 50.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var message: String?

    var body: some View {
        Form {
            Section("Probing") {
                TextField("Outside host", text: $outsideHost, prompt: Text(Keys.defaultOutsideHost))
                Text("IP or hostname, optionally with :port (default port 443). The gateway is probed on port 53.")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper(value: $probeInterval, in: 1...10, step: 1) {
                    Text("Probe interval: \(Int(probeInterval)) s")
                }
            }
            Section("Thresholds — Good when all below") {
                threshold("Latency (ms)", $goodLatency)
                threshold("Loss (%)", $goodLoss)
                threshold("Jitter (ms)", $goodJitter)
            }
            Section("Thresholds — Poor when any at or above") {
                threshold("Latency (ms)", $poorLatency)
                threshold("Loss (%)", $poorLoss)
                threshold("Jitter (ms)", $poorJitter)
            }
            Section("General") {
                Toggle("Show latency in menu bar", isOn: $showLatency)
                Toggle("Notify when verdict becomes Poor", isOn: $notifyPoor)
                    .onChange(of: notifyPoor) { _, enabled in if enabled { requestNotifications() } }
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                HStack {
                    Text("Wi-Fi network name")
                    Spacer()
                    if location.isAuthorized {
                        Text("Allowed").foregroundStyle(.secondary)
                    } else if location.isDenied {
                        Button("Open Privacy Settings") { location.openSystemSettings() }
                    } else {
                        Button("Allow Location…") { location.request() }
                    }
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
            }
            Section {
                Button { Support.openDonate() } label: {
                    Label("Support / Donate ❤️", systemImage: "heart.fill")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func threshold(_ title: String, _ value: Binding<Double>) -> some View {
        TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
            .multilineTextAlignment(.trailing)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            message = nil
        } catch {
            message = "Couldn't update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                if !granted {
                    message = "Notifications are off. Enable them in System Settings › Notifications."
                }
            }
        }
    }
}
