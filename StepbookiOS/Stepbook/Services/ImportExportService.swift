import Foundation
import ZIPFoundation
import UIKit

// MARK: - Manifest types (matches web version exactly)

struct ExportManifest: Codable {
    var version: Int
    var sequence: ManifestSequence
    var steps: [ManifestStep]
}

struct ManifestSequence: Codable {
    var title: String
    var description: String?
}

struct ManifestStep: Codable {
    var orderIndex: Int
    var imageFilename: String
    var annotations: AnnotationData
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case orderIndex = "order_index"
        case imageFilename = "image_filename"
        case annotations, notes
    }
}

// MARK: - Service

final class ImportExportService {
    private let database: BookDatabase
    private let imageStore: ImageStore

    init(database: BookDatabase, imageStore: ImageStore) {
        self.database = database
        self.imageStore = imageStore
    }

    private static let allowedExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp"]

    // MARK: - Export

    func exportSequence(id: String) throws -> URL {
        let (sequence, steps) = try database.fetchSequenceWithSteps(id: id)

        // Build manifest matching web format:
        // Web uses path.extname() which includes the dot, e.g. ".png"
        // Then formats as `${step.order_index}${ext}` -> "0.png"
        // We reproduce the same output.
        let manifestSteps = steps.map { step -> ManifestStep in
            let ext = URL(fileURLWithPath: step.imagePath).pathExtension.lowercased()
            let safeExt = ext.isEmpty ? "jpg" : ext
            let filename = "\(step.orderIndex).\(safeExt)"
            return ManifestStep(
                orderIndex: step.orderIndex,
                imageFilename: filename,
                annotations: AnnotationData.parse(from: step.annotations),
                notes: step.notes.isEmpty ? nil : step.notes
            )
        }

        let manifest = ExportManifest(
            version: 1,
            sequence: ManifestSequence(
                title: sequence.title,
                description: sequence.description.isEmpty ? nil : sequence.description
            ),
            steps: manifestSteps
        )

        // Create temp ZIP file
        let safeTitle = sequence.title
            .replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
            .prefix(50)
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(safeTitle).stepseq")
        try? FileManager.default.removeItem(at: zipURL)

        let archive = try Archive(url: zipURL, accessMode: .create)

        // Add manifest.json
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        try archive.addEntry(
            with: "manifest.json",
            type: .file,
            uncompressedSize: Int64(manifestData.count)
        ) { (position: Int64, size: Int) -> Data in
            let start = Int(position)
            return manifestData[start..<start+size]
        }

        // Add images under images/ directory
        for step in steps {
            let imageURL = imageStore.imageURL(path: step.imagePath)
            guard FileManager.default.fileExists(atPath: imageURL.path) else { continue }
            let ext = imageURL.pathExtension.lowercased()
            let safeExt = ext.isEmpty ? "jpg" : ext
            let entryName = "images/\(step.orderIndex).\(safeExt)"
            try archive.addEntry(with: entryName, fileURL: imageURL)
        }

        return zipURL
    }

    // MARK: - Import

    func importSequence(from zipURL: URL) throws -> Sequence {
        let archive = try Archive(url: zipURL, accessMode: .read)

        // Read manifest
        guard let manifestEntry = archive["manifest.json"] else {
            throw ImportExportError.missingManifest
        }
        var manifestData = Data()
        _ = try archive.extract(manifestEntry) { data in
            manifestData.append(data)
        }
        let manifest = try JSONDecoder().decode(ExportManifest.self, from: manifestData)

        guard !manifest.sequence.title.isEmpty else {
            throw ImportExportError.invalidManifest("Missing sequence title")
        }

        // Create sequence
        let sequence = try database.createSequence(
            title: manifest.sequence.title,
            description: manifest.sequence.description ?? ""
        )

        // Extract images and create steps
        for manifestStep in manifest.steps {
            let imageFilename = manifestStep.imageFilename
            let ext = URL(fileURLWithPath: imageFilename).pathExtension.lowercased()

            guard Self.allowedExtensions.contains(ext) else {
                throw ImportExportError.invalidManifest("Invalid image type: \(imageFilename)")
            }

            guard let imageEntry = archive["images/\(imageFilename)"] else {
                throw ImportExportError.missingImage(imageFilename)
            }

            var imageData = Data()
            _ = try archive.extract(imageEntry) { data in
                imageData.append(data)
            }

            let stepId = UUID().uuidString
            let imagePath = try imageStore.saveImageData(
                imageData, sequenceId: sequence.id, stepId: stepId, ext: ext
            )

            let step = try database.createStep(sequenceId: sequence.id, imagePath: imagePath)
            let annotationsJSON = manifestStep.annotations.toJSONString()
            _ = try database.updateStep(
                id: step.id,
                annotations: annotationsJSON,
                notes: manifestStep.notes ?? ""
            )
        }

        return sequence
    }

    // MARK: - Helpers

    func readManifest(from zipURL: URL) throws -> ExportManifest {
        let archive = try Archive(url: zipURL, accessMode: .read)
        guard let entry = archive["manifest.json"] else {
            throw ImportExportError.missingManifest
        }
        var data = Data()
        _ = try archive.extract(entry) { chunk in data.append(chunk) }
        return try JSONDecoder().decode(ExportManifest.self, from: data)
    }
}

enum ImportExportError: Error, LocalizedError {
    case archiveCreationFailed
    case invalidZip
    case missingManifest
    case invalidManifest(String)
    case missingImage(String)

    var errorDescription: String? {
        switch self {
        case .archiveCreationFailed: return "Failed to create ZIP archive"
        case .invalidZip: return "Invalid ZIP file"
        case .missingManifest: return "Missing manifest.json in ZIP"
        case .invalidManifest(let msg): return "Invalid manifest: \(msg)"
        case .missingImage(let name): return "Missing image: \(name)"
        }
    }
}
