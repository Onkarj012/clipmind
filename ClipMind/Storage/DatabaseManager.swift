import Foundation
import GRDB

enum DatabaseManager {
    static let appSupportSubpath = "ClipMind"
    static let ftsTableName = "clipboard_items_fts"

    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: ClipboardItem.databaseTableName) { table in
                table.column(ClipboardItem.Columns.id.rawValue, .text).primaryKey()
                table.column(ClipboardItem.Columns.type.rawValue, .text).notNull()
                table.column(ClipboardItem.Columns.contentText.rawValue, .text)
                table.column(ClipboardItem.Columns.contentHash.rawValue, .text).notNull().unique()
                table.column(ClipboardItem.Columns.sourceApp.rawValue, .text)
                table.column(ClipboardItem.Columns.sourceBundleId.rawValue, .text)
                table.column(ClipboardItem.Columns.preview.rawValue, .text)
                table.column(ClipboardItem.Columns.title.rawValue, .text)
                table.column(ClipboardItem.Columns.isFavorite.rawValue, .integer).notNull().defaults(to: 0)
                table.column(ClipboardItem.Columns.isSensitive.rawValue, .integer).notNull().defaults(to: 0)
                table.column(ClipboardItem.Columns.isDeleted.rawValue, .integer).notNull().defaults(to: 0)
                table.column(ClipboardItem.Columns.copyCount.rawValue, .integer).notNull().defaults(to: 1)
                table.column(ClipboardItem.Columns.createdAt.rawValue, .double).notNull()
                table.column(ClipboardItem.Columns.lastUsedAt.rawValue, .double)
            }
        }

        migrator.registerMigration("v2_fts_metadata") { db in
            try db.create(table: ClipboardItemMetadata.databaseTableName) { table in
                table.column(ClipboardItemMetadata.Columns.clipboardItemId.rawValue, .text)
                    .notNull()
                    .references(ClipboardItem.databaseTableName, onDelete: .cascade)
                table.column(ClipboardItemMetadata.Columns.key.rawValue, .text).notNull()
                table.column(ClipboardItemMetadata.Columns.value.rawValue, .text).notNull()
                table.primaryKey([
                    ClipboardItemMetadata.Columns.clipboardItemId.rawValue,
                    ClipboardItemMetadata.Columns.key.rawValue,
                ])
            }

            try db.execute(sql: """
                CREATE VIRTUAL TABLE \(ftsTableName) USING fts5(
                    content_text,
                    preview,
                    title,
                    source_app,
                    content='\(ClipboardItem.databaseTableName)',
                    content_rowid='rowid'
                );
                """)

            try db.execute(sql: """
                CREATE TRIGGER clipboard_items_ai AFTER INSERT ON \(ClipboardItem.databaseTableName) BEGIN
                    INSERT INTO \(ftsTableName)(rowid, content_text, preview, title, source_app)
                    VALUES (
                        new.rowid,
                        new.\(ClipboardItem.Columns.contentText.rawValue),
                        new.\(ClipboardItem.Columns.preview.rawValue),
                        new.\(ClipboardItem.Columns.title.rawValue),
                        new.\(ClipboardItem.Columns.sourceApp.rawValue)
                    );
                END;
                """)

            try db.execute(sql: """
                CREATE TRIGGER clipboard_items_ad AFTER DELETE ON \(ClipboardItem.databaseTableName) BEGIN
                    INSERT INTO \(ftsTableName)(\(ftsTableName), rowid, content_text, preview, title, source_app)
                    VALUES (
                        'delete',
                        old.rowid,
                        old.\(ClipboardItem.Columns.contentText.rawValue),
                        old.\(ClipboardItem.Columns.preview.rawValue),
                        old.\(ClipboardItem.Columns.title.rawValue),
                        old.\(ClipboardItem.Columns.sourceApp.rawValue)
                    );
                END;
                """)

            try db.execute(sql: """
                CREATE TRIGGER clipboard_items_au AFTER UPDATE ON \(ClipboardItem.databaseTableName) BEGIN
                    INSERT INTO \(ftsTableName)(\(ftsTableName), rowid, content_text, preview, title, source_app)
                    VALUES (
                        'delete',
                        old.rowid,
                        old.\(ClipboardItem.Columns.contentText.rawValue),
                        old.\(ClipboardItem.Columns.preview.rawValue),
                        old.\(ClipboardItem.Columns.title.rawValue),
                        old.\(ClipboardItem.Columns.sourceApp.rawValue)
                    );
                    INSERT INTO \(ftsTableName)(rowid, content_text, preview, title, source_app)
                    VALUES (
                        new.rowid,
                        new.\(ClipboardItem.Columns.contentText.rawValue),
                        new.\(ClipboardItem.Columns.preview.rawValue),
                        new.\(ClipboardItem.Columns.title.rawValue),
                        new.\(ClipboardItem.Columns.sourceApp.rawValue)
                    );
                END;
                """)

            try db.execute(sql: """
                INSERT INTO \(ftsTableName)(rowid, content_text, preview, title, source_app)
                SELECT rowid,
                       \(ClipboardItem.Columns.contentText.rawValue),
                       \(ClipboardItem.Columns.preview.rawValue),
                       \(ClipboardItem.Columns.title.rawValue),
                       \(ClipboardItem.Columns.sourceApp.rawValue)
                FROM \(ClipboardItem.databaseTableName);
                """)
        }

        migrator.registerMigration("v3_assets") { db in
            try db.create(table: ClipboardAsset.databaseTableName) { table in
                table.column(ClipboardAsset.Columns.itemId.rawValue, .text)
                    .primaryKey()
                    .references(ClipboardItem.databaseTableName, onDelete: .cascade)
                table.column(ClipboardAsset.Columns.filePath.rawValue, .text).notNull()
                table.column(ClipboardAsset.Columns.thumbnailPath.rawValue, .text)
                table.column(ClipboardAsset.Columns.mimeType.rawValue, .text).notNull()
                table.column(ClipboardAsset.Columns.width.rawValue, .integer).notNull()
                table.column(ClipboardAsset.Columns.height.rawValue, .integer).notNull()
            }
        }

        migrator.registerMigration("v4_embeddings") { db in
            try db.create(table: ClipboardEmbedding.databaseTableName) { table in
                table.column(ClipboardEmbedding.Columns.itemId.rawValue, .text)
                    .primaryKey()
                    .references(ClipboardItem.databaseTableName, onDelete: .cascade)
                table.column(ClipboardEmbedding.Columns.model.rawValue, .text).notNull()
                table.column(ClipboardEmbedding.Columns.vector.rawValue, .blob).notNull()
                table.column(ClipboardEmbedding.Columns.createdAt.rawValue, .double).notNull()
            }
        }

        migrator.registerMigration("v5_ai_metadata") { db in
            try db.alter(table: ClipboardItem.databaseTableName) { table in
                table.add(column: ClipboardItem.Columns.summary.rawValue, .text)
            }

            try db.create(table: Tag.databaseTableName) { table in
                table.column(Tag.Columns.id.rawValue, .text).primaryKey()
                table.column(Tag.Columns.name.rawValue, .text).notNull().unique()
            }

            try db.create(table: ClipboardTag.databaseTableName) { table in
                table.column(ClipboardTag.Columns.clipboardItemId.rawValue, .text)
                    .notNull()
                    .references(ClipboardItem.databaseTableName, onDelete: .cascade)
                table.column(ClipboardTag.Columns.tagId.rawValue, .text)
                    .notNull()
                    .references(Tag.databaseTableName, onDelete: .cascade)
                table.primaryKey([
                    ClipboardTag.Columns.clipboardItemId.rawValue,
                    ClipboardTag.Columns.tagId.rawValue,
                ])
            }
        }

        migrator.registerMigration("v6_ocr_text") { db in
            try db.alter(table: ClipboardAsset.databaseTableName) { table in
                table.add(column: ClipboardAsset.Columns.ocrText.rawValue, .text)
            }
        }

        return migrator
    }

    static func applicationSupportURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appURL = base.appendingPathComponent(appSupportSubpath, isDirectory: true)
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        return appURL
    }

    static func openProductionQueue() throws -> DatabaseQueue {
        let databaseURL = try applicationSupportURL().appendingPathComponent("database.sqlite")
        let queue = try DatabaseQueue(path: databaseURL.path)
        try makeMigrator().migrate(queue)
        return queue
    }

    static func openInMemoryQueue() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try makeMigrator().migrate(queue)
        return queue
    }
}
