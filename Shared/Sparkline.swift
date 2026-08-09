import SwiftUI
import ClaudeGaugeCore

/// A small filled line chart of daily token totals.
///
/// Hand-drawn with `Path` rather than Swift Charts: this renders inside the
/// menu bar popover *and* inside the widget extension, and a widget's
/// snapshot rendering is far cheaper with a plain shape than with a full
/// charting stack. The bigger, interactive chart in the History window does
/// use Swift Charts, where that cost is fine.
struct Sparkline: View {
    let values: [Int]
    var tint: Color = .accentColor

    private var normalized: [Double] {
        guard let maximum = values.max(), maximum > 0 else {
            return Array(repeating: 0, count: values.count)
        }
        return values.map { Double($0) / Double(maximum) }
    }

    var body: some View {
        GeometryReader { geo in
            let points = normalized
            if points.count < 2 {
                // A single day can't describe a trend; an empty frame reads
                // better than a misleading flat line.
                Color.clear
            } else {
                let step = geo.size.width / CGFloat(points.count - 1)
                let coordinates = points.enumerated().map { index, value in
                    CGPoint(
                        x: CGFloat(index) * step,
                        y: geo.size.height - (CGFloat(value) * geo.size.height)
                    )
                }

                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height))
                        path.addLine(to: coordinates[0])
                        for point in coordinates.dropFirst() { path.addLine(to: point) }
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.35), tint.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        path.move(to: coordinates[0])
                        for point in coordinates.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    Sparkline(values: [3, 9, 4, 12, 8, 15, 6], tint: .purple)
        .frame(width: 160, height: 40)
        .padding()
}
