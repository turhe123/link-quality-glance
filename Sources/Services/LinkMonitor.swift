import AppKit
import Network
import UserNotifications

/// Drives the probe loop: probes the gateway and outside host on an interval, keeps rolling
/// windows, reads Wi-Fi metrics, derives the verdict and posts Poor notifications.
final class LinkMonitor: ObservableObject {
    @Published private(set) var gatewayWindow = SampleWindow()
    @Published private(set) var outsideWindow = SampleWindow()
    @Published private(set) var verdict: Verdict = .measuring
    @Published private(set) var explanation = "Collecting samples…"
    @Published private(set) var wifi: WiFiDetails?
    @Published private(set) var gateway: String?
    @Published private(set) var activeInterface: String?
    @Published private(set) var isOnline = true
    @Published var isPaused = false { didSet { if isPaused != oldValue { restart() } } }

    private let prober = TCPProber()
    private let pathMonitor = NWPathMonitor()
    private var generation = 0
    private var isAsleep = false
    private var lastOutsideHost = ""
    private var lastPathSignature = ""
    private var lastNotified = Date.distantPast
    private var previousVerdict: Verdict = .measuring

    var gatewayStats: LinkStats? { gatewayWindow.stats }
    var outsideStats: LinkStats? { outsideWindow.stats }
    var outsideHost: String { UserDefaults.standard.string(forKey: Keys.outsideHost) ?? Keys.defaultOutsideHost }

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { self?.handlePath(path) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.turhe123.linkqualityglance.path"))

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isAsleep = true
            self?.restart()
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.isAsleep = false
            self?.resetWindows()
            self?.restart()
        }
        restart()
    }

    /// Clears both windows, e.g. after wake or a connectivity change, to avoid false loss.
    func resetWindows() {
        generation += 1
        gatewayWindow.reset()
        outsideWindow.reset()
        refreshInfo()
        evaluate()
    }

    private func handlePath(_ path: NWPath) {
        let signature = "\(path.status)-\(path.availableInterfaces.first?.name ?? "")"
        guard signature != lastPathSignature else { return }
        lastPathSignature = signature
        isOnline = path.status == .satisfied
        resetWindows()
        restart()
    }

    /// Cancels the pending tick and schedules a new loop with the current settings.
    private func restart() {
        generation += 1
        evaluate()
        guard !isPaused, !isAsleep else { return }
        scheduleTick(generation: generation, delay: 0)
    }

    private func scheduleTick(generation token: Int, delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, token == self.generation, !self.isPaused, !self.isAsleep else { return }
            self.tick()
            let interval = UserDefaults.standard.double(forKey: Keys.probeInterval)
            self.scheduleTick(generation: token, delay: min(10, max(1, interval == 0 ? 2 : interval)))
        }
    }

    private func refreshInfo() {
        wifi = NetworkInfo.wifi()
        let routing = NetworkInfo.routing(wifiInterface: NetworkInfo.wifiInterfaceName)
        gateway = routing.gateway
        activeInterface = routing.primaryInterface
    }

    private func tick() {
        refreshInfo()
        guard isOnline else { evaluate(); return }

        let host = outsideHost
        if host != lastOutsideHost {
            lastOutsideHost = host
            outsideWindow.reset()
        }
        let token = generation
        if let gateway {
            prober.probe(host: gateway, port: 53) { [weak self] rtt in
                guard let self, token == self.generation else { return }
                self.gatewayWindow.append(rtt)
                self.evaluate()
            }
        }
        let target = TCPProber.parse(host, defaultPort: 443)
        prober.probe(host: target.host, port: target.port) { [weak self] rtt in
            guard let self, token == self.generation else { return }
            self.outsideWindow.append(rtt)
            self.evaluate()
        }
    }

    private func evaluate() {
        if !isOnline {
            verdict = .offline
            explanation = "Not connected. Join a Wi-Fi network to start measuring."
        } else if isPaused {
            verdict = .paused
            explanation = "Probes are paused."
        } else {
            (verdict, explanation) = VerdictEngine.evaluate(gateway: gatewayStats, hasGateway: gateway != nil,
                                                            outside: outsideStats, wifi: wifi,
                                                            thresholds: .fromDefaults())
        }
        if verdict == .poor, previousVerdict != .poor { notifyPoor() }
        previousVerdict = verdict
    }

    private func notifyPoor() {
        guard UserDefaults.standard.bool(forKey: Keys.notifyPoor),
              Date().timeIntervalSince(lastNotified) > 5 * 60 else { return }
        lastNotified = Date()
        let content = UNMutableNotificationContent()
        content.title = "Link quality is Poor"
        content.body = explanation
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
