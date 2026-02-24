import UIKit

/// Manages reading and writing step images on the filesystem.
final class ImageStore {
    let imagesDirectory: URL

    init(imagesDirectory: URL) {
        self.imagesDirectory = imagesDirectory
    }

    /// Save a UIImage to disk. Returns the relative path (e.g. "seqId/stepId.jpg").
    func saveImage(_ image: UIImage, sequenceId: String, stepId: String) throws -> String {
        let seqDir = imagesDirectory.appendingPathComponent(sequenceId)
        try FileManager.default.createDirectory(at: seqDir, withIntermediateDirectories: true)

        let filename = "\(stepId).jpg"
        let filePath = seqDir.appendingPathComponent(filename)
        guard let data = image.jpegData(compressionQuality: 0.85) else {
            throw ImageStoreError.encodingFailed
        }
        try data.write(to: filePath)
        return "\(sequenceId)/\(filename)"
    }

    /// Save raw image data (preserving original format). Returns relative path.
    func saveImageData(_ data: Data, sequenceId: String, stepId: String, ext: String) throws -> String {
        let seqDir = imagesDirectory.appendingPathComponent(sequenceId)
        try FileManager.default.createDirectory(at: seqDir, withIntermediateDirectories: true)

        let filename = "\(stepId).\(ext)"
        let filePath = seqDir.appendingPathComponent(filename)
        try data.write(to: filePath)
        return "\(sequenceId)/\(filename)"
    }

    /// Load a full-resolution image from a relative path.
    func loadImage(path: String) -> UIImage? {
        let url = imagesDirectory.appendingPathComponent(path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// Load a downsampled thumbnail.
    func loadThumbnail(path: String, maxSize: CGSize) -> UIImage? {
        let url = imagesDirectory.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: max(maxSize.width, maxSize.height),
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// Get the full filesystem URL for a relative image path.
    func imageURL(path: String) -> URL {
        imagesDirectory.appendingPathComponent(path)
    }

    /// Delete a single image file.
    func deleteImage(path: String) {
        let url = imagesDirectory.appendingPathComponent(path)
        try? FileManager.default.removeItem(at: url)
    }

    /// Delete all images for a sequence.
    func deleteSequenceImages(sequenceId: String) {
        let seqDir = imagesDirectory.appendingPathComponent(sequenceId)
        try? FileManager.default.removeItem(at: seqDir)
    }
}

enum ImageStoreError: Error, LocalizedError {
    case encodingFailed
    var errorDescription: String? {
        switch self {
        case .encodingFailed: return "Failed to encode image"
        }
    }
}
