import Foundation

struct AnnotationLine: Codable, Hashable {
    var points: [Double]
    var stroke: String
    var strokeWidth: Double
    var lineCap: String?
    var lineJoin: String?
    var pointerLength: Double?
    var pointerWidth: Double?
}

struct AnnotationLabel: Codable, Hashable {
    var x: Double
    var y: Double
    var text: String
    var fontSize: Double
    var fill: String
}

struct AnnotationData: Codable, Hashable {
    var version: Int
    var lines: [AnnotationLine]
    var labels: [AnnotationLabel]

    enum CodingKeys: String, CodingKey {
        case version = "_v"
        case lines
        case labels
    }

    init(version: Int = 2, lines: [AnnotationLine] = [], labels: [AnnotationLabel] = []) {
        self.version = version
        self.lines = lines
        self.labels = labels
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 2
        self.lines = try container.decodeIfPresent([AnnotationLine].self, forKey: .lines) ?? []
        self.labels = try container.decodeIfPresent([AnnotationLabel].self, forKey: .labels) ?? []
    }

    /// Parse from the JSON string stored in the Step.annotations field
    static func parse(from jsonString: String) -> AnnotationData {
        guard let data = jsonString.data(using: .utf8),
              let annotation = try? JSONDecoder().decode(AnnotationData.self, from: data) else {
            return AnnotationData()
        }
        return annotation
    }

    /// Serialize to JSON string for storage in Step.annotations
    func toJSONString() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
