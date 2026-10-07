import AppKit

struct PasteboardExtractedText: Sendable {
    let plainText: String
    let metadata: [String: String]
}

enum PasteboardTextExtractor {
    static func extract(from pasteboard: NSPasteboard) -> PasteboardExtractedText? {
        var plainText = pasteboard.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if let rtfData = pasteboard.data(forType: .rtf) {
            if plainText.isEmpty,
               let attributed = try? NSAttributedString(
                   data: rtfData,
                   options: [.documentType: NSAttributedString.DocumentType.rtf],
                   documentAttributes: nil
               )
            {
                plainText = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let htmlData = pasteboard.data(forType: .html) {
            if plainText.isEmpty,
               let attributed = try? NSAttributedString(
                   data: htmlData,
                   options: [.documentType: NSAttributedString.DocumentType.html],
                   documentAttributes: nil
               )
            {
                plainText = attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        guard !plainText.isEmpty else {
            return nil
        }

        return PasteboardExtractedText(plainText: plainText, metadata: [:])
    }
}
