import Foundation
import NaturalLanguage

enum AppleEmbeddingError: Error, Equatable {
    case modelUnavailable
    case assetsUnavailable
    case embeddingFailed
}

struct AppleEmbeddingProvider: Sendable {
    static let modelIdentifier = "apple-nl-contextual-en"

    private static let queue = DispatchQueue(label: "io.clipmind.apple-embedding")

    var modelIdentifier: String { Self.modelIdentifier }

    func embed(text: String) async throws -> [Float] {
        try await withCheckedThrowingContinuation { continuation in
            Self.queue.async {
                do {
                    continuation.resume(returning: try Self.embedSync(text: text))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func embedSync(text: String) throws -> [Float] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw AppleEmbeddingError.embeddingFailed
        }

        guard let embedding = NLContextualEmbedding(language: .english) else {
            throw AppleEmbeddingError.modelUnavailable
        }

        if !embedding.hasAvailableAssets {
            try requestAssets(for: embedding)
        }

        try embedding.load()
        defer { embedding.unload() }

        let result = try embedding.embeddingResult(for: trimmed, language: .english)

        var sum: [Double] = []
        var tokenCount = 0

        result.enumerateTokenVectors(in: trimmed.startIndex..<trimmed.endIndex) { vector, _ in
            if sum.isEmpty {
                sum = Array(repeating: 0, count: vector.count)
            }
            for index in vector.indices {
                sum[index] += vector[index]
            }
            tokenCount += 1
            return true
        }

        guard tokenCount > 0 else {
            throw AppleEmbeddingError.embeddingFailed
        }

        return sum.map { Float($0 / Double(tokenCount)) }
    }

    private static func requestAssets(for embedding: NLContextualEmbedding) throws {
        let semaphore = DispatchSemaphore(value: 0)
        var requestError: Error?

        embedding.requestAssets { result, error in
            if let error {
                requestError = error
            } else if result != .available {
                requestError = AppleEmbeddingError.assetsUnavailable
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let requestError {
            throw requestError
        }
    }
}
