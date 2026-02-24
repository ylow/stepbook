import Foundation
import GRDB

struct Book: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var path: String
}

extension Book: FetchableRecord, PersistableRecord {
    static let databaseTableName = "books"
}
