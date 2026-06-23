import Foundation
import GRDB

struct ClipboardAsset: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    static let databaseTableName = "clipboard_assets"

    var itemId: String
    var filePath: String
    var thumbnailPath: String?
    var mimeType: String
    var width: Int
    var height: Int
    var ocrText: String?

    enum Columns: String, ColumnExpression {
        case itemId = "item_id"
        case filePath = "file_path"
        case thumbnailPath = "thumbnail_path"
        case mimeType = "mime_type"
        case width, height
        case ocrText = "ocr_text"
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case filePath = "file_path"
        case thumbnailPath = "thumbnail_path"
        case mimeType = "mime_type"
        case width, height
        case ocrText = "ocr_text"
    }
}
