import GRDB
import XCTest
@testable import ClipMind

final class AIMetadataServiceTests: XCTestCase {
    func testSkipsTinyClips() {
        XCTAssertFalse(AIMetadataService.shouldProcess(text: "short", type: "text"))
        XCTAssertTrue(AIMetadataService.shouldProcess(text: String(repeating: "a", count: 60), type: "text"))
    }

    func testRulesBasedMetadataForShortClip() {
        let text = """
        Error: Cannot read properties of undefined (reading 'props')
            at HydrationBoundary (react-dom.js:102:11)
        """
        let metadata = AIMetadataService.generateRulesFirst(text: text, type: "code")

        XCTAssertNotNil(metadata)
        XCTAssertTrue(metadata?.title?.contains("Error") == true)
        XCTAssertTrue(metadata?.tags.contains("error") == true)
    }

    func testRulesBasedMetadataForLongClipUsesSummary() {
        let text = String(repeating: "This is a long clipboard note about project planning. ", count: 8)
        let metadata = AIMetadataService.rulesBasedMetadata(text: text, type: "text")

        XCTAssertNotNil(metadata.title)
        XCTAssertNotNil(metadata.summary)
    }

    func testInferTagsForCodeError() {
        let metadata = AIMetadataService.rulesBasedMetadata(
            text: "Traceback (most recent call last):\nValueError: invalid literal",
            type: "code"
        )
        XCTAssertTrue(metadata.tags.contains("error"))
        XCTAssertTrue(metadata.tags.contains("code"))
    }

    func testParseLLMResponseFromFakeProviderJSON() async throws {
        struct FakeProvider: LLMProvider {
            let response: String
            func complete(prompt: String) async throws -> String { response }
        }

        let json = """
        {"title":"Test title","summary":"A short summary.","tags":["swift","code"]}
        """
        let provider = FakeProvider(response: json)
        let text = String(repeating: "Long clipboard content for LLM metadata generation. ", count: 10)
        let metadata = try await AIMetadataService.generateWithLLM(
            text: text,
            type: "code",
            provider: provider
        )

        XCTAssertEqual(metadata?.title, "Test title")
        XCTAssertEqual(metadata?.summary, "A short summary.")
        XCTAssertEqual(metadata?.tags, ["swift", "code"])
    }

    func testGenerateWithLLMFallsBackToRulesWhenProviderFails() async throws {
        struct FailingProvider: LLMProvider {
            func complete(prompt: String) async throws -> String {
                throw LLMProviderError.unavailable
            }
        }

        let text = String(repeating: "Error in production deployment logs. ", count: 10)
        let metadata = try await AIMetadataService.generateWithLLM(
            text: text,
            type: "text",
            provider: FailingProvider()
        )

        XCTAssertNotNil(metadata?.title)
        XCTAssertNotNil(metadata?.summary)
    }
}

final class LLMProviderChainTests: XCTestCase {
    func testOllamaProviderRejectsRemoteEndpointBeforeSendingContent() async {
        let provider = OllamaChatProvider(
            baseURL: URL(string: "https://example.com")!,
            model: "test"
        )

        do {
            _ = try await provider.complete(prompt: "clipboard content")
            XCTFail("Expected local endpoint validation error")
        } catch {
            XCTAssertEqual(error as? OllamaChatError, .nonLoopbackURL)
        }
    }

    func testChainPrefersFirstProvider() async throws {
        struct RecordingProvider: LLMProvider {
            let name: String
            let response: String
            static let lock = NSLock()
            static var calls: [String] = []

            func complete(prompt: String) async throws -> String {
                Self.lock.lock()
                Self.calls.append(name)
                Self.lock.unlock()
                if name == "groq" { return response }
                throw GroqChatError.httpError(statusCode: 503)
            }
        }

        RecordingProvider.calls = []
        let chain = LLMProviderChain(providers: [
            RecordingProvider(name: "groq", response: "groq-result"),
            RecordingProvider(name: "ollama", response: "ollama-result"),
        ])

        let result = try await chain.complete(prompt: "hi")
        XCTAssertEqual(result, "groq-result")
        XCTAssertEqual(RecordingProvider.calls, ["groq"])
    }

    func testChainFallsBackToSecondProvider() async throws {
        struct RecordingProvider: LLMProvider {
            let name: String
            let response: String

            func complete(prompt: String) async throws -> String {
                if name == "groq" { throw GroqChatError.httpError(statusCode: 401) }
                return response
            }
        }

        let chain = LLMProviderChain(providers: [
            RecordingProvider(name: "groq", response: "groq-result"),
            RecordingProvider(name: "ollama", response: "ollama-result"),
        ])

        let result = try await chain.complete(prompt: "hi")
        XCTAssertEqual(result, "ollama-result")
    }

