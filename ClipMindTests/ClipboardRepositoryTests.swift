import AppKit
import GRDB
import XCTest
@testable import ClipMind

final class ClipboardRepositoryTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private var repository: ClipboardRepository!
    private var assetBaseURL: URL!

    override func setUpWithError() throws {
        dbQueue = try DatabaseManager.openInMemoryQueue()
        assetBaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipMindTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: assetBaseURL, withIntermediateDirectories: true)
        repository = ClipboardRepository(dbWriter: dbQueue, assetBaseURL: assetBaseURL)
    }

    override func tearDownWithError() throws {
        repository = nil
        dbQueue = nil
        if let assetBaseURL {
            try? FileManager.default.removeItem(at: assetBaseURL)
        }
        assetBaseURL = nil
    }

    func testInsertAndRetrieve() throws {
        let item = try repository.insertText(
            ClipboardInsertInput(
                text: "Hello, ClipMind!",
                sourceApp: "Safari",
                sourceBundleId: "com.apple.Safari"
            )
        )

        XCTAssertEqual(item.type, "text")
        XCTAssertEqual(item.contentText, "Hello, ClipMind!")
        XCTAssertEqual(item.sourceApp, "Safari")
        XCTAssertEqual(item.sourceBundleId, "com.apple.Safari")
        XCTAssertEqual(item.copyCount, 1)
        XCTAssertFalse(item.isDeleted)
        XCTAssertFalse(item.isSensitive)

        let items = try repository.listByRecency()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, item.id)
        XCTAssertEqual(items[0].preview, "Hello, ClipMind!")
    }

    func testDedupIncrementsCopyCount() throws {
        let first = try repository.insertText(
            ClipboardInsertInput(text: "duplicate me", sourceApp: "Notes", sourceBundleId: "com.apple.Notes")
        )
        let second = try repository.insertText(
            ClipboardInsertInput(text: "duplicate me", sourceApp: "Terminal", sourceBundleId: "com.apple.Terminal")
        )

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.copyCount, 2)
        XCTAssertEqual(try repository.count(), 1)

        let listed = try repository.listByRecency()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0].copyCount, 2)
    }

    func testListByRecencyOrdersMostRecentlyUsedFirst() throws {
        _ = try repository.insertText(
            ClipboardInsertInput(text: "older clip", sourceApp: "A", sourceBundleId: "a")
        )

        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE \(ClipboardItem.databaseTableName)
                SET \(ClipboardItem.Columns.lastUsedAt.rawValue) = ?
                WHERE \(ClipboardItem.Columns.contentText.rawValue) = ?
                """,
                arguments: [Date().addingTimeInterval(-3600).timeIntervalSince1970, "older clip"]
            )
        }

        let newer = try repository.insertText(
            ClipboardInsertInput(text: "newer clip", sourceApp: "B", sourceBundleId: "b")
        )

        let items = try repository.listByRecency()
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].id, newer.id)
    }

    func testEmptyContentIsRejected() {
        XCTAssertThrowsError(
            try repository.insertText(
                ClipboardInsertInput(text: "   \n  ", sourceApp: nil, sourceBundleId: nil)
            )
        ) { error in
            XCTAssertEqual(error as? ClipboardRepositoryError, .emptyContent)
        }
    }

    func testURLClassification() throws {
        let item = try repository.insertText(
            ClipboardInsertInput(
                text: "https://swift.org/documentation",
                sourceApp: "Safari",
                sourceBundleId: "com.apple.Safari"
            )
        )

        XCTAssertEqual(item.type, "url")
    }

    func testCodeClassification() throws {
        let item = try repository.insertText(
            ClipboardInsertInput(
                text: """
                import Foundation

                func greet() {
                    print("hello")
                }
                """,
                sourceApp: "Xcode",
                sourceBundleId: "com.apple.dt.Xcode"
            )
        )

        XCTAssertEqual(item.type, "code")
    }

    func testRichTextMetadataIsStored() throws {
        let item = try repository.insertText(
            ClipboardInsertInput(
                text: "Bold headline",
                sourceApp: "Notes",
                sourceBundleId: "com.apple.Notes",
                metadata: [
                    "rich_rtf": "eHh4",
                    "rich_html": "PGI+",
                ]
            )
        )

        let metadata = try dbQueue.read { db in
            try ClipboardItemMetadata
                .filter(ClipboardItemMetadata.Columns.clipboardItemId == item.id)
                .fetchAll(db)
        }

        XCTAssertEqual(metadata.count, 2)
        XCTAssertTrue(metadata.contains { $0.key == "rich_rtf" && $0.value == "eHh4" })
        XCTAssertTrue(metadata.contains { $0.key == "rich_html" && $0.value == "PGI+" })
    }

    func testSensitiveClipIsSavedButHiddenByDefault() throws {
        let sensitive = try repository.insertText(
            ClipboardInsertInput(
                text: "export OPENAI_API_KEY=sk-abcdefghijklmnopqrstuvwxyz",
                sourceApp: "Terminal",
                sourceBundleId: "com.apple.Terminal"
            )
        )
        let normal = try repository.insertText(
            ClipboardInsertInput(
                text: "public note",
                sourceApp: "Notes",
                sourceBundleId: "com.apple.Notes"
            )
        )

        XCTAssertTrue(sensitive.isSensitive)
        XCTAssertEqual(try repository.count(), 2)

        let listed = try repository.listByRecency()
        XCTAssertEqual(listed.count, 1)
        XCTAssertEqual(listed[0].id, normal.id)
    }

    func testSensitivePrefixReturnsSensitiveClips() throws {
        _ = try repository.insertText(
            ClipboardInsertInput(
                text: "ghp_abcdefghijklmnopqrstuvwxyz1234567890",
                sourceApp: "Terminal",
                sourceBundleId: "com.apple.Terminal"
            )
        )
        _ = try repository.insertText(
            ClipboardInsertInput(
                text: "safe clip",
                sourceApp: "Notes",
                sourceBundleId: "com.apple.Notes"
            )
        )

        let results = try repository.search("is:sensitive")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].isSensitive)
    }

    func testTypePrefixFiltersResults() throws {
        _ = try repository.insertText(
            ClipboardInsertInput(
                text: "https://example.com",
                sourceApp: "Safari",
                sourceBundleId: "com.apple.Safari"
            )
        )
        _ = try repository.insertText(
            ClipboardInsertInput(
                text: "plain memo",
                sourceApp: "Notes",
                sourceBundleId: "com.apple.Notes"
            )
        )

        let results = try repository.search("type:url")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].type, "url")
    }

    func testFromPrefixFiltersResults() throws {
        _ = try repository.insertText(
            ClipboardInsertInput(
                text: "safari clip",
                sourceApp: "Safari",
                sourceBundleId: "com.apple.Safari"
            )
        )
        _ = try repository.insertText(
            ClipboardInsertInput(
                text: "notes clip",
                sourceApp: "Notes",
                sourceBundleId: "com.apple.Notes"
            )
        )

        let results = try repository.search("from:safari")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].sourceApp, "Safari")
    }

    func testKeywordSearchFindsMatchingClip() throws {
        _ = try repository.insertText(
            ClipboardInsertInput(
                text: "react error boundary failed to render",
                sourceApp: "VS Code",
                sourceBundleId: "com.microsoft.VSCode"
            )
        )
        _ = try repository.insertText(
            ClipboardInsertInput(
                text: "unrelated grocery list",
                sourceApp: "Notes",
                sourceBundleId: "com.apple.Notes"
            )
        )

        let results = try repository.search("react error")
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].contentText?.contains("react error") == true)
    }

    func testSearchExcludesSensitiveByDefault() throws {
        _ = try repository.insertText(
            ClipboardInsertInput(
                text: "token sk-live-abcdefghijklmnopqrstuvwxyz",
                sourceApp: "Terminal",
                sourceBundleId: "com.apple.Terminal"
            )
        )
        _ = try repository.insertText(
            ClipboardInsertInput(
                text: "react error in component",
                sourceApp: "VS Code",
                sourceBundleId: "com.microsoft.VSCode"
            )
        )

        let results = try repository.search("react")
        XCTAssertEqual(results.count, 1)
        XCTAssertFalse(results[0].isSensitive)
    }

    func testRetentionPurgesOldestNonFavoriteWhenOverCount() throws {
        let retention = RetentionSettings(maxCount: 2, maxAgeDays: 365, infinite: false)

        let first = try repository.insertText(
            ClipboardInsertInput(text: "first", sourceApp: "A", sourceBundleId: "a"),
            retention: retention
        )
        _ = try repository.insertText(
            ClipboardInsertInput(text: "second", sourceApp: "B", sourceBundleId: "b"),
            retention: retention
        )
        let third = try repository.insertText(
            ClipboardInsertInput(text: "third", sourceApp: "C", sourceBundleId: "c"),
            retention: retention
        )

        let items = try repository.listByRecency(includeSensitive: true)
        XCTAssertEqual(items.count, 2)
        XCTAssertNil(try repository.fetch(id: first.id))
        XCTAssertTrue(items.contains { $0.id == third.id })
    }

    func testRetentionDoesNotPurgeFavorites() throws {
        let retention = RetentionSettings(maxCount: 1, maxAgeDays: 365, infinite: false)

        let favorite = try repository.insertText(
            ClipboardInsertInput(text: "favorite clip", sourceApp: "A", sourceBundleId: "a"),
            retention: retention
        )
        _ = try repository.toggleFavorite(id: favorite.id)

        _ = try repository.insertText(
            ClipboardInsertInput(text: "newer clip", sourceApp: "B", sourceBundleId: "b"),
            retention: retention
        )

        let items = try repository.listByRecency(includeSensitive: true)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.contains { $0.id == favorite.id && $0.isFavorite })
    }

    func testRetentionInfiniteDisablesPurge() throws {
        let retention = RetentionSettings(maxCount: 1, maxAgeDays: 1, infinite: true)

        _ = try repository.insertText(
            ClipboardInsertInput(text: "first", sourceApp: "A", sourceBundleId: "a"),
            retention: retention
        )
        _ = try repository.insertText(
            ClipboardInsertInput(text: "second", sourceApp: "B", sourceBundleId: "b"),
            retention: retention
        )

        XCTAssertEqual(try repository.listByRecency(includeSensitive: true).count, 2)
    }

    func testClearHistoryRemovesActiveClips() throws {
        let active = try repository.insertText(
            ClipboardInsertInput(text: "active", sourceApp: "A", sourceBundleId: "a")
        )
        let trashed = try repository.insertText(
            ClipboardInsertInput(text: "trashed", sourceApp: "B", sourceBundleId: "b")
        )
        try repository.softDelete(id: trashed.id)

        try repository.clearHistory()

        XCTAssertNil(try repository.fetch(id: active.id))
        XCTAssertNotNil(try repository.fetch(id: trashed.id))
        XCTAssertEqual(try repository.listByRecency(includeSensitive: true).count, 0)
    }

    func testEmptyTrashPermanentlyDeletesTrashedClips() throws {
        let active = try repository.insertText(
            ClipboardInsertInput(text: "active", sourceApp: "A", sourceBundleId: "a")
        )
        let trashed = try repository.insertText(
            ClipboardInsertInput(text: "trashed", sourceApp: "B", sourceBundleId: "b")
        )
        try repository.softDelete(id: trashed.id)

        try repository.emptyTrash()

        XCTAssertNotNil(try repository.fetch(id: active.id))
        XCTAssertNil(try repository.fetch(id: trashed.id))
        XCTAssertEqual(try repository.list(filter: .trash).count, 0)
    }

    func testRetentionDoesNotCountTrashedItems() throws {
        let retention = RetentionSettings(maxCount: 1, maxAgeDays: 365, infinite: false)

        let trashed = try repository.insertText(
            ClipboardInsertInput(text: "trashed", sourceApp: "A", sourceBundleId: "a"),
            retention: retention
        )
        try repository.softDelete(id: trashed.id)

        _ = try repository.insertText(
            ClipboardInsertInput(text: "active one", sourceApp: "B", sourceBundleId: "b"),
            retention: retention
        )
        let activeTwo = try repository.insertText(
            ClipboardInsertInput(text: "active two", sourceApp: "C", sourceBundleId: "c"),
            retention: retention
        )

        let items = try repository.listByRecency(includeSensitive: true)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, activeTwo.id)
        XCTAssertNotNil(try repository.fetch(id: trashed.id))
    }

    func testInsertImageCreatesAssetAndThumbnail() throws {
        let pngData = try Self.makeTestPNGData(width: 120, height: 90)
        let item = try repository.insertImage(
            ClipboardImageInsertInput(
                imageData: pngData,
                format: .png,
                sourceApp: "Preview",
                sourceBundleId: "com.apple.Preview"
            )
        )

        XCTAssertEqual(item.type, "image")
        XCTAssertEqual(item.preview, "Image 120×90")
        XCTAssertNil(item.contentText)
        XCTAssertEqual(item.sourceApp, "Preview")

        let asset = try XCTUnwrap(try repository.fetchAsset(for: item.id))
        XCTAssertEqual(asset.mimeType, "image/png")
        XCTAssertEqual(asset.width, 120)
        XCTAssertEqual(asset.height, 90)
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.filePath))
        XCTAssertTrue(FileManager.default.fileExists(atPath: asset.thumbnailPath ?? ""))
    }

    func testInsertImageDedupIncrementsCopyCount() throws {
        let pngData = try Self.makeTestPNGData(width: 64, height: 64)
        let first = try repository.insertImage(
            ClipboardImageInsertInput(
                imageData: pngData,
                format: .png,
                sourceApp: "Preview",
                sourceBundleId: "com.apple.Preview"
            )
        )
        let second = try repository.insertImage(
            ClipboardImageInsertInput(
                imageData: pngData,
                format: .png,
                sourceApp: "Safari",
                sourceBundleId: "com.apple.Safari"
            )
        )

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.copyCount, 2)
        XCTAssertEqual(try repository.count(), 1)
    }

    func testListImagesFilterReturnsImageClips() throws {
        _ = try repository.insertText(
            ClipboardInsertInput(text: "plain text", sourceApp: "Notes", sourceBundleId: "com.apple.Notes")
        )
        let image = try repository.insertImage(
            ClipboardImageInsertInput(
                imageData: try Self.makeTestPNGData(width: 40, height: 40),
                format: .png,
                sourceApp: "Preview",
                sourceBundleId: "com.apple.Preview"
            )
        )

        let images = try repository.list(filter: .images)
        XCTAssertEqual(images.count, 1)
        XCTAssertEqual(images[0].id, image.id)
        XCTAssertEqual(images[0].type, "image")
    }

    func testSearchFindsImageBySourceApp() throws {
        _ = try repository.insertImage(
            ClipboardImageInsertInput(
                imageData: try Self.makeTestPNGData(width: 50, height: 50),
                format: .png,
                sourceApp: "Preview",
                sourceBundleId: "com.apple.Preview"
            )
        )

        let results = try repository.search("from:preview")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].type, "image")
    }

    func testInsertFile() throws {
        let item = try repository.insertFile(
            ClipboardFileInsertInput(
                path: "/Users/test/Documents/report.pdf",
                displayName: "report.pdf",
                sourceApp: "Finder",
                sourceBundleId: "com.apple.finder"
            )
        )

        XCTAssertEqual(item.type, "file")
        XCTAssertEqual(item.contentText, "report.pdf — /Users/test/Documents/report.pdf")
        XCTAssertEqual(item.preview, "report.pdf")
        XCTAssertEqual(item.title, "report.pdf")
        XCTAssertEqual(item.sourceApp, "Finder")
        XCTAssertFalse(item.isSensitive)

        let metadata = try dbQueue.read { db in
            try ClipboardItemMetadata
                .filter(ClipboardItemMetadata.Columns.clipboardItemId == item.id)
                .fetchAll(db)
        }
        XCTAssertEqual(metadata.count, 1)
        XCTAssertEqual(metadata[0].key, "file_path")
        XCTAssertEqual(metadata[0].value, "/Users/test/Documents/report.pdf")
    }

    func testFileDedupIncrementsCopyCount() throws {
        let first = try repository.insertFile(
            ClipboardFileInsertInput(
                path: "/tmp/duplicate.txt",
                displayName: "duplicate.txt",
                sourceApp: "Finder",
                sourceBundleId: "com.apple.finder"
            )
        )
        let second = try repository.insertFile(
            ClipboardFileInsertInput(
                path: "/tmp/duplicate.txt",
                displayName: "duplicate.txt",
                sourceApp: "Finder",
                sourceBundleId: "com.apple.finder"
            )
        )

        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.copyCount, 2)
    }

    func testKeywordSearchFindsFileByName() throws {
        _ = try repository.insertFile(
            ClipboardFileInsertInput(
                path: "/Users/test/Desktop/quarterly-report.pdf",
                displayName: "quarterly-report.pdf",
                sourceApp: "Finder",
                sourceBundleId: "com.apple.finder"
            )
        )
        _ = try repository.insertText(
            ClipboardInsertInput(
                text: "unrelated memo",
                sourceApp: "Notes",
                sourceBundleId: "com.apple.Notes"
            )
        )

        let results = try repository.search("quarterly-report")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].type, "file")
    }

    func testFilesFilterListsOnlyFileClips() throws {
        _ = try repository.insertFile(
            ClipboardFileInsertInput(
                path: "/tmp/readme.md",
                displayName: "readme.md",
                sourceApp: "Finder",
                sourceBundleId: "com.apple.finder"
            )
        )
        _ = try repository.insertText(
            ClipboardInsertInput(
                text: "plain text clip",
                sourceApp: "Notes",
                sourceBundleId: "com.apple.Notes"
            )
        )

        let files = try repository.list(filter: .files)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].type, "file")
        XCTAssertEqual(files[0].fileDisplayName, "readme.md")
    }

    private static func makeTestPNGData(width: Int, height: Int) throws -> Data {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw TestImageError.contextCreationFailed
        }

        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard let cgImage = context.makeImage() else {
            throw TestImageError.imageCreationFailed
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw TestImageError.pngEncodingFailed
        }
        return png
    }

    private enum TestImageError: Error {
        case contextCreationFailed
        case imageCreationFailed
        case pngEncodingFailed
    }
}

final class CaptureDenylistTests: XCTestCase {
    func testPasswordManagersAreDenied() {
        XCTAssertTrue(CaptureDenylist.shouldIgnore(bundleID: "com.1password.1password"))
        XCTAssertTrue(CaptureDenylist.shouldIgnore(bundleID: "com.bitwarden.desktop"))
        XCTAssertTrue(CaptureDenylist.shouldIgnore(bundleID: "com.apple.keychainaccess"))
    }

    func testTerminalIsNeverDenied() {
        XCTAssertFalse(CaptureDenylist.shouldIgnore(bundleID: "com.apple.Terminal"))
        XCTAssertFalse(CaptureDenylist.shouldIgnore(bundleID: "com.googlecode.iterm2"))
        XCTAssertFalse(CaptureDenylist.shouldIgnore(bundleID: "dev.warp.Warp-Stable"))
    }

    func testRegularAppsAreNotDenied() {
        XCTAssertFalse(CaptureDenylist.shouldIgnore(bundleID: "com.apple.Safari"))
        XCTAssertFalse(CaptureDenylist.shouldIgnore(bundleID: nil))
    }
}

final class ContentClassifierTests: XCTestCase {
    func testClassifiesURL() {
        XCTAssertEqual(ContentClassifier.classify("https://example.com"), "url")
    }

    func testClassifiesCode() {
        XCTAssertEqual(
            ContentClassifier.classify("func main() {\n    print(\"hi\")\n}"),
            "code"
        )
    }

    func testDefaultsToText() {
        XCTAssertEqual(ContentClassifier.classify("hello world"), "text")
    }
}

final class SensitiveDetectorTests: XCTestCase {
    func testDetectsCommonPatterns() {
        XCTAssertTrue(SensitiveDetector.isSensitive("sk-abcdefghijklmnopqrstuvwxyz"))
        XCTAssertTrue(SensitiveDetector.isSensitive("ghp_abcdefghijklmnopqrstuvwxyz"))
        XCTAssertTrue(SensitiveDetector.isSensitive("-----BEGIN PRIVATE KEY-----"))
        XCTAssertTrue(
            SensitiveDetector.isSensitive(
                "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signature"
            )
        )
        XCTAssertFalse(SensitiveDetector.isSensitive("hello world"))
    }
}
