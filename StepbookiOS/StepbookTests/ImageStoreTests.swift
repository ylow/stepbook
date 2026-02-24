import XCTest
import UIKit
@testable import Stepbook

final class ImageStoreTests: XCTestCase {

    var store: ImageStore!
    var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        store = ImageStore(imagesDirectory: tempDir)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testSaveAndLoadImage() throws {
        let image = createTestImage()
        let path = try store.saveImage(image, sequenceId: "seq1", stepId: "step1")
        XCTAssertTrue(path.hasPrefix("seq1/step1"))
        XCTAssertTrue(path.hasSuffix(".jpg"))

        let loaded = store.loadImage(path: path)
        XCTAssertNotNil(loaded)
    }

    func testDeleteImage() throws {
        let image = createTestImage()
        let path = try store.saveImage(image, sequenceId: "seq1", stepId: "step1")
        store.deleteImage(path: path)

        let loaded = store.loadImage(path: path)
        XCTAssertNil(loaded)
    }

    func testDeleteSequenceDirectory() throws {
        let image = createTestImage()
        _ = try store.saveImage(image, sequenceId: "seq1", stepId: "step1")
        _ = try store.saveImage(image, sequenceId: "seq1", stepId: "step2")
        store.deleteSequenceImages(sequenceId: "seq1")

        let seqDir = tempDir.appendingPathComponent("seq1")
        XCTAssertFalse(FileManager.default.fileExists(atPath: seqDir.path))
    }

    func testThumbnailGeneration() throws {
        let image = createTestImage(size: CGSize(width: 400, height: 300))
        let path = try store.saveImage(image, sequenceId: "seq1", stepId: "step1")
        let thumbnail = store.loadThumbnail(path: path, maxSize: CGSize(width: 100, height: 100))
        XCTAssertNotNil(thumbnail)
        XCTAssertLessThanOrEqual(thumbnail!.size.width, 100)
        XCTAssertLessThanOrEqual(thumbnail!.size.height, 100)
    }

    func testSaveImageData() throws {
        let image = createTestImage()
        let pngData = image.pngData()!
        let path = try store.saveImageData(pngData, sequenceId: "seq1", stepId: "step1", ext: "png")
        XCTAssertTrue(path.hasSuffix(".png"))
        let loaded = store.loadImage(path: path)
        XCTAssertNotNil(loaded)
    }

    func testImageURL() throws {
        let url = store.imageURL(path: "seq1/step1.jpg")
        XCTAssertTrue(url.path.contains("seq1/step1.jpg"))
    }

    private func createTestImage(size: CGSize = CGSize(width: 100, height: 100)) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
