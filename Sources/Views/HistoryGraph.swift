import SwiftUI

/// Canvas line graph of the last five minutes of readings, with an optional dashed alert line.
struct HistoryGraph: View {
    let values: [Double]
    let alertLevel: Double?
    private let range = 20.0...110.0
    private let capacity = 1200

    var body: some View {
        Canvas { context, size in
            func y(_ db: Double) -> CGFloat {
                let clamped = min(max(db, range.lowerBound), range.upperBound)
                return size.height * (1 - (clamped - range.lowerBound) / (range.upperBound - range.lowerBound))
            }
            for grid in stride(from: 40.0, through: 100.0, by: 20.0) {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y(grid)))
                line.addLine(to: CGPoint(x: size.width, y: y(grid)))
                context.stroke(line, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
                context.draw(Text("\(Int(grid))").font(.system(size: 8)).foregroundColor(.secondary),
                             at: CGPoint(x: 2, y: y(grid) - 5), anchor: .leading)
            }
            if let alertLevel {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y(alertLevel)))
                line.addLine(to: CGPoint(x: size.width, y: y(alertLevel)))
                context.stroke(line, with: .color(.red.opacity(0.7)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
            guard values.count > 1 else { return }
            let step = size.width / CGFloat(capacity - 1)
            let startX = size.width - CGFloat(values.count - 1) * step
            var path = Path()
            for (i, value) in values.enumerated() {
                let point = CGPoint(x: startX + CGFloat(i) * step, y: y(value))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            var fill = path
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: startX, y: size.height))
            fill.closeSubpath()
            context.fill(fill, with: .linearGradient(Gradient(colors: [.accentColor.opacity(0.35), .clear]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(path, with: .color(.accentColor), lineWidth: 1.2)
        }
        .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.4)))
        .overlay(alignment: .bottomTrailing) {
            Text("last 5 min").font(.system(size: 8)).foregroundStyle(.secondary).padding(3)
        }
    }
}
