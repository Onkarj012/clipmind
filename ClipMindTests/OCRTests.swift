import GRDB
import XCTest
@testable import ClipMind

final class OCRTests: XCTestCase {
    private var dbQueue: DatabaseQueue!
    private var repository: ClipboardRepository!

    override func setUpWithError() throws {
        dbQueue = try DatabaseManager.openInMemoryQueue()
        repository = ClipboardRepository(dbWriter: dbQueue)
    }

    override func tearDownWithError() throws {
        repository = nil
        dbQueue = nil
    }

    func testApplyOCRTextPersistsAndIsSearchable() throws {
        let item = try repository.insertText(
            ClipboardInsertInput(
                text: "placeholder",
                sourceApp: "Test",
                sourceBundleId: "test"
            )
        )

        try dbQueue.write { db in
            var updated = try XCTUnwrap(try ClipboardItem.fetchOne(db, key: item.id))
            updated.type = "image"
            updated.contentText = nil
            try updated.update(db)

            try ClipboardAsset(
                itemId: item.id,
                filePath: "/tmp/test.png",
                thumbnailPath: nil,
                mimeType: "image/png",
                width: 100,
                height: 50,
                ocrText: nil
            ).insert(db)
        }

        let ocrText = "TypeError: undefined is not a function"
        let updatedItem = try repository.applyOCRText(itemID: item.id, text: ocrText)

        XCTAssertEqual(updatedItem.contentText, ocrText)

        let asset = try XCTUnwrap(try repository.fetchAsset(for: item.id))
        XCTAssertEqual(asset.ocrText, ocrText)

        let results = try repository.search("TypeError undefined function", limit: 10)
        XCTAssertEqual(results.first?.id, item.id)
    }

    func testOCRIndexerDoesNotWriteWhenDisabled() throws {
        let item = try repository.insertText(
            ClipboardInsertInput(text: "x", sourceApp: "Test", sourceBundleId: "test")
        )

        try dbQueue.write { db in
            var updated = try XCTUnwrap(try ClipboardItem.fetchOne(db, key: item.id))
            updated.type = "image"
            updated.contentText = nil
            try updated.update(db)

            try ClipboardAsset(
                itemId: item.id,
                filePath: "/tmp/test.png",
                thumbnailPath: nil,
                mimeType: "image/png",
                width: 10,
                height: 10,
                ocrText: nil
            ).insert(db)
        }

        let indexer = OCRIndexer(repository: repository)
        indexer.settingsProvider = { OCRSettings(isEnabled: false) }
        indexer.ocrTextProvider = { _ in
            XCTFail("OCR should not run when disabled")
            return "should-not-run"
        }
        indexer.enqueue(item: try XCTUnwrap(try repository.fetch(id: item.id)))

        let asset = try XCTUnwrap(try repository.fetchAsset(for: item.id))
        XCTAssertNil(asset.ocrText)
    }
}
