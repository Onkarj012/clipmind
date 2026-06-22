import CryptoKit
import Foundation
import GRDB

struct ClipboardInsertInput: Sendable {
    let text: String
    let sourceApp: String?
    let sourceBundleId: String?
    let metadata: [String: String]

    init(
        text: String,
        sourceApp: String?,
        sourceBundleId: String?,
        metadata: [String: String] = [:]
    ) {
        self.text = text
        self.sourceApp = sourceApp
        self.sourceBundleId = sourceBundleId
        self.metadata = metadata
    }
}

struct ClipboardFileInsertInput: Sendable {
    let path: String
    let displayName: String
    let sourceApp: String?
    let sourceBundleId: String?
}

struct ClipboardImageInsertInput: Sendable {
    let imageData: Data
    let format: ImagePasteboardFormat
    let sourceApp: String?
    let sourceBundleId: String?
}

struct ParsedSearchQuery: Equatable, Sendable {
    var keywords: String = ""
    var typeFilter: String?
    var fromFilter: String?
    var tagFilter: String?
    var favoritesOnly: Bool?
    var includeSensitive: Bool = false

    var wordCount: Int {
        keywords
            .split(whereSeparator: \.isWhitespace)
            .filter { !$0.isEmpty }
            .count
    }

    var qualifiesForSemanticSearch: Bool {
        typeFilter == nil && fromFilter == nil && tagFilter == nil && wordCount > 3
    }
}

enum ClipboardRepositoryError: Error, Equatable {
    case emptyContent
    case notFound
}

final class ClipboardRepository: @unchecked Sendable {
    private static let assetsTableName = "clipboard_assets"

    private let dbWriter: any DatabaseWriter
    private let assetBaseURL: URL?

    init(dbWriter: any DatabaseWriter, assetBaseURL: URL? = nil) {
        self.dbWriter = dbWriter
        self.assetBaseURL = assetBaseURL
    }

    @discardableResult
    func insertFile(
        _ input: ClipboardFileInsertInput,
        retention settings: RetentionSettings? = nil
    ) throws -> ClipboardItem {
        let path = input.path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            throw ClipboardRepositoryError.emptyContent
        }

        let displayName = input.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayName.isEmpty else {
            throw ClipboardRepositoryError.emptyContent
        }

        let searchableText = "\(displayName) — \(path)"
        let hash = Self.contentHash(for: path)
        let now = Date().timeIntervalSince1970

