import PencilKit
import UIKit

/// Converts between PencilKit drawings and the web-compatible JSON annotation format.
enum AnnotationConverter {

    /// Convert stored annotation data to a PencilKit drawing.
    /// Scales from native image coordinates → display coordinates.
    static func toDrawing(_ annotation: AnnotationData, imageSize: CGSize, displaySize: CGSize) -> PKDrawing {
        guard !annotation.lines.isEmpty else { return PKDrawing() }

        let scaleX = displaySize.width / imageSize.width
        let scaleY = displaySize.height / imageSize.height

        var strokes: [PKStroke] = []
        for line in annotation.lines {
            // Skip arrows (have pointerLength) — render these as static overlay instead
            if line.pointerLength != nil { continue }

            guard line.points.count >= 4 else { continue }
            let color = colorFromHex(line.stroke) ?? .red
            let ink = PKInk(.pen, color: color)
            let width = line.strokeWidth * scaleX

            var controlPoints: [PKStrokePoint] = []
            for i in stride(from: 0, to: line.points.count - 1, by: 2) {
                let x = line.points[i] * scaleX
                let y = line.points[i + 1] * scaleY
                controlPoints.append(PKStrokePoint(
                    location: CGPoint(x: x, y: y),
                    timeOffset: 0,
                    size: CGSize(width: width, height: width),
                    opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
                ))
            }
            guard controlPoints.count >= 2 else { continue }
            let path = PKStrokePath(controlPoints: controlPoints, creationDate: Date())
            strokes.append(PKStroke(ink: ink, path: path))
        }

        return PKDrawing(strokes: strokes)
    }

    /// Convert a PencilKit drawing to the web-compatible annotation format.
    /// Scales from display coordinates → native image coordinates.
    static func fromDrawing(_ drawing: PKDrawing, imageSize: CGSize, displaySize: CGSize) -> AnnotationData {
        let scaleX = imageSize.width / displaySize.width
        let scaleY = imageSize.height / displaySize.height

        var lines: [AnnotationLine] = []
        for stroke in drawing.strokes {
            var points: [Double] = []
            let path = stroke.path
            let count = path.count
            for i in 0..<count {
                let point = path[i].location
                points.append(Double(point.x * scaleX))
                points.append(Double(point.y * scaleY))
            }
            guard points.count >= 4 else { continue }

            let color = stroke.ink.color
            let hex = hexFromColor(color)
            let strokeWidth = Double(path[0].size.width * scaleX)

            lines.append(AnnotationLine(
                points: points,
                stroke: hex,
                strokeWidth: strokeWidth,
                lineCap: "round",
                lineJoin: "round",
                pointerLength: nil,
                pointerWidth: nil
            ))
        }

        return AnnotationData(version: 2, lines: lines, labels: [])
    }

    // MARK: - Color Conversion

    static func colorFromHex(_ hex: String) -> UIColor? {
        var hexStr = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexStr.hasPrefix("#") { hexStr.removeFirst() }
        guard hexStr.count == 6, let rgb = UInt64(hexStr, radix: 16) else { return nil }
        return UIColor(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }

    static func hexFromColor(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02x%02x%02x", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
