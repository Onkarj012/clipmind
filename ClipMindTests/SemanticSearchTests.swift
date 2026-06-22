import GRDB
import NaturalLanguage
import XCTest
@testable import ClipMind

final class VectorMathTests: XCTestCase {
    func testEncodeDecodeRoundTrip() {
        let vector: [Float] = [1, 2, 3, 4.5]
        let decoded = VectorMath.decode(VectorMath.encode(vector))
        XCTAssertEqual(decoded, vector)
    }

    func testCosineSimilarityIdenticalVectors() {
        let vector: [Float] = [1, 0, 0]
        XCTAssertEqual(VectorMath.cosineSimilarity(vector, vector), 1, accuracy: 0.0001)
    }

    func testCosineSimilarityOrthogonalVectors() {
        XCTAssertEqual(
            VectorMath.cosineSimilarity([1, 0, 0], [0, 1, 0]),
            0,
            accuracy: 0.0001
        )
    }
}

final class SemanticSearchTests: XCTestCase {
    func testQualifiesForSemanticSearchRequiresMoreThanThreeWords() {
        var parsed = ClipboardRepository.parseSearchQuery("react hydration bug")
        XCTAssertFalse(parsed.qualifiesForSemanticSearch)

        parsed = ClipboardRepository.parseSearchQuery("react hydration bug missing")
        XCTAssertTrue(parsed.qualifiesForSemanticSearch)
    }

    func testTypePrefixDisablesSemanticSearch() {
        let parsed = ClipboardRepository.parseSearchQuery("type:code react hydration bug missing")
        XCTAssertFalse(parsed.qualifiesForSemanticSearch)
    }

    func testFromPrefixDisablesSemanticSearch() {
        let parsed = ClipboardRepository.parseSearchQuery("from:vscode react hydration bug missing")
        XCTAssertFalse(parsed.qualifiesForSemanticSearch)
    }

    func testMergeHybridResultsPrefersItemsInBothLists() {
        let fts = [
            ScoredItemID(itemID: "a", score: 1),
            ScoredItemID(itemID: "b", score: 0.5),
        ]
        let semantic = [
            ScoredItemID(itemID: "b", score: 0.9),
            ScoredItemID(itemID: "c", score: 0.8),
        ]

        let merged = SemanticSearchService.mergeHybridResults(
            ftsRanked: fts,
            semanticRanked: semantic,
            limit: 3
        )

        XCTAssertEqual(merged.first, "b")
        XCTAssertEqual(Set(merged), Set(["a", "b", "c"]))
    }

    func testSemanticRankOrdersBySimilarity() {
        let query: [Float] = [1, 0, 0]
        let ranked = SemanticSearchService.rank(
            queryEmbedding: query,
            candidates: [
                ("orthogonal", [0, 1, 0]),
                ("closest", [0.9, 0.1, 0]),
                ("opposite", [-1, 0, 0]),
            ]
        )

        XCTAssertEqual(ranked[0].itemID, "closest")
        XCTAssertGreaterThan(ranked[0].score, ranked[1].score)
    }
}

final class EmbeddingRepositoryTests: XCTestCase {
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

    func testUpsertAndFetchEmbedding() throws {
        let item = try repository.insertText(
            ClipboardInsertInput(text: "long enough text for embedding", sourceApp: "A", sourceBundleId: "a")
        )

        try repository.upsertEmbedding(itemID: item.id, model: "test-model", vector: [1, 0, 0])

        let embedding = try XCTUnwrap(try repository.fetchEmbedding(for: item.id))
        XCTAssertEqual(embedding.model, "test-model")
        XCTAssertEqual(VectorMath.decode(embedding.vector), [1, 0, 0])
    }

    func testHybridSearchUsesSemanticResults() throws {
        let stackTrace = try repository.insertText(
            ClipboardInsertInput(
                text: """
                Error: Cannot read properties of undefined (reading 'props')
                    at HydrationBoundary (react-dom.js:102:11)
                """,
                sourceApp: "VS Code",
                sourceBundleId: "com.microsoft.VSCode"
            )
        )
        _ = try repository.insertText(
            ClipboardInsertInput(
                text: "buy milk and eggs from the store",
                sourceApp: "Notes",
                sourceBundleId: "com.apple.Notes"
            )
        )

        try repository.upsertEmbedding(
            itemID: stackTrace.id,
            model: "test",
            vector: [0.92, 0.12, 0.05]
        )

        let queryEmbedding: [Float] = [0.9, 0.15, 0.02]
        let results = try repository.search(
            "react hydration bug missing props",
            limit: 5,
            queryEmbedding: queryEmbedding,
            embeddingModel: "test"
        )

        XCTAssertEqual(results.first?.id, stackTrace.id)
    }
}

final class EmbeddingGeneratorTests: XCTestCase {
    func testSkipsTinyClips() {
        let generator = EmbeddingGenerator.make(settings: .defaults)
        XCTAssertFalse(generator.shouldEmbed(text: "short"))
        XCTAssertTrue(generator.shouldEmbed(text: "this clip is long enough to embed"))
    }

    func testDefaultBackendIsApple() {
        XCTAssertEqual(SemanticSearchSettings.defaults.backend, .apple)
        XCTAssertEqual(
            EmbeddingGenerator.make(settings: .defaults).modelIdentifier,
            AppleEmbeddingProvider.modelIdentifier
        )
    }

    func testOllamaBackendUsesConfiguredModel() {
        var settings = SemanticSearchSettings.defaults
        settings.backend = .ollama
        settings.ollamaEmbeddingModel = "bge-small-en"

        XCTAssertEqual(
            EmbeddingGenerator.make(settings: settings).modelIdentifier,
            "bge-small-en"
        )
    }

    func testRemoteOllamaEmbeddingURLFallsBackToLocalhost() {
        var settings = SemanticSearchSettings.defaults
        settings.backend = .ollama
        settings.ollamaBaseURL = "http://remote.example.test:11434"

        XCTAssertEqual(EmbeddingGenerator.make(settings: settings).modelIdentifier, settings.ollamaEmbeddingModel)
        XCTAssertEqual(settings.ollamaURL.host, "localhost")
    }
}

final class AppleEmbeddingProviderTests: XCTestCase {
    func testEmbedsSentenceWhenAssetsAvailable() async throws {
        guard NLContextualEmbedding(language: .english)?.hasAvailableAssets == true else {
            throw XCTSkip("NLContextualEmbedding assets are not available in this environment")
        }

        let provider = AppleEmbeddingProvider()
        let vector = try await provider.embed(
            text: "react hydration error missing props in component tree"
        )

        XCTAssertFalse(vector.isEmpty)
        XCTAssertGreaterThan(vector.count, 32)
    }
}
