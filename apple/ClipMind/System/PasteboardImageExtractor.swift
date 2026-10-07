import AppKit

enum ImagePasteboardFormat: String, Sendable {
    case png
    case tiff

    var assetFormat: AssetStore.ImageFormat {
        switch self {
        case .png: return .png
        case .tiff: return .tiff
        }
    }
}

struct PasteboardExtractedImage: Sendable {
    let data: Data
    let format: ImagePasteboardFormat
}

enum PasteboardImageExtractor {
    static func extract(from pasteboard: NSPasteboard) -> PasteboardExtractedImage? {
        if let data = pasteboard.data(forType: .png), !data.isEmpty {
            return PasteboardExtractedImage(data: data, format: .png)
        }

        if let data = pasteboard.data(forType: .tiff), !data.isEmpty {
            return PasteboardExtractedImage(data: data, format: .tiff)
        }

        return nil
    }
}
