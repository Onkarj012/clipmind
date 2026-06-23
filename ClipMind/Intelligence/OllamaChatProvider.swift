import Foundation

enum OllamaChatError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case nonLoopbackURL
    case httpError(statusCode: Int)
    case emptyResponse
}

struct OllamaChatProvider: LLMProvider, Sendable {
    let baseURL: URL
    let model: String
    let session: URLSession

    init(baseURL: URL, model: String, session: URLSession = AIServiceNetwork.makeSession()) {
        self.baseURL = baseURL
        self.model = model
        self.session = session
    }

    func complete(prompt: String) async throws -> String {
        guard let host = baseURL.host?.lowercased(), OllamaEndpointPolicy.isLoopback(host: host) else {
            throw OllamaChatError.nonLoopbackURL
        }
        guard let url = URL(string: "api/generate", relativeTo: baseURL) else {
            throw OllamaChatError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            GenerateRequest(model: model, prompt: prompt, stream: false)
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OllamaChatError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw OllamaChatError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
        let trimmed = decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw OllamaChatError.emptyResponse
        }
        return trimmed
    }

    private struct GenerateRequest: Encodable {
        let model: String
        let prompt: String
        let stream: Bool
    }

    private struct GenerateResponse: Decodable {
        let response: String
    }
}
