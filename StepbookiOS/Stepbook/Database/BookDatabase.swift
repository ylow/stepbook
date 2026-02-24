import Foundation
import GRDB

/// Manages a single book's SQLite database and image directory.
/// Each book has its own stepbook.db and images/ folder.
final class BookDatabase {
    let dbPool: DatabasePool
    let directory: URL
    var imagesDirectory: URL { directory.appendingPathComponent("images") }

    init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("images"),
            withIntermediateDirectories: true
        )

        let dbPath = directory.appendingPathComponent("stepbook.db").path
        dbPool = try DatabasePool(path: dbPath)

        try migrator.migrate(dbPool)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS sequences (
                    id TEXT PRIMARY KEY,
                    title TEXT NOT NULL,
                    description TEXT DEFAULT '',
                    created_at TEXT DEFAULT (datetime('now')),
                    updated_at TEXT DEFAULT (datetime('now'))
                )
                """)
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS steps (
                    id TEXT PRIMARY KEY,
                    sequence_id TEXT NOT NULL,
                    order_index INTEGER NOT NULL,
                    image_path TEXT NOT NULL,
                    annotations TEXT DEFAULT '{}',
                    notes TEXT DEFAULT '',
                    created_at TEXT DEFAULT (datetime('now')),
                    updated_at TEXT DEFAULT (datetime('now')),
                    FOREIGN KEY (sequence_id) REFERENCES sequences(id) ON DELETE CASCADE
                )
                """)
        }
        return migrator
    }

    // MARK: - Sequences

    func createSequence(title: String, description: String) throws -> Sequence {
        try dbPool.write { db in
            let id = UUID().uuidString
            let now = Self.isoNow()
            let seq = Sequence(
                id: id, title: title, description: description,
                createdAt: now, updatedAt: now
            )
            try seq.insert(db)
            return seq
        }
    }

    func listSequences() throws -> [Sequence] {
        try dbPool.read { db in
            let sql = """
                SELECT s.*,
                       COUNT(st.id) as step_count,
                       (SELECT st2.image_path FROM steps st2
                        WHERE st2.sequence_id = s.id
                        ORDER BY st2.order_index LIMIT 1) as thumbnail_path
                FROM sequences s
                LEFT JOIN steps st ON st.sequence_id = s.id
                GROUP BY s.id
                ORDER BY s.updated_at DESC
                """
            return try Sequence.fetchAll(db, sql: sql)
        }
    }

    func fetchSequenceWithSteps(id: String) throws -> (Sequence, [Step]) {
        try dbPool.read { db in
            guard let seq = try Sequence.fetchOne(db, key: id) else {
                throw StepbookError(message: "Sequence not found")
            }
            let steps = try Step
                .filter(Step.Columns.sequenceId == id)
                .order(Step.Columns.orderIndex)
                .fetchAll(db)
            return (seq, steps)
        }
    }

    func updateSequence(id: String, title: String?, description: String?) throws -> Sequence {
        try dbPool.write { db in
            guard var seq = try Sequence.fetchOne(db, key: id) else {
                throw StepbookError(message: "Sequence not found")
            }
            if let title { seq.title = title }
            if let description { seq.description = description }
            seq.updatedAt = Self.isoNow()
            try seq.update(db)
            return seq
        }
    }

    func deleteSequence(id: String) throws {
        _ = try dbPool.write { db in
            try Sequence.deleteOne(db, key: id)
        }
    }

    // MARK: - Steps

    func createStep(sequenceId: String, imagePath: String) throws -> Step {
        try dbPool.write { db in
            let maxOrder = try Int.fetchOne(db, sql: """
                SELECT COALESCE(MAX(order_index), -1) FROM steps WHERE sequence_id = ?
                """, arguments: [sequenceId]) ?? -1
            let now = Self.isoNow()
            let step = Step(
                id: UUID().uuidString,
                sequenceId: sequenceId,
                orderIndex: maxOrder + 1,
                imagePath: imagePath,
                annotations: "{}",
                notes: "",
                createdAt: now,
                updatedAt: now
            )
            try step.insert(db)
            // Update sequence timestamp
            try db.execute(
                sql: "UPDATE sequences SET updated_at = ? WHERE id = ?",
                arguments: [now, sequenceId]
            )
            return step
        }
    }

    func updateStep(id: String, annotations: String?, notes: String?) throws -> Step {
        try dbPool.write { db in
            guard var step = try Step.fetchOne(db, key: id) else {
                throw StepbookError(message: "Step not found")
            }
            if let annotations { step.annotations = annotations }
            if let notes { step.notes = notes }
            let now = Self.isoNow()
            step.updatedAt = now
            try step.update(db)
            // Update parent sequence timestamp
            try db.execute(
                sql: "UPDATE sequences SET updated_at = ? WHERE id = ?",
                arguments: [now, step.sequenceId]
            )
            return step
        }
    }

    func deleteStep(id: String) throws {
        try dbPool.write { db in
            guard let step = try Step.fetchOne(db, key: id) else { return }
            let sequenceId = step.sequenceId
            try Step.deleteOne(db, key: id)
            // Re-index remaining steps
            let remaining = try Step
                .filter(Step.Columns.sequenceId == sequenceId)
                .order(Step.Columns.orderIndex)
                .fetchAll(db)
            for (index, var s) in remaining.enumerated() {
                s.orderIndex = index
                try s.update(db)
            }
        }
    }

    func fetchSteps(sequenceId: String) throws -> [Step] {
        try dbPool.read { db in
            try Step
                .filter(Step.Columns.sequenceId == sequenceId)
                .order(Step.Columns.orderIndex)
                .fetchAll(db)
        }
    }

    func reorderSteps(sequenceId: String, stepIds: [String]) throws -> [Step] {
        try dbPool.write { db in
            for (index, stepId) in stepIds.enumerated() {
                try db.execute(
                    sql: "UPDATE steps SET order_index = ? WHERE id = ? AND sequence_id = ?",
                    arguments: [index, stepId, sequenceId]
                )
            }
            return try Step
                .filter(Step.Columns.sequenceId == sequenceId)
                .order(Step.Columns.orderIndex)
                .fetchAll(db)
        }
    }

    // MARK: - Helpers

    private static func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
    }
}

struct StepbookError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
