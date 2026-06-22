import Foundation

struct SemanticSearchSettings: Equatable, Sendable {
    var isEnabled: Bool
    var backend: EmbeddingBackend
    var ollamaBaseURL: String
    var ollamaEmbeddingModel: String

    static let defaults = SemanticSearchSettings(
        isEnabled: true,
        backend: .apple,
        ollamaBaseURL: "http://localhost:11434",
        ollamaEmbeddingModel: EmbeddingGenerator.defaultOllamaModel
    )

    var ollamaURL: URL {
        OllamaEndpointPolicy.localURL(from: ollamaBaseURL)
    }

    var embeddingModelIdentifier: String {
        switch backend {
        case .apple:
            AppleEmbeddingProvider.modelIdentifier
        case .ollama:
            ollamaEmbeddingModel
        }
    }
}
