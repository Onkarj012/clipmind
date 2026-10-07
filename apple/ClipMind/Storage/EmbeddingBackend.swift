import Foundation

enum EmbeddingBackend: String, CaseIterable, Sendable, Identifiable {
    case apple
    case ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple:
            "Apple (on-device)"
        case .ollama:
            "Ollama"
        }
    }
}