    func testChainThrowsWhenAllProvidersFail() async {
        struct FailingProvider: LLMProvider {
            func complete(prompt: String) async throws -> String {
                throw LLMProviderError.unavailable
            }
        }

        let chain = LLMProviderChain(providers: [FailingProvider(), FailingProvider()])

        do {
            _ = try await chain.complete(prompt: "hi")
            XCTFail("Expected error")
        } catch {
            XCTAssertTrue(error is LLMProviderError)
        }
    }
}

final class KeychainSecretsStoreTests: XCTestCase {
    func testInMemorySecretsRoundTrip() throws {
        let store = InMemorySecretsStore()
        try store.write(key: .groqAPIKey, value: "gsk_test_key")
        XCTAssertEqual(try store.read(key: .groqAPIKey), "gsk_test_key")
        try store.delete(key: .groqAPIKey)
        XCTAssertNil(try store.read(key: .groqAPIKey))
    }
}

final class AIMetadataSettingsTests: XCTestCase {
    func testRemoteOllamaURLFallsBackToLocalhost() {
        var settings = AIMetadataSettings.defaults
        settings.ollamaBaseURL = "https://example.com:11434"

        XCTAssertEqual(settings.ollamaURL.host, "localhost")
        XCTAssertEqual(settings.ollamaURL.port, 11434)
    }

    func testLoopbackOllamaURLIsPreserved() {
        var settings = AIMetadataSettings.defaults
        settings.ollamaBaseURL = "http://127.0.0.1:11435"

        XCTAssertEqual(settings.ollamaURL.host, "127.0.0.1")
        XCTAssertEqual(settings.ollamaURL.port, 11435)
    }
}

final class TagSearchTests: XCTestCase {
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

    func testTagPrefixParsing() {
        let parsed = ClipboardRepository.parseSearchQuery("tag:error react bug")
        XCTAssertEqual(parsed.tagFilter, "error")
        XCTAssertEqual(parsed.keywords, "react bug")
        XCTAssertFalse(parsed.qualifiesForSemanticSearch)
    }

    func testTagFilterSearch() throws {
        let item = try repository.insertText(
            ClipboardInsertInput(
                text: "Error: hydration failed because props were missing in the component tree.",
                sourceApp: "VS Code",
                sourceBundleId: "com.microsoft.VSCode"
            )
        )

        try repository.applyAIMetadata(
            itemID: item.id,
            metadata: ClipAIMetadata(
                title: "Hydration error",
                summary: "Missing props during hydration.",
                tags: ["error", "react"]
            )
        )

        let results = try repository.search("tag:error", limit: 10)
        XCTAssertEqual(results.first?.id, item.id)

        let noMatch = try repository.search("tag:shopping", limit: 10)
        XCTAssertTrue(noMatch.isEmpty)
    }

    func testApplyAIMetadataPersistsTitleSummaryAndTags() throws {
        let item = try repository.insertText(
            ClipboardInsertInput(
                text: String(repeating: "Planning notes for the sprint review and backlog grooming. ", count: 4),
                sourceApp: "Notes",
                sourceBundleId: "com.apple.Notes"
            )
        )

        try repository.applyAIMetadata(
            itemID: item.id,
            metadata: ClipAIMetadata(
                title: "Sprint planning",
                summary: "Notes for sprint review.",
                tags: ["planning"]
            )
        )

        let updated = try XCTUnwrap(try repository.fetch(id: item.id))
        XCTAssertEqual(updated.title, "Sprint planning")
        XCTAssertEqual(updated.summary, "Notes for sprint review.")

        let tags = try repository.fetchTags(for: item.id)
        XCTAssertEqual(tags.map(\.name), ["planning"])
    }
}

final class SimilarClipsTests: XCTestCase {
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

    func testFetchSimilarItemsExcludesSelf() throws {
        let primary = try repository.insertText(
            ClipboardInsertInput(
                text: "react hydration error missing props in component tree",
                sourceApp: "A",
                sourceBundleId: "a"
            )
        )
        let similar = try repository.insertText(
            ClipboardInsertInput(
                text: "hydration boundary failed because props were undefined",
                sourceApp: "A",
                sourceBundleId: "a"
            )
        )
        let unrelated = try repository.insertText(
            ClipboardInsertInput(text: "buy groceries and milk", sourceApp: "B", sourceBundleId: "b")
        )

        try repository.upsertEmbedding(itemID: primary.id, model: "test", vector: [1, 0, 0])
        try repository.upsertEmbedding(itemID: similar.id, model: "test", vector: [0.95, 0.1, 0])
        try repository.upsertEmbedding(itemID: unrelated.id, model: "test", vector: [0, 1, 0])

        let results = try repository.fetchSimilarItems(for: primary.id, embeddingModel: "test", limit: 5)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, similar.id)
    }
}
