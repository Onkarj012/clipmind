import Foundation

struct EmbeddingGenerator: Sendable {
    static let minimumTextLength = 20
    static let defaultOllamaModel = "nomic-embed-text"

    enum Backend: Sendable {
        case apple(AppleEmbeddingProvider)
        case ollama(OllamaEmbeddingProvider)
    }

    let backend: Backend

    var modelIdentifier: String {
        switch backend {
        case .apple(let provider):
            provider.modelIdentifier
        case .ollama(let provider):
            provider.model
        }
    }

    static func make(settings: SemanticSearchSettings) -> EmbeddingGenerator {
        switch settings.backend {
        case .apple:
            EmbeddingGenerator(backend: .apple(AppleEmbeddingProvider()))
        case .ollama:
            EmbeddingGenerator(
                backend: .ollama(
                    OllamaEmbeddingProvider(
                        baseURL: settings.ollamaURL,
                        model: settings.ollamaEmbeddingModel
                    )
                )
            )
        }
    }

    func shouldEmbed(text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= Self.minimumTextLength
    }

    func generateEmbedding(for text: String) async throws -> [Float] {
        switch backend {
        case .apple(let provider):
            try await provider.embed(text: text)
        case .ollama(let provider):
            try await provider.embed(text: text)
        }
    }
}