        return try dbWriter.write { db in
            if var existing = try ClipboardItem
                .filter(ClipboardItem.Columns.contentHash == hash)
                .fetchOne(db)
            {
                existing.copyCount += 1
                existing.lastUsedAt = now
                try existing.update(db)
                return existing
            }

            let item = ClipboardItem(
                id: UUID().uuidString,
                type: "file",
                contentText: searchableText,
                contentHash: hash,
                sourceApp: input.sourceApp,
                sourceBundleId: input.sourceBundleId,
                preview: displayName,
                title: displayName,
                summary: nil,
                isFavorite: false,
                isSensitive: false,
                isDeleted: false,
                copyCount: 1,
                createdAt: now,
                lastUsedAt: now
            )
            try item.insert(db)
            try Self.insertMetadata(["file_path": path], for: item.id, in: db)
            if let settings {
                try Self.enforceRetention(settings: settings, in: db)
            }
            return item
        }
    }

    @discardableResult
    func insertText(
        _ input: ClipboardInsertInput,
        retention settings: RetentionSettings? = nil
    ) throws -> ClipboardItem {
        let trimmed = input.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ClipboardRepositoryError.emptyContent
        }

        let hash = Self.contentHash(for: trimmed)
        let now = Date().timeIntervalSince1970
        let type = ContentClassifier.classify(trimmed)
        let isSensitive = SensitiveDetector.isSensitive(trimmed)

        return try dbWriter.write { db in
            if var existing = try ClipboardItem
                .filter(ClipboardItem.Columns.contentHash == hash)
                .fetchOne(db)
            {
                existing.copyCount += 1
                existing.lastUsedAt = now
                try existing.update(db)
                return existing
            }

            let item = ClipboardItem(
                id: UUID().uuidString,
                type: type,
                contentText: trimmed,
                contentHash: hash,
                sourceApp: input.sourceApp,
                sourceBundleId: input.sourceBundleId,
                preview: Self.makePreview(from: trimmed),
                title: nil,
                summary: nil,
                isFavorite: false,
                isSensitive: isSensitive,
                isDeleted: false,
                copyCount: 1,
                createdAt: now,
                lastUsedAt: now
            )
            try item.insert(db)
            try Self.insertMetadata(input.metadata, for: item.id, in: db)
            if let settings {
                try Self.enforceRetention(settings: settings, in: db)
            }
            return item
        }
    }

    func enforceRetention(settings: RetentionSettings) throws {
        guard !settings.infinite else { return }
        try dbWriter.write { db in
            try Self.enforceRetention(settings: settings, in: db)
        }
    }

    func clearHistory() throws {
        try dbWriter.write { db in
            let ids = try ClipboardItem
                .filter(ClipboardItem.Columns.isDeleted == false)
                .fetchAll(db)
                .map(\.id)
            try Self.deleteAssetFiles(for: ids, in: db)
            try Self.hardDeleteItems(ids: ids, in: db, deleteAssets: false)
        }
    }

    func emptyTrash() throws {
        try dbWriter.write { db in
            let ids = try ClipboardItem
                .filter(ClipboardItem.Columns.isDeleted == true)
                .fetchAll(db)
                .map(\.id)
            try Self.deleteAssetFiles(for: ids, in: db)
            try Self.hardDeleteItems(ids: ids, in: db, deleteAssets: false)
        }
    }

    func hardDeleteItems(ids: [String]) throws {
        guard !ids.isEmpty else { return }
        try dbWriter.write { db in
            try Self.deleteAssetFiles(for: ids, in: db)
            try Self.hardDeleteItems(ids: ids, in: db, deleteAssets: false)
        }
    }

    @discardableResult
    func insertImage(
        _ input: ClipboardImageInsertInput,
        retention settings: RetentionSettings? = nil
    ) throws -> ClipboardItem {
        guard !input.imageData.isEmpty else {
            throw ClipboardRepositoryError.emptyContent
        }

        let hash = Self.contentHash(for: input.imageData)
        let now = Date().timeIntervalSince1970

        return try dbWriter.write { db in
            if var existing = try ClipboardItem
                .filter(ClipboardItem.Columns.contentHash == hash)
                .fetchOne(db)
            {
                existing.copyCount += 1
                existing.lastUsedAt = now
                try existing.update(db)
                return existing
            }

            let itemID = UUID().uuidString
            let savedAsset = try AssetStore.saveImage(
                data: input.imageData,
                format: input.format.assetFormat,
                itemID: itemID,
                baseURL: assetBaseURL
            )
            let preview = Self.makeImagePreview(width: savedAsset.width, height: savedAsset.height)

            let item = ClipboardItem(
                id: itemID,
                type: "image",
                contentText: nil,
                contentHash: hash,
                sourceApp: input.sourceApp,
                sourceBundleId: input.sourceBundleId,
                preview: preview,
                title: nil,
                summary: nil,
                isFavorite: false,
                isSensitive: false,
                isDeleted: false,
                copyCount: 1,
                createdAt: now,
                lastUsedAt: now
            )
            try item.insert(db)

            try ClipboardAsset(
                itemId: itemID,
                filePath: savedAsset.filePath,
                thumbnailPath: savedAsset.thumbnailPath,
                mimeType: savedAsset.mimeType,
                width: savedAsset.width,
                height: savedAsset.height
            ).insert(db)

            if let settings {
                try Self.enforceRetention(settings: settings, in: db)
            }

            return item
        }
    }

    func fetchAsset(for itemID: String) throws -> ClipboardAsset? {
        try dbWriter.read { db in
            try ClipboardAsset.fetchOne(db, key: itemID)
        }
    }

    func fetchImageItemIDsMissingOCR() throws -> [String] {
        try dbWriter.read { db in
            let sql = """
                SELECT \(ClipboardAsset.Columns.itemId.rawValue)
                FROM \(ClipboardAsset.databaseTableName)
                JOIN \(ClipboardItem.databaseTableName)
                  ON \(ClipboardItem.databaseTableName).\(ClipboardItem.Columns.id.rawValue)
                   = \(ClipboardAsset.databaseTableName).\(ClipboardAsset.Columns.itemId.rawValue)
                WHERE \(ClipboardItem.databaseTableName).\(ClipboardItem.Columns.type.rawValue) = 'image'
                  AND \(ClipboardItem.databaseTableName).\(ClipboardItem.Columns.isDeleted.rawValue) = 0
                  AND (\(ClipboardAsset.databaseTableName).\(ClipboardAsset.Columns.ocrText.rawValue) IS NULL
                       OR \(ClipboardAsset.databaseTableName).\(ClipboardAsset.Columns.ocrText.rawValue) = '')
                """
            return try String.fetchAll(db, sql: sql)
        }
    }

    @discardableResult
    func applyOCRText(itemID: String, text: String) throws -> ClipboardItem {
        try dbWriter.write { db in
            guard var asset = try ClipboardAsset.fetchOne(db, key: itemID),
                  var item = try ClipboardItem.fetchOne(db, key: itemID)
            else {
                throw ClipboardRepositoryError.notFound
            }

            asset.ocrText = text
            try asset.update(db)

            item.contentText = text
            try item.update(db)

            return item
        }
    }

    func listByRecency(limit: Int = 200, includeSensitive: Bool = false) throws -> [ClipboardItem] {
        try dbWriter.read { db in
            var request = ClipboardItem
                .filter(ClipboardItem.Columns.isDeleted == false)

            if !includeSensitive {
                request = request.filter(ClipboardItem.Columns.isSensitive == false)
            }

            return try request
                .order(
                    sql: "COALESCE(\(ClipboardItem.Columns.lastUsedAt.rawValue), \(ClipboardItem.Columns.createdAt.rawValue)) DESC"
                )
                .limit(limit)
                .fetchAll(db)
        }
    }

    func search(
        _ query: String,
        limit: Int = 50,
        queryEmbedding: [Float]? = nil,
        embeddingModel: String? = nil
    ) throws -> [ClipboardItem] {
        let parsed = Self.parseSearchQuery(query)
        return try dbWriter.read { db in
            try Self.fetchSearchResults(
                parsed: parsed,
                limit: limit,
                queryEmbedding: queryEmbedding,
                embeddingModel: embeddingModel,
                in: db
            )
        }
    }

    func upsertEmbedding(itemID: String, model: String, vector: [Float]) throws {
        let record = ClipboardEmbedding(
            itemId: itemID,
            model: model,
            vector: VectorMath.encode(vector),
            createdAt: Date().timeIntervalSince1970
        )
        try dbWriter.write { db in
            try record.insert(db, onConflict: .replace)
        }
    }

    func fetchEmbedding(for itemID: String) throws -> ClipboardEmbedding? {
        try dbWriter.read { db in
            try ClipboardEmbedding.fetchOne(db, key: itemID)
        }
    }

    func applyAIMetadata(itemID: String, metadata: ClipAIMetadata) throws {
        try dbWriter.write { db in
            guard var item = try ClipboardItem.fetchOne(db, key: itemID) else {
                throw ClipboardRepositoryError.notFound
            }

            if let title = metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                item.title = title
            }
            if let summary = metadata.summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
                item.summary = summary
            }
            try item.update(db)

            try ClipboardTag
                .filter(ClipboardTag.Columns.clipboardItemId == itemID)
                .deleteAll(db)

            for tagName in metadata.tags {
                let normalized = tagName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalized.isEmpty else { continue }

                let tag: Tag
                if let existing = try Tag.filter(Tag.Columns.name == normalized).fetchOne(db) {
                    tag = existing
                } else {
                    tag = Tag(id: UUID().uuidString, name: normalized)
                    try tag.insert(db)
                }

                try ClipboardTag(clipboardItemId: itemID, tagId: tag.id).insert(db)
            }
        }
    }

    func fetchTags(for itemID: String) throws -> [Tag] {
        try dbWriter.read { db in
            try Tag.fetchAll(
                db,
                sql: """
                    SELECT \(Tag.databaseTableName).*
                    FROM \(Tag.databaseTableName)
                    JOIN \(ClipboardTag.databaseTableName)
                      ON \(ClipboardTag.databaseTableName).\(ClipboardTag.Columns.tagId.rawValue)
                         = \(Tag.databaseTableName).\(Tag.Columns.id.rawValue)
                    WHERE \(ClipboardTag.databaseTableName).\(ClipboardTag.Columns.clipboardItemId.rawValue) = ?
                    ORDER BY \(Tag.databaseTableName).\(Tag.Columns.name.rawValue) ASC
                    """,
                arguments: [itemID]
            )
        }
    }

    func fetchSimilarItems(
        for itemID: String,
        embeddingModel: String,
        limit: Int = 5
    ) throws -> [ClipboardItem] {
        try dbWriter.read { db in
            guard let embedding = try ClipboardEmbedding.fetchOne(db, key: itemID) else {
                return []
            }

            let queryVector = VectorMath.decode(embedding.vector)
            guard !queryVector.isEmpty else { return [] }

            let scored = try Self.semanticSearchScored(
                queryEmbedding: queryVector,
                embeddingModel: embeddingModel,
                parsed: ParsedSearchQuery(),
                limit: limit + 1,
                in: db
            )

            let similarIDs = scored
                .filter { $0.itemID != itemID && $0.score > 0.1 }
                .prefix(limit)
                .map(\.itemID)

            let items = try Self.fetchItems(ids: Array(similarIDs), in: db)
            let itemsByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
            return similarIDs.compactMap { itemsByID[$0] }
        }
    }

    func count() throws -> Int {
        try dbWriter.read { db in
            try ClipboardItem.fetchCount(db)
        }
    }

    func fetch(id: String) throws -> ClipboardItem? {
        try dbWriter.read { db in
            try ClipboardItem.fetchOne(db, key: id)
        }
    }

    func list(filter: LibraryFilter, limit: Int = 200) throws -> [ClipboardItem] {
        try dbWriter.read { db in
            var request = ClipboardItem.all()

            switch filter {
            case .all:
                request = request
                    .filter(ClipboardItem.Columns.isDeleted == false)
                    .filter(ClipboardItem.Columns.isSensitive == false)
            case .text:
                request = request
                    .filter(ClipboardItem.Columns.isDeleted == false)
                    .filter(ClipboardItem.Columns.isSensitive == false)
                    .filter(ClipboardItem.Columns.type == "text")
            case .code:
                request = request
                    .filter(ClipboardItem.Columns.isDeleted == false)
                    .filter(ClipboardItem.Columns.isSensitive == false)
                    .filter(ClipboardItem.Columns.type == "code")
            case .links:
                request = request
                    .filter(ClipboardItem.Columns.isDeleted == false)
                    .filter(ClipboardItem.Columns.isSensitive == false)
                    .filter(ClipboardItem.Columns.type == "url")
            case .images:
                request = request
                    .filter(ClipboardItem.Columns.isDeleted == false)
                    .filter(ClipboardItem.Columns.isSensitive == false)
                    .filter(ClipboardItem.Columns.type == "image")
            case .files:
                request = request
                    .filter(ClipboardItem.Columns.isDeleted == false)
                    .filter(ClipboardItem.Columns.isSensitive == false)
                    .filter(ClipboardItem.Columns.type == "file")
            case .favorites:
                request = request
                    .filter(ClipboardItem.Columns.isDeleted == false)
                    .filter(ClipboardItem.Columns.isSensitive == false)
                    .filter(ClipboardItem.Columns.isFavorite == true)
            case .sensitive:
                request = request
                    .filter(ClipboardItem.Columns.isDeleted == false)
                    .filter(ClipboardItem.Columns.isSensitive == true)
            case .trash:
                request = request.filter(ClipboardItem.Columns.isDeleted == true)
            }

            return try request
                .order(
                    sql: "COALESCE(\(ClipboardItem.Columns.lastUsedAt.rawValue), \(ClipboardItem.Columns.createdAt.rawValue)) DESC"
                )
                .limit(limit)
                .fetchAll(db)
        }
    }

    @discardableResult
    func toggleFavorite(id: String) throws -> ClipboardItem {
        try dbWriter.write { db in
            guard var item = try ClipboardItem.fetchOne(db, key: id) else {
                throw ClipboardRepositoryError.notFound
            }
            item.isFavorite.toggle()
            try item.update(db)
            return item
        }
    }

    func softDelete(id: String) throws {
        try dbWriter.write { db in
            guard var item = try ClipboardItem.fetchOne(db, key: id) else {
                throw ClipboardRepositoryError.notFound
            }
            item.isDeleted = true
            try item.update(db)
        }
    }

    func restore(id: String) throws {
        try dbWriter.write { db in
            guard var item = try ClipboardItem.fetchOne(db, key: id) else {
                throw ClipboardRepositoryError.notFound
            }
            item.isDeleted = false
            try item.update(db)
        }
    }

    func touchLastUsed(id: String) throws {
        try dbWriter.write { db in
            guard var item = try ClipboardItem.fetchOne(db, key: id) else {
                throw ClipboardRepositoryError.notFound
            }
            item.lastUsedAt = Date().timeIntervalSince1970
            try item.update(db)
        }
    }

    static func parseSearchQuery(_ query: String) -> ParsedSearchQuery {
        var parsed = ParsedSearchQuery()
        var terms: [String] = []

        for part in query.split(whereSeparator: \.isWhitespace) {
            let token = String(part)
            let lowercased = token.lowercased()

            if lowercased.hasPrefix("type:") {
                parsed.typeFilter = String(token.dropFirst("type:".count))
            } else if lowercased.hasPrefix("from:") {
                parsed.fromFilter = String(token.dropFirst("from:".count))
            } else if lowercased.hasPrefix("tag:") {
                parsed.tagFilter = String(token.dropFirst("tag:".count))
            } else if lowercased == "is:favorite" {
                parsed.favoritesOnly = true
            } else if lowercased == "is:sensitive" {
                parsed.includeSensitive = true
            } else {
                terms.append(token)
            }
        }

        parsed.keywords = terms.joined(separator: " ")
        return parsed
    }

    static func contentHash(for text: String) -> String {
        contentHash(for: Data(text.utf8))
    }

    static func contentHash(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func makeImagePreview(width: Int, height: Int) -> String {
        "Image \(width)×\(height)"
    }

    private static func ftsMatchQuery(from keywords: String) -> String {
        keywords
            .split(whereSeparator: \.isWhitespace)
            .map { token in
                let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
            .joined(separator: " ")
    }

    static func makePreview(from text: String, maxLength: Int = 200) -> String {
        let collapsed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if collapsed.count <= maxLength {
            return collapsed
        }
        let endIndex = collapsed.index(collapsed.startIndex, offsetBy: maxLength)
        return String(collapsed[..<endIndex]) + "…"
    }

    private static func insertMetadata(
        _ metadata: [String: String],
        for itemID: String,
        in db: Database
    ) throws {
        for (key, value) in metadata where !value.isEmpty {
            try ClipboardItemMetadata(
                clipboardItemId: itemID,
                key: key,
                value: value
            ).insert(db)
        }
    }

    private static func fetchSearchResults(
        parsed: ParsedSearchQuery,
        limit: Int,
        queryEmbedding: [Float]? = nil,
        embeddingModel: String? = nil,
        in db: Database
    ) throws -> [ClipboardItem] {
        let keywords = parsed.keywords.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasKeywords = !keywords.isEmpty

        if hasKeywords, let queryEmbedding, let embeddingModel, parsed.qualifiesForSemanticSearch {
            return try searchHybrid(
                keywords: keywords,
                parsed: parsed,
                limit: limit,
                queryEmbedding: queryEmbedding,
                embeddingModel: embeddingModel,
                in: db
            )
        }

        if hasKeywords {
            return try searchWithFTS(
                keywords: keywords,
                parsed: parsed,
                limit: limit,
                in: db
            )
        }

        return try filterOnlySearch(parsed: parsed, limit: limit, in: db)
    }

    private static func searchHybrid(
        keywords: String,
        parsed: ParsedSearchQuery,
        limit: Int,
        queryEmbedding: [Float],
        embeddingModel: String,
        in db: Database
    ) throws -> [ClipboardItem] {
        let ftsRanked = try searchWithFTSScored(
            keywords: keywords,
            parsed: parsed,
            limit: limit * 2,
            in: db
        )
        let semanticRanked = try semanticSearchScored(
            queryEmbedding: queryEmbedding,
            embeddingModel: embeddingModel,
            parsed: parsed,
            limit: limit * 2,
            in: db
        )

        if semanticRanked.isEmpty {
            return ftsRanked.prefix(limit).map(\.item)
        }

        let mergedIDs = SemanticSearchService.mergeHybridResults(
            ftsRanked: ftsRanked.map { ScoredItemID(itemID: $0.item.id, score: $0.rankScore) },
            semanticRanked: semanticRanked,
            limit: limit
        )

        let mergedItems = try fetchItems(ids: mergedIDs, in: db)
        let itemsByID = Dictionary(
            uniqueKeysWithValues: (ftsRanked.map(\.item) + mergedItems)
                .map { ($0.id, $0) }
        )

        return mergedIDs.compactMap { itemsByID[$0] }
    }

    private struct RankedClipboardItem {
        let item: ClipboardItem
        let rankScore: Double
    }

    private static func searchWithFTSScored(
        keywords: String,
        parsed: ParsedSearchQuery,
        limit: Int,
        in db: Database
    ) throws -> [RankedClipboardItem] {
        var sql = """
            SELECT \(ClipboardItem.databaseTableName).*,
                   bm25(\(DatabaseManager.ftsTableName)) AS fts_rank
            FROM \(ClipboardItem.databaseTableName)
            JOIN \(DatabaseManager.ftsTableName)
              ON \(DatabaseManager.ftsTableName).rowid = \(ClipboardItem.databaseTableName).rowid
            WHERE \(DatabaseManager.ftsTableName) MATCH ?
              AND \(ClipboardItem.Columns.isDeleted.rawValue) = 0
            """
        var arguments: [DatabaseValueConvertible] = [ftsMatchQuery(from: keywords)]

        appendSensitiveFilter(to: &sql, arguments: &arguments, parsed: parsed)
        appendTypeFilter(to: &sql, arguments: &arguments, parsed: parsed)
        appendFromFilter(to: &sql, arguments: &arguments, parsed: parsed)
        appendTagFilter(to: &sql, arguments: &arguments, parsed: parsed)
        appendFavoriteFilter(to: &sql, arguments: &arguments, parsed: parsed)

        sql += """
             ORDER BY fts_rank,
                      \(ClipboardItem.Columns.createdAt.rawValue) DESC
             LIMIT ?
            """
        arguments.append(limit)

        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        return rows.compactMap { row in
            guard let item = try? ClipboardItem(row: row) else { return nil }
            let rank = abs(row["fts_rank"] as? Double ?? 0)
            return RankedClipboardItem(item: item, rankScore: rank)
        }
    }

    private static func semanticSearchScored(
        queryEmbedding: [Float],
        embeddingModel: String,
        parsed: ParsedSearchQuery,
        limit: Int,
        in db: Database
    ) throws -> [ScoredItemID] {
        var sql = """
            SELECT \(ClipboardEmbedding.databaseTableName).\(ClipboardEmbedding.Columns.itemId.rawValue),
                   \(ClipboardEmbedding.databaseTableName).\(ClipboardEmbedding.Columns.vector.rawValue)
            FROM \(ClipboardEmbedding.databaseTableName)
            JOIN \(ClipboardItem.databaseTableName)
              ON \(ClipboardItem.databaseTableName).\(ClipboardItem.Columns.id.rawValue)
                 = \(ClipboardEmbedding.databaseTableName).\(ClipboardEmbedding.Columns.itemId.rawValue)
            WHERE \(ClipboardItem.Columns.isDeleted.rawValue) = 0
              AND \(ClipboardEmbedding.databaseTableName).\(ClipboardEmbedding.Columns.model.rawValue) = ?
            """
        var arguments: [DatabaseValueConvertible] = [embeddingModel]

        appendSensitiveFilter(to: &sql, arguments: &arguments, parsed: parsed)
        appendTypeFilter(to: &sql, arguments: &arguments, parsed: parsed)
        appendFromFilter(to: &sql, arguments: &arguments, parsed: parsed)
        appendTagFilter(to: &sql, arguments: &arguments, parsed: parsed)
        appendFavoriteFilter(to: &sql, arguments: &arguments, parsed: parsed)

        let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
        let candidates = rows.compactMap { row -> (itemID: String, vector: [Float])? in
            guard let itemID: String = row[ClipboardEmbedding.Columns.itemId.rawValue],
                  let vectorData: Data = row[ClipboardEmbedding.Columns.vector.rawValue]
            else {
                return nil
            }
            let vector = VectorMath.decode(vectorData)
            guard !vector.isEmpty else { return nil }
            return (itemID, vector)
        }

        return SemanticSearchService.rank(queryEmbedding: queryEmbedding, candidates: candidates)
            .prefix(limit)
            .map { $0 }
    }

    private static func fetchItems(ids: [String], in db: Database) throws -> [ClipboardItem] {
        guard !ids.isEmpty else { return [] }
        return try ClipboardItem.fetchAll(db, keys: ids)
    }

    private static func searchWithFTS(
        keywords: String,
        parsed: ParsedSearchQuery,
        limit: Int,
        in db: Database
    ) throws -> [ClipboardItem] {
        var sql = """
            SELECT \(ClipboardItem.databaseTableName).*
            FROM \(ClipboardItem.databaseTableName)
            JOIN \(DatabaseManager.ftsTableName)
              ON \(DatabaseManager.ftsTableName).rowid = \(ClipboardItem.databaseTableName).rowid
            WHERE \(DatabaseManager.ftsTableName) MATCH ?
              AND \(ClipboardItem.Columns.isDeleted.rawValue) = 0
            """
        var arguments: [DatabaseValueConvertible] = [ftsMatchQuery(from: keywords)]

        appendSensitiveFilter(to: &sql, arguments: &arguments, parsed: parsed)
        appendTypeFilter(to: &sql, arguments: &arguments, parsed: parsed)
        appendFromFilter(to: &sql, arguments: &arguments, parsed: parsed)
        appendTagFilter(to: &sql, arguments: &arguments, parsed: parsed)
        appendFavoriteFilter(to: &sql, arguments: &arguments, parsed: parsed)

        sql += """
             ORDER BY bm25(\(DatabaseManager.ftsTableName)),
                      \(ClipboardItem.Columns.createdAt.rawValue) DESC
             LIMIT ?
            """
        arguments.append(limit)

        return try ClipboardItem.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
    }

    private static func filterOnlySearch(
        parsed: ParsedSearchQuery,
        limit: Int,
        in db: Database
    ) throws -> [ClipboardItem] {
        var sql = """
            SELECT *
            FROM \(ClipboardItem.databaseTableName)
            WHERE \(ClipboardItem.Columns.isDeleted.rawValue) = 0
            """
        var arguments: [DatabaseValueConvertible] = []

        appendSensitiveFilter(to: &sql, arguments: &arguments, parsed: parsed)
        appendTypeFilter(to: &sql, arguments: &arguments, parsed: parsed)
        appendFromFilter(to: &sql, arguments: &arguments, parsed: parsed)
        appendTagFilter(to: &sql, arguments: &arguments, parsed: parsed)
        appendFavoriteFilter(to: &sql, arguments: &arguments, parsed: parsed)

        sql += """
             ORDER BY COALESCE(\(ClipboardItem.Columns.lastUsedAt.rawValue), \(ClipboardItem.Columns.createdAt.rawValue)) DESC
             LIMIT ?
            """
        arguments.append(limit)

        return try ClipboardItem.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
    }

    private static func appendSensitiveFilter(
        to sql: inout String,
        arguments: inout [DatabaseValueConvertible],
        parsed: ParsedSearchQuery
    ) {
        if parsed.includeSensitive {
            sql += " AND \(ClipboardItem.Columns.isSensitive.rawValue) = 1"
        } else {
            sql += " AND \(ClipboardItem.Columns.isSensitive.rawValue) = 0"
        }
    }

    private static func appendTypeFilter(
        to sql: inout String,
        arguments: inout [DatabaseValueConvertible],
        parsed: ParsedSearchQuery
    ) {
        guard let typeFilter = parsed.typeFilter?.lowercased(), !typeFilter.isEmpty else {
            return
        }
        sql += " AND LOWER(\(ClipboardItem.Columns.type.rawValue)) = ?"
        arguments.append(typeFilter)
    }

    private static func appendFromFilter(
        to sql: inout String,
        arguments: inout [DatabaseValueConvertible],
        parsed: ParsedSearchQuery
    ) {
        guard let fromFilter = parsed.fromFilter?.lowercased(), !fromFilter.isEmpty else {
            return
        }
        let pattern = "%\(fromFilter)%"
        sql += """
             AND (
               LOWER(COALESCE(\(ClipboardItem.Columns.sourceApp.rawValue), '')) LIKE ?
               OR LOWER(COALESCE(\(ClipboardItem.Columns.sourceBundleId.rawValue), '')) LIKE ?
             )
            """
        arguments.append(pattern)
        arguments.append(pattern)
    }

    private static func appendTagFilter(
        to sql: inout String,
        arguments: inout [DatabaseValueConvertible],
        parsed: ParsedSearchQuery
    ) {
        guard let tagFilter = parsed.tagFilter?.lowercased(), !tagFilter.isEmpty else {
            return
        }
        sql += """
             AND EXISTS (
               SELECT 1
               FROM \(ClipboardTag.databaseTableName)
               JOIN \(Tag.databaseTableName)
                 ON \(Tag.databaseTableName).\(Tag.Columns.id.rawValue)
                    = \(ClipboardTag.databaseTableName).\(ClipboardTag.Columns.tagId.rawValue)
               WHERE \(ClipboardTag.databaseTableName).\(ClipboardTag.Columns.clipboardItemId.rawValue)
                     = \(ClipboardItem.databaseTableName).\(ClipboardItem.Columns.id.rawValue)
                 AND LOWER(\(Tag.databaseTableName).\(Tag.Columns.name.rawValue)) = ?
             )
            """
        arguments.append(tagFilter)
    }

    private static func appendFavoriteFilter(
        to sql: inout String,
        arguments: inout [DatabaseValueConvertible],
        parsed: ParsedSearchQuery
    ) {
        guard parsed.favoritesOnly == true else {
            return
        }
        sql += " AND \(ClipboardItem.Columns.isFavorite.rawValue) = 1"
    }

    private static func enforceRetention(settings: RetentionSettings, in db: Database) throws {
        guard !settings.infinite else { return }

        let now = Date().timeIntervalSince1970
        let cutoff = now - Double(settings.maxAgeDays) * 86_400
        var idsToDelete = Set<String>()

        let ageCandidates = try ClipboardItem
            .filter(ClipboardItem.Columns.isDeleted == false)
            .filter(ClipboardItem.Columns.isFavorite == false)
            .filter(
                sql: "COALESCE(\(ClipboardItem.Columns.lastUsedAt.rawValue), \(ClipboardItem.Columns.createdAt.rawValue)) < ?",
                arguments: [cutoff]
            )
            .fetchAll(db)
        idsToDelete.formUnion(ageCandidates.map(\.id))

        let activeNonFavorite = try ClipboardItem
            .filter(ClipboardItem.Columns.isDeleted == false)
            .filter(ClipboardItem.Columns.isFavorite == false)
            .order(
                sql: "COALESCE(\(ClipboardItem.Columns.lastUsedAt.rawValue), \(ClipboardItem.Columns.createdAt.rawValue)) ASC"
            )
            .fetchAll(db)

        let excess = activeNonFavorite.count - settings.maxCount
        if excess > 0 {
            idsToDelete.formUnion(activeNonFavorite.prefix(excess).map(\.id))
        }

        try hardDeleteItems(ids: Array(idsToDelete), in: db, deleteAssets: true)
    }

    private static func hardDeleteItems(ids: [String], in db: Database, deleteAssets: Bool) throws {
        guard !ids.isEmpty else { return }
        if deleteAssets {
            try deleteAssetFiles(for: ids, in: db)
        }
        try ClipboardItem.deleteAll(db, keys: ids)
    }

    private static func deleteAssetFiles(for itemIDs: [String], in db: Database) throws {
        guard !itemIDs.isEmpty else { return }
        guard try db.tableExists(assetsTableName) else { return }

        let placeholders = Array(repeating: "?", count: itemIDs.count).joined(separator: ", ")
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT file_path, thumbnail_path FROM \(assetsTableName) WHERE item_id IN (\(placeholders))",
            arguments: StatementArguments(itemIDs)
        )

        let fileManager = FileManager.default
        for row in rows {
            if let path: String = row["file_path"], !path.isEmpty {
                try? fileManager.removeItem(atPath: path)
            }
            if let thumbnail: String = row["thumbnail_path"], !thumbnail.isEmpty {
                try? fileManager.removeItem(atPath: thumbnail)
            }
        }
    }
}
