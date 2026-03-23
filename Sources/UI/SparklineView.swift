import SwiftUI

/// A mini ECG-style sparkline drawn via Canvas from an array of Double values.
struct SparklineView: View {
    let data: [Double]
    let color: Color

    var body: some View {
        Canvas { context, size in
            guard data.count > 1 else { return }

            let maxVal = data.max() ?? 1.0
            let scale = maxVal > 0 ? maxVal : 1.0
            let stepX = size.width / CGFloat(data.count - 1)

            var path = Path()
            for (index, value) in data.enumerated() {
                let x = CGFloat(index) * stepX
                let y = size.height - (CGFloat(value / scale) * size.height)
                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            context.stroke(path, with: .color(color), lineWidth: 1.5)
        }
    }
}
