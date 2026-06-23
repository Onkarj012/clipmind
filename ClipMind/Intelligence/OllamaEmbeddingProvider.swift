import Foundation

enum OllamaEmbeddingError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case nonLoopbackURL
    case httpError(statusCode: Int)
    case emptyEmbedding
}

struct OllamaEmbeddingProvider: Sendable {
    let baseURL: URL
    let model: String
    let session: URLSession

    init(baseURL: URL, model: String, session: URLSession = AIServiceNetwork.makeSession()) {
        self.baseURL = baseURL
        self.model = model
        self.session = session
    }

    func embed(text: String) async throws -> [Float] {
        guard let host = baseURL.host?.lowercased(), OllamaEndpointPolicy.isLoopback(host: host) else {
            throw OllamaEmbeddingError.nonLoopbackURL
        }
        guard let url = URL(string: "api/embeddings", relativeTo: baseURL) else {
            throw OllamaEmbeddingError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(EmbeddingRequest(model: model, prompt: text))

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaEmbeddingError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw OllamaEmbeddingError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(EmbeddingResponse.self, from: data)
        guard !decoded.embedding.isEmpty else {
            throw OllamaEmbeddingError.emptyEmbedding
        }
        return decoded.embedding
    }

    private struct EmbeddingRequest: Encodable {
        let model: String
        let prompt: String
    }

    private struct EmbeddingResponse: Decodable {
        let embedding: [Float]
    }
}
