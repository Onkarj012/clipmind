import Foundation

protocol LLMProvider: Sendable {
    func complete(prompt: String) async throws -> String
}

enum LLMProviderError: Error, Equatable {
    case unavailable
}
