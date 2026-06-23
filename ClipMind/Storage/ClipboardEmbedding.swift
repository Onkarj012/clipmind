import Foundation
import GRDB

struct ClipboardEmbedding: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    static let databaseTableName = "clipboard_embeddings"

    var itemId: String
    var model: String
    var vector: Data
    var createdAt: TimeInterval

    enum Columns: String, ColumnExpression {
        case itemId = "item_id"
        case model
        case vector
        case createdAt = "created_at"
    }

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case model
        case vector
        case createdAt = "created_at"
    }
}
