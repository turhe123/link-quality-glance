import SwiftUI

/// Small line chart of RTT samples; timeouts are drawn as red ticks along the baseline.
struct Sparkline: View {
    let samples: [Double?]
    let capacity: Int
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let values = samples.compactMap { $0 }
            let maxValue = max(values.max() ?? 1, 1) * 1.15
            let step = geo.size.width / CGFloat(max(capacity - 1, 1))
            let offset = CGFloat(capacity - samples.count) * step
            let point = { (i: Int, v: Double) -> CGPoint in
                CGPoint(x: offset + CGFloat(i) * step, y: geo.size.height * (1 - CGFloat(v / maxValue)))
            }
            ZStack {
                Path { path in
                    var started = false
                    for (i, sample) in samples.enumerated() {
                        guard let v = sample else { started = false; continue }
                        if started { path.addLine(to: point(i, v)) } else { path.move(to: point(i, v)); started = true }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                Path { path in
                    for (i, sample) in samples.enumerated() where sample == nil {
                        let x = offset + CGFloat(i) * step
                        path.move(to: CGPoint(x: x, y: geo.size.height))
                        path.addLine(to: CGPoint(x: x, y: geo.size.height - 6))
                    }
                }
                .stroke(Color.red, lineWidth: 1.5)
            }
        }
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.05)))
    }
}
