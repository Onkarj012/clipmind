import Foundation
import GRDB

struct ClipboardItemMetadata: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    static let databaseTableName = "clipboard_metadata"

    var clipboardItemId: String
    var key: String
    var value: String

    enum Columns: String, ColumnExpression {
        case clipboardItemId = "clipboard_item_id"
        case key
        case value
    }

    enum CodingKeys: String, CodingKey {
        case clipboardItemId = "clipboard_item_id"
        case key
        case value
    }
}
