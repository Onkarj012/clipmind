import Foundation
import GRDB

struct Tag: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "tags"

    var id: String
    var name: String

    enum Columns: String, ColumnExpression {
        case id, name
    }
}

struct ClipboardTag: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    static let databaseTableName = "clipboard_tags"

    var clipboardItemId: String
    var tagId: String

    enum Columns: String, ColumnExpression {
        case clipboardItemId = "clipboard_item_id"
        case tagId = "tag_id"
    }

    enum CodingKeys: String, CodingKey {
        case clipboardItemId = "clipboard_item_id"
        case tagId = "tag_id"
    }
}
