import Foundation
import GRDB

struct Sequence: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var description: String
    var createdAt: String
    var updatedAt: String

    // Transient properties (not in DB columns)
    var stepCount: Int?
    var thumbnailPath: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case stepCount = "step_count"
        case thumbnailPath = "thumbnail_path"
    }

    enum Columns: String, ColumnExpression {
        case id, title, description
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension Sequence: FetchableRecord, PersistableRecord {
    static let databaseTableName = "sequences"

    // Only persist actual DB columns
    func encode(to container: inout PersistenceContainer) {
        container["id"] = id
        container["title"] = title
        container["description"] = description
        container["created_at"] = createdAt
        container["updated_at"] = updatedAt
    }
}
