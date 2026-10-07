import Foundation
import GRDB

struct ClipboardItem: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "clipboard_items"

    var id: String
    var type: String
    var contentText: String?
    var contentHash: String
    var sourceApp: String?
    var sourceBundleId: String?
    var preview: String?
    var title: String?
    var summary: String?
    var isFavorite: Bool
    var isSensitive: Bool
    var isDeleted: Bool
    var copyCount: Int
    var createdAt: TimeInterval
    var lastUsedAt: TimeInterval?

    enum Columns: String, ColumnExpression {
        case id, type, contentText = "content_text", contentHash = "content_hash"
        case sourceApp = "source_app", sourceBundleId = "source_bundle_id"
        case preview, title, summary
        case isFavorite = "is_favorite", isSensitive = "is_sensitive", isDeleted = "is_deleted"
        case copyCount = "copy_count", createdAt = "created_at", lastUsedAt = "last_used_at"
    }

    enum CodingKeys: String, CodingKey {
        case id, type, preview, title, summary
        case contentText = "content_text"
        case contentHash = "content_hash"
        case sourceApp = "source_app"
        case sourceBundleId = "source_bundle_id"
        case isFavorite = "is_favorite"
        case isSensitive = "is_sensitive"
        case isDeleted = "is_deleted"
        case copyCount = "copy_count"
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
    }

    var filePath: String? {
        guard type == "file", let text = contentText else { return nil }
        if let range = text.range(of: " — ") {
            return String(text[range.upperBound...])
        }
        return text
    }

    var fileDisplayName: String? {
        guard type == "file" else { return nil }
        if let title, !title.isEmpty { return title }
        if let preview, !preview.isEmpty { return preview }
        return filePath.map { URL(fileURLWithPath: $0).lastPathComponent }
    }
}
