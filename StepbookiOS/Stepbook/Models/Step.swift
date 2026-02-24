import Foundation
import GRDB

struct Step: Codable, Identifiable, Hashable {
    var id: String
    var sequenceId: String
    var orderIndex: Int
    var imagePath: String
    var annotations: String
    var notes: String
    var createdAt: String
    var updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case sequenceId = "sequence_id"
        case orderIndex = "order_index"
        case imagePath = "image_path"
        case annotations, notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    enum Columns: String, ColumnExpression {
        case id
        case sequenceId = "sequence_id"
        case orderIndex = "order_index"
        case imagePath = "image_path"
        case annotations, notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

extension Step: FetchableRecord, PersistableRecord {
    static let databaseTableName = "steps"
}
