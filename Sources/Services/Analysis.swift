import SwiftUI

/// Summary numbers computed from a rolling window of probe samples.
struct LinkStats: Equatable {
    var average: Double?
    var jitter: Double?
    var loss: Double
    var count: Int
}

/// Rolling window of the most recent probe results; `nil` entries are timeouts.
struct SampleWindow: Equatable {
    var capacity = 60
    private(set) var samples: [Double?] = []

    mutating func append(_ sample: Double?) {
        samples.append(sample)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }

    mutating func reset() { samples.removeAll() }

    /// Statistics, or `nil` while fewer than three samples exist (shown as Measuring).
    var stats: LinkStats? {
        guard samples.count >= 3 else { return nil }
        let ok = samples.compactMap { $0 }
        let loss = Double(samples.count - ok.count) / Double(samples.count) * 100
        let average = ok.isEmpty ? nil : ok.reduce(0, +) / Double(ok.count)
        var jitter: Double?
        if ok.count >= 2 {
            jitter = zip(ok.dropFirst(), ok).map { abs($0 - $1) }.reduce(0, +) / Double(ok.count - 1)
        }
        return LinkStats(average: average, jitter: jitter, loss: loss, count: samples.count)
    }
}

/// User-editable limits separating Good, Check and Poor.
struct Thresholds {
    var goodLatency: Double, goodLoss: Double, goodJitter: Double
    var poorLatency: Double, poorLoss: Double, poorJitter: Double

    static func fromDefaults(_ d: UserDefaults = .standard) -> Thresholds {
        func v(_ key: String, _ fallback: Double) -> Double { d.object(forKey: key) == nil ? fallback : d.double(forKey: key) }
        return Thresholds(goodLatency: v(Keys.goodLatency, 50), goodLoss: v(Keys.goodLoss, 1), goodJitter: v(Keys.goodJitter, 20),
                          poorLatency: v(Keys.poorLatency, 150), poorLoss: v(Keys.poorLoss, 5), poorJitter: v(Keys.poorJitter, 50))
    }
}

/// The overall link health label shown in the menu bar.
enum Verdict: Int, Comparable {
    case offline, paused, measuring, good, check, poor

    static func < (a: Verdict, b: Verdict) -> Bool { a.rawValue < b.rawValue }

    var title: String {
        switch self {
        case .offline: return "Offline"
        case .paused: return "Paused"
        case .measuring: return "Measuring…"
        case .good: return "Good"
        case .check: return "Check"
        case .poor: return "Poor"
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    var nsColor: NSColor {
        switch self {
        case .good: return .systemGreen
        case .check: return .systemOrange
        case .poor: return .systemRed
        case .offline, .paused, .measuring: return .systemGray
        }
    }

    var symbol: String {
        switch self {
        case .offline: return "wifi.slash"
        case .paused: return "pause.circle"
        default: return "wifi"
        }
    }
}

/// Rules engine that turns gateway and outside-host statistics into a verdict plus a one-line explanation.
enum VerdictEngine {
    static func level(_ s: LinkStats, _ t: Thresholds) -> Verdict {
        guard let avg = s.average else { return .poor }
        let jitter = s.jitter ?? 0
        if s.loss >= t.poorLoss || avg >= t.poorLatency || jitter >= t.poorJitter { return .poor }
        if s.loss < t.goodLoss && avg < t.goodLatency && jitter < t.goodJitter { return .good }
        return .check
    }

    private static func issue(_ s: LinkStats, _ t: Thresholds) -> String {
        guard let avg = s.average else { return "No replies" }
        if s.loss >= t.goodLoss { return String(format: "%.0f%% packet loss", s.loss) }
        if (s.jitter ?? 0) >= t.goodJitter { return "High jitter" }
        if avg >= t.goodLatency { return "High latency" }
        return "Unstable timing"
    }

    static func evaluate(gateway: LinkStats?, hasGateway: Bool, outside: LinkStats?,
                         wifi: WiFiDetails?, thresholds t: Thresholds) -> (Verdict, String) {
        guard let outside, (gateway != nil || !hasGateway) else {
            return (.measuring, "Collecting samples…")
        }
        let outsideLevel = level(outside, t)
        let gatewayLevel = gateway.map { level($0, t) } ?? .good
        let overall = max(outsideLevel, gatewayLevel)
        let weakSignal = wifi.map { $0.rssi < -72 || $0.snr < 20 } ?? false
        let signalNote = weakSignal ? " Signal is weak (\(wifi?.rssi ?? 0) dBm)." : ""

        if overall == .good {
            let base = wifi == nil ? "Local link and internet look healthy." : "Wi-Fi and internet look healthy."
            return (.good, base + signalNote)
        }
        if let gateway, gatewayLevel > .good {
            let link = wifi == nil ? "your local network" : "Wi-Fi trouble"
            return (overall, "\(issue(gateway, t)) on the gateway — hints at \(link).\(signalNote)")
        }
        let prefix = hasGateway ? "\(issue(outside, t)) only on the outside host" : "\(issue(outside, t)) on the outside host (no gateway found)"
        return (overall, "\(prefix) — hints at your provider.")
    }
}

/// `UserDefaults` / `@AppStorage` keys shared by the monitor and the settings UI.
enum Keys {
    static let outsideHost = "outsideHost"
    static let probeInterval = "probeInterval"
    static let showLatency = "showLatencyInMenuBar"
    static let notifyPoor = "notifyWhenPoor"
    static let goodLatency = "goodLatency", goodLoss = "goodLoss", goodJitter = "goodJitter"
    static let poorLatency = "poorLatency", poorLoss = "poorLoss", poorJitter = "poorJitter"
    static let defaultOutsideHost = "1.1.1.1"
}
