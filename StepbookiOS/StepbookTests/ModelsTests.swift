import XCTest
@testable import Stepbook

final class ModelsTests: XCTestCase {

    func testBookRoundTrip() throws {
        let book = Book(id: "abc-123", name: "My Book", path: "abc-123")
        let data = try JSONEncoder().encode(book)
        let decoded = try JSONDecoder().decode(Book.self, from: data)
        XCTAssertEqual(decoded.id, "abc-123")
        XCTAssertEqual(decoded.name, "My Book")
        XCTAssertEqual(decoded.path, "abc-123")
    }

    func testSequenceRoundTrip() throws {
        let seq = Sequence(
            id: "seq-1",
            title: "My Guide",
            description: "A guide",
            createdAt: "2026-02-23T00:00:00",
            updatedAt: "2026-02-23T00:00:00"
        )
        let data = try JSONEncoder().encode(seq)
        let decoded = try JSONDecoder().decode(Sequence.self, from: data)
        XCTAssertEqual(decoded.title, "My Guide")
    }

    func testStepRoundTrip() throws {
        let step = Step(
            id: "step-1",
            sequenceId: "seq-1",
            orderIndex: 0,
            imagePath: "seq-1/step-1.jpg",
            annotations: "{}",
            notes: "First step",
            createdAt: "2026-02-23T00:00:00",
            updatedAt: "2026-02-23T00:00:00"
        )
        let data = try JSONEncoder().encode(step)
        let decoded = try JSONDecoder().decode(Step.self, from: data)
        XCTAssertEqual(decoded.imagePath, "seq-1/step-1.jpg")
        XCTAssertEqual(decoded.notes, "First step")
    }

    func testAnnotationDataParsesWebFormat() throws {
        let json = """
        {
            "_v": 2,
            "lines": [
                {
                    "points": [10.0, 20.0, 30.0, 40.0],
                    "stroke": "#ff0000",
                    "strokeWidth": 4,
                    "lineCap": "round",
                    "lineJoin": "round"
                }
            ],
            "labels": [
                {
                    "x": 100,
                    "y": 50,
                    "text": "Hello",
                    "fontSize": 16,
                    "fill": "#00ff00"
                }
            ]
        }
        """
        let data = try JSONDecoder().decode(AnnotationData.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(data.version, 2)
        XCTAssertEqual(data.lines.count, 1)
        XCTAssertEqual(data.lines[0].points, [10.0, 20.0, 30.0, 40.0])
        XCTAssertEqual(data.lines[0].stroke, "#ff0000")
        XCTAssertEqual(data.lines[0].strokeWidth, 4)
        XCTAssertEqual(data.labels.count, 1)
        XCTAssertEqual(data.labels[0].text, "Hello")
    }

    func testAnnotationDataEncodesToWebFormat() throws {
        let annotation = AnnotationData(
            version: 2,
            lines: [
                AnnotationLine(
                    points: [1.0, 2.0, 3.0, 4.0],
                    stroke: "#0000ff",
                    strokeWidth: 2,
                    lineCap: "round",
                    lineJoin: "round",
                    pointerLength: nil,
                    pointerWidth: nil
                )
            ],
            labels: []
        )
        let data = try JSONEncoder().encode(annotation)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["_v"] as? Int, 2)
        let lines = json["lines"] as! [[String: Any]]
        XCTAssertEqual(lines.count, 1)
    }

    func testAnnotationDataEmptyParsesCorrectly() throws {
        let json = "{}"
        let data = try JSONDecoder().decode(AnnotationData.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(data.version, 2)
        XCTAssertTrue(data.lines.isEmpty)
        XCTAssertTrue(data.labels.isEmpty)
    }

    func testAnnotationLineWithArrowProperties() throws {
        let json = """
        {
            "_v": 2,
            "lines": [
                {
                    "points": [0, 0, 100, 100],
                    "stroke": "#ff0000",
                    "strokeWidth": 4,
                    "lineCap": "round",
                    "lineJoin": "round",
                    "pointerLength": 10,
                    "pointerWidth": 10
                }
            ],
            "labels": []
        }
        """
        let data = try JSONDecoder().decode(AnnotationData.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(data.lines[0].pointerLength, 10)
        XCTAssertEqual(data.lines[0].pointerWidth, 10)
    }
}
