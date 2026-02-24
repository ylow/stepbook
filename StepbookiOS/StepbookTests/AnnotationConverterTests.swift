import XCTest
import PencilKit
@testable import Stepbook

final class AnnotationConverterTests: XCTestCase {

    func testEmptyAnnotationsProduceEmptyDrawing() {
        let annotation = AnnotationData()
        let imageSize = CGSize(width: 1000, height: 800)
        let displaySize = CGSize(width: 500, height: 400)
        let drawing = AnnotationConverter.toDrawing(annotation, imageSize: imageSize, displaySize: displaySize)
        XCTAssertTrue(drawing.strokes.isEmpty)
    }

    func testAnnotationWithLinesConvertsToDrawing() {
        let annotation = AnnotationData(
            version: 2,
            lines: [
                AnnotationLine(
                    points: [100, 100, 200, 100, 300, 150],
                    stroke: "#ff0000",
                    strokeWidth: 4,
                    lineCap: "round",
                    lineJoin: "round",
                    pointerLength: nil,
                    pointerWidth: nil
                )
            ],
            labels: []
        )
        let imageSize = CGSize(width: 1000, height: 800)
        let displaySize = CGSize(width: 500, height: 400)
        let drawing = AnnotationConverter.toDrawing(annotation, imageSize: imageSize, displaySize: displaySize)
        XCTAssertEqual(drawing.strokes.count, 1)
    }

    func testArrowLinesAreSkipped() {
        let annotation = AnnotationData(
            version: 2,
            lines: [
                AnnotationLine(
                    points: [0, 0, 100, 100],
                    stroke: "#ff0000",
                    strokeWidth: 4,
                    lineCap: "round",
                    lineJoin: "round",
                    pointerLength: 10,
                    pointerWidth: 10
                )
            ],
            labels: []
        )
        let drawing = AnnotationConverter.toDrawing(annotation, imageSize: CGSize(width: 1000, height: 1000), displaySize: CGSize(width: 500, height: 500))
        XCTAssertTrue(drawing.strokes.isEmpty, "Arrow lines should be skipped in PencilKit conversion")
    }

    func testColorFromHex() {
        let color = AnnotationConverter.colorFromHex("#ff0000")
        XCTAssertNotNil(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color?.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }

    func testColorFromHexBlue() {
        let color = AnnotationConverter.colorFromHex("#0000ff")
        XCTAssertNotNil(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color?.getRed(&r, green: &g, blue: &b, alpha: &a)
        XCTAssertEqual(r, 0.0, accuracy: 0.01)
        XCTAssertEqual(b, 1.0, accuracy: 0.01)
    }

    func testHexFromColor() {
        let hex = AnnotationConverter.hexFromColor(.red)
        XCTAssertEqual(hex.lowercased(), "#ff0000")
    }

    func testColorRoundTrip() {
        let original = "#ab12cd"
        guard let color = AnnotationConverter.colorFromHex(original) else {
            XCTFail("Failed to parse hex color")
            return
        }
        let result = AnnotationConverter.hexFromColor(color)
        XCTAssertEqual(result.lowercased(), original.lowercased())
    }

    func testDrawingToAnnotationScalesCoordinates() {
        // Build a simple PKDrawing with known points
        let imageSize = CGSize(width: 1000, height: 800)
        let displaySize = CGSize(width: 500, height: 400)

        var points = [PKStrokePoint]()
        let positions: [(CGFloat, CGFloat)] = [(50, 40), (100, 80)]
        for (x, y) in positions {
            points.append(PKStrokePoint(
                location: CGPoint(x: x, y: y),
                timeOffset: 0, size: CGSize(width: 4, height: 4),
                opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            ))
        }
        let path = PKStrokePath(controlPoints: points, creationDate: Date())
        let ink = PKInk(.pen, color: .red)
        let stroke = PKStroke(ink: ink, path: path)
        let drawing = PKDrawing(strokes: [stroke])

        let annotation = AnnotationConverter.fromDrawing(drawing, imageSize: imageSize, displaySize: displaySize)
        XCTAssertEqual(annotation.version, 2)
        XCTAssertEqual(annotation.lines.count, 1)
        // Display (50,40) at 500x400 → image (100,80) at 1000x800
        XCTAssertEqual(annotation.lines[0].points[0], 100.0, accuracy: 1.0)
        XCTAssertEqual(annotation.lines[0].points[1], 80.0, accuracy: 1.0)
    }
}
