import AppKit
import Foundation

struct PasteboardExtractedFile: Sendable {
    let fileURL: URL
    let displayName: String

    var path: String { fileURL.path }
}

enum PasteboardFileExtractor {
    static func extract(from pasteboard: NSPasteboard) -> PasteboardExtractedFile? {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL],
            let url = urls.first
        {
            return makeExtractedFile(from: url)
        }

        if let filenames = pasteboard.propertyList(
            forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")
        ) as? [String],
           let path = filenames.first
        {
            return makeExtractedFile(from: URL(fileURLWithPath: path))
        }

        return nil
    }

    private static func makeExtractedFile(from url: URL) -> PasteboardExtractedFile? {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        let displayName = url.lastPathComponent
        guard !displayName.isEmpty else {
            return nil
        }

        return PasteboardExtractedFile(fileURL: url, displayName: displayName)
    }
}
