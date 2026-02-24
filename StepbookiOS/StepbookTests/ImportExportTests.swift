import XCTest
import UIKit
@testable import Stepbook

final class ImportExportTests: XCTestCase {

    var bookDb: BookDatabase!
    var imageStore: ImageStore!
    var service: ImportExportService!
    var tempDir: URL!

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        bookDb = try BookDatabase(directory: tempDir)
        imageStore = ImageStore(imagesDirectory: tempDir.appendingPathComponent("images"))
        service = ImportExportService(database: bookDb, imageStore: imageStore)
    }

    override func tearDown() async throws {
        bookDb = nil
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testExportAndImportRoundTrip() throws {
        // Create a sequence with a step
        let seq = try bookDb.createSequence(title: "Export Test", description: "Testing export")
        let image = createTestImage()
        let imagePath = try imageStore.saveImage(image, sequenceId: seq.id, stepId: "step1")
        _ = try bookDb.createStep(sequenceId: seq.id, imagePath: imagePath)

        // Export
        let zipURL = try service.exportSequence(id: seq.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path))

        // Import into same DB (should create new sequence with new IDs)
        let imported = try service.importSequence(from: zipURL)
        XCTAssertNotEqual(imported.id, seq.id)
        XCTAssertEqual(imported.title, "Export Test")

        let (_, steps) = try bookDb.fetchSequenceWithSteps(id: imported.id)
        XCTAssertEqual(steps.count, 1)
        XCTAssertNotEqual(steps[0].imagePath, imagePath)
    }

    func testExportManifestFormat() throws {
        let seq = try bookDb.createSequence(title: "Manifest Test", description: "desc")
        let image = createTestImage()
        let path = try imageStore.saveImage(image, sequenceId: seq.id, stepId: "s1")
        _ = try bookDb.createStep(sequenceId: seq.id, imagePath: path)
        let steps = try bookDb.fetchSteps(sequenceId: seq.id)
        _ = try bookDb.updateStep(id: steps[0].id,
                                   annotations: "{\"_v\":2,\"lines\":[],\"labels\":[]}",
                                   notes: "Step notes")

        let zipURL = try service.exportSequence(id: seq.id)

        let manifest = try service.readManifest(from: zipURL)
        XCTAssertEqual(manifest.version, 1)
        XCTAssertEqual(manifest.sequence.title, "Manifest Test")
        XCTAssertEqual(manifest.steps.count, 1)
        XCTAssertEqual(manifest.steps[0].notes, "Step notes")
        XCTAssertEqual(manifest.steps[0].orderIndex, 0)
    }

    func testExportContainsImages() throws {
        let seq = try bookDb.createSequence(title: "Image Test", description: "")
        let image = createTestImage()
        let path = try imageStore.saveImage(image, sequenceId: seq.id, stepId: "s1")
        _ = try bookDb.createStep(sequenceId: seq.id, imagePath: path)

        let zipURL = try service.exportSequence(id: seq.id)

        // Verify the zip contains the expected image entry
        let manifest = try service.readManifest(from: zipURL)
        XCTAssertEqual(manifest.steps[0].imageFilename, "0.jpg")
    }

    func testImportPreservesAnnotations() throws {
        // Create a sequence with annotations
        let seq = try bookDb.createSequence(title: "Annotation Test", description: "")
        let image = createTestImage()
        let path = try imageStore.saveImage(image, sequenceId: seq.id, stepId: "s1")
        _ = try bookDb.createStep(sequenceId: seq.id, imagePath: path)
        let steps = try bookDb.fetchSteps(sequenceId: seq.id)
        let annotations = "{\"_v\":2,\"lines\":[{\"points\":[10,20,30,40],\"stroke\":\"#ff0000\",\"strokeWidth\":3}],\"labels\":[]}"
        _ = try bookDb.updateStep(id: steps[0].id, annotations: annotations, notes: "Test note")

        // Export and re-import
        let zipURL = try service.exportSequence(id: seq.id)
        let imported = try service.importSequence(from: zipURL)
        let (_, importedSteps) = try bookDb.fetchSequenceWithSteps(id: imported.id)

        XCTAssertEqual(importedSteps.count, 1)
        XCTAssertEqual(importedSteps[0].notes, "Test note")
        // Verify annotation data round-trips (parsed and re-serialized)
        let parsedAnnotations = AnnotationData.parse(from: importedSteps[0].annotations)
        XCTAssertEqual(parsedAnnotations.version, 2)
        XCTAssertEqual(parsedAnnotations.lines.count, 1)
        XCTAssertEqual(parsedAnnotations.lines[0].stroke, "#ff0000")
    }

    func testImportMultipleSteps() throws {
        // Create a sequence with multiple steps
        let seq = try bookDb.createSequence(title: "Multi Step", description: "")
        let image = createTestImage()
        for i in 0..<3 {
            let path = try imageStore.saveImage(image, sequenceId: seq.id, stepId: "s\(i)")
            _ = try bookDb.createStep(sequenceId: seq.id, imagePath: path)
        }

        let zipURL = try service.exportSequence(id: seq.id)
        let imported = try service.importSequence(from: zipURL)
        let (_, importedSteps) = try bookDb.fetchSequenceWithSteps(id: imported.id)

        XCTAssertEqual(importedSteps.count, 3)
    }

    private func createTestImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100)).image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        }
    }
}
