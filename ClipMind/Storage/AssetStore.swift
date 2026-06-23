import AppKit
import Foundation

enum AssetStoreError: Error, Equatable {
    case invalidImageData
    case invalidItemID
    case failedToWriteThumbnail
}

enum AssetStore {
    enum ImageFormat: String, Sendable {
        case png
        case tiff

        var fileExtension: String { rawValue }

        var mimeType: String {
            switch self {
            case .png: return "image/png"
            case .tiff: return "image/tiff"
            }
        }

        init?(mimeType: String) {
            switch mimeType.lowercased() {
            case "image/png": self = .png
            case "image/tiff": self = .tiff
            default: return nil
            }
        }
    }

    struct SavedImageAsset: Equatable, Sendable {
        let filePath: String
        let thumbnailPath: String
        let width: Int
        let height: Int
        let mimeType: String
    }

    private static let maxThumbnailDimension: CGFloat = 200

    static func saveImage(
        data: Data,
        format: ImageFormat,
        itemID: String,
        baseURL: URL? = nil
    ) throws -> SavedImageAsset {
        guard let image = NSImage(data: data) else {
            throw AssetStoreError.invalidImageData
        }
        guard UUID(uuidString: itemID) != nil else {
            throw AssetStoreError.invalidItemID
        }

        let pixelSize = pixelDimensions(of: image)
        let rootURL = try baseURL ?? DatabaseManager.applicationSupportURL()
        let imagesURL = rootURL.appendingPathComponent("images", isDirectory: true)
        let thumbnailsURL = rootURL.appendingPathComponent("thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)

        let originalURL = imagesURL.appendingPathComponent("\(itemID).\(format.fileExtension)")
        try data.write(to: originalURL, options: .atomic)

        let thumbnailURL = thumbnailsURL.appendingPathComponent("\(itemID).jpg")
        try writeThumbnail(for: image, pixelSize: pixelSize, to: thumbnailURL)

        return SavedImageAsset(
            filePath: originalURL.path,
            thumbnailPath: thumbnailURL.path,
            width: pixelSize.width,
            height: pixelSize.height,
            mimeType: format.mimeType
        )
    }

    private static func pixelDimensions(of image: NSImage) -> (width: Int, height: Int) {
        if let rep = image.representations.first as? NSBitmapImageRep {
            return (rep.pixelsWide, rep.pixelsHigh)
        }
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return (cgImage.width, cgImage.height)
        }
        return (Int(image.size.width.rounded()), Int(image.size.height.rounded()))
    }

    private static func writeThumbnail(
        for image: NSImage,
        pixelSize: (width: Int, height: Int),
        to url: URL
    ) throws {
        guard let sourceCG = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AssetStoreError.failedToWriteThumbnail
        }

        let maxSide = max(pixelSize.width, pixelSize.height)
        let scale = maxSide > 0
            ? min(maxThumbnailDimension / CGFloat(maxSide), 1)
            : 1
        let thumbWidth = max(1, Int((CGFloat(pixelSize.width) * scale).rounded()))
        let thumbHeight = max(1, Int((CGFloat(pixelSize.height) * scale).rounded()))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: thumbWidth,
            height: thumbHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AssetStoreError.failedToWriteThumbnail
        }

        context.interpolationQuality = .high
        context.draw(sourceCG, in: CGRect(x: 0, y: 0, width: thumbWidth, height: thumbHeight))

        guard let thumbCG = context.makeImage() else {
            throw AssetStoreError.failedToWriteThumbnail
        }

        let rep = NSBitmapImageRep(cgImage: thumbCG)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else {
            throw AssetStoreError.failedToWriteThumbnail
        }

        try jpeg.write(to: url, options: .atomic)
    }
}
