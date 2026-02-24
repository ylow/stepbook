import XCTest
import GRDB
@testable import Stepbook

final class DatabaseTests: XCTestCase {

    var bookDb: BookDatabase!
    var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        bookDb = try BookDatabase(directory: tempDir)
    }

    override func tearDown() async throws {
        bookDb = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    // MARK: - Sequences

    func testCreateSequence() throws {
        let seq = try bookDb.createSequence(title: "Test Guide", description: "A test")
        XCTAssertFalse(seq.id.isEmpty)
        XCTAssertEqual(seq.title, "Test Guide")
        XCTAssertEqual(seq.description, "A test")
    }

    func testListSequences() throws {
        _ = try bookDb.createSequence(title: "First", description: "")
        _ = try bookDb.createSequence(title: "Second", description: "")
        let sequences = try bookDb.listSequences()
        XCTAssertEqual(sequences.count, 2)
    }

    func testDeleteSequenceCascadesSteps() throws {
        let seq = try bookDb.createSequence(title: "Test", description: "")
        _ = try bookDb.createStep(sequenceId: seq.id, imagePath: "test/img.jpg")
        try bookDb.deleteSequence(id: seq.id)
        let sequences = try bookDb.listSequences()
        XCTAssertEqual(sequences.count, 0)
    }

    // MARK: - Steps

    func testCreateStep() throws {
        let seq = try bookDb.createSequence(title: "Test", description: "")
        let step = try bookDb.createStep(sequenceId: seq.id, imagePath: "seq/step.jpg")
        XCTAssertEqual(step.sequenceId, seq.id)
        XCTAssertEqual(step.orderIndex, 0)
        XCTAssertEqual(step.imagePath, "seq/step.jpg")
        XCTAssertEqual(step.annotations, "{}")
        XCTAssertEqual(step.notes, "")
    }

    func testCreateMultipleStepsAutoIncrementOrder() throws {
        let seq = try bookDb.createSequence(title: "Test", description: "")
        let step1 = try bookDb.createStep(sequenceId: seq.id, imagePath: "s/1.jpg")
        let step2 = try bookDb.createStep(sequenceId: seq.id, imagePath: "s/2.jpg")
        let step3 = try bookDb.createStep(sequenceId: seq.id, imagePath: "s/3.jpg")
        XCTAssertEqual(step1.orderIndex, 0)
        XCTAssertEqual(step2.orderIndex, 1)
        XCTAssertEqual(step3.orderIndex, 2)
    }

    func testUpdateStepAnnotations() throws {
        let seq = try bookDb.createSequence(title: "Test", description: "")
        let step = try bookDb.createStep(sequenceId: seq.id, imagePath: "s/1.jpg")
        let annotations = "{\"_v\":2,\"lines\":[],\"labels\":[]}"
        let updated = try bookDb.updateStep(id: step.id, annotations: annotations, notes: "Hello")
        XCTAssertEqual(updated.annotations, annotations)
        XCTAssertEqual(updated.notes, "Hello")
    }

    func testReorderSteps() throws {
        let seq = try bookDb.createSequence(title: "Test", description: "")
        let s1 = try bookDb.createStep(sequenceId: seq.id, imagePath: "s/1.jpg")
        let s2 = try bookDb.createStep(sequenceId: seq.id, imagePath: "s/2.jpg")
        let s3 = try bookDb.createStep(sequenceId: seq.id, imagePath: "s/3.jpg")

        let steps = try bookDb.reorderSteps(sequenceId: seq.id, stepIds: [s3.id, s2.id, s1.id])
        XCTAssertEqual(steps[0].id, s3.id)
        XCTAssertEqual(steps[0].orderIndex, 0)
        XCTAssertEqual(steps[1].id, s2.id)
        XCTAssertEqual(steps[1].orderIndex, 1)
        XCTAssertEqual(steps[2].id, s1.id)
        XCTAssertEqual(steps[2].orderIndex, 2)
    }

    func testDeleteStepReindexes() throws {
        let seq = try bookDb.createSequence(title: "Test", description: "")
        _ = try bookDb.createStep(sequenceId: seq.id, imagePath: "s/1.jpg")
        let s2 = try bookDb.createStep(sequenceId: seq.id, imagePath: "s/2.jpg")
        let s3 = try bookDb.createStep(sequenceId: seq.id, imagePath: "s/3.jpg")

        try bookDb.deleteStep(id: s2.id)
        let remaining = try bookDb.fetchSteps(sequenceId: seq.id)
        XCTAssertEqual(remaining.count, 2)
        XCTAssertEqual(remaining[0].orderIndex, 0)
        XCTAssertEqual(remaining[1].id, s3.id)
        XCTAssertEqual(remaining[1].orderIndex, 1)
    }

    func testFetchSequenceWithSteps() throws {
        let seq = try bookDb.createSequence(title: "Test", description: "")
        _ = try bookDb.createStep(sequenceId: seq.id, imagePath: "s/1.jpg")
        _ = try bookDb.createStep(sequenceId: seq.id, imagePath: "s/2.jpg")
        let (fetched, steps) = try bookDb.fetchSequenceWithSteps(id: seq.id)
        XCTAssertEqual(fetched.id, seq.id)
        XCTAssertEqual(steps.count, 2)
    }
}
