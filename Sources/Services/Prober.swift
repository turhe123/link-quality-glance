import Foundation
import Network

/// Measures round-trip time by timing a TCP handshake with `NWConnection`.
/// ICMP needs raw sockets, so a short TCP connect is used instead. A refused
/// connection still counts as a successful round trip because it proves reachability.
final class TCPProber {
    private let queue = DispatchQueue(label: "com.turhe123.linkqualityglance.probe")

    /// Probes `host:port` and calls `completion` on the main queue with the RTT in
    /// milliseconds, or `nil` when the probe timed out or failed (counted as loss).
    func probe(host: String, port: UInt16, timeout: TimeInterval = 1.0, completion: @escaping (Double?) -> Void) {
        guard !host.isEmpty, let nwPort = NWEndpoint.Port(rawValue: port) else {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        let parameters = NWParameters.tcp
        if let tcp = parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options {
            tcp.connectionTimeout = Int(max(1, timeout.rounded(.up)))
            tcp.noDelay = true
        }
        parameters.preferNoProxies = true
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        let start = DispatchTime.now().uptimeNanoseconds
        var finished = false // only touched on `queue`

        func finish(reachable: Bool) {
            guard !finished else { return }
            finished = true
            connection.stateUpdateHandler = nil
            connection.cancel()
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            let result: Double? = reachable && elapsed <= timeout * 1000 ? elapsed : nil
            DispatchQueue.main.async { completion(result) }
        }

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                finish(reachable: true)
            case .waiting(let error):
                if Self.isRefused(error) { finish(reachable: true) }
            case .failed(let error):
                finish(reachable: Self.isRefused(error))
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + timeout) { finish(reachable: false) }
    }

    private static func isRefused(_ error: NWError) -> Bool {
        if case .posix(let code) = error, code == .ECONNREFUSED { return true }
        return false
    }

    /// Splits user input such as `1.1.1.1`, `example.com:443` or `[::1]:53` into host and port.
    static func parse(_ input: String, defaultPort: UInt16) -> (host: String, port: UInt16) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]") {
            let host = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
            let rest = trimmed[trimmed.index(after: close)...]
            let port = rest.hasPrefix(":") ? UInt16(rest.dropFirst()) : nil
            return (host, port ?? defaultPort)
        }
        let parts = trimmed.split(separator: ":")
        if parts.count == 2, let port = UInt16(parts[1]) {
            return (String(parts[0]), port)
        }
        return (trimmed, defaultPort)
    }
}
