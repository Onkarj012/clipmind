import Foundation

enum AIServiceNetwork {
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }
}

enum GroqChatError: Error, Equatable {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case emptyResponse
}

struct GroqChatProvider: LLMProvider, Sendable {
    static let defaultModel = "llama-3.3-70b-versatile"
    static let apiBaseURL = URL(string: "https://api.groq.com/openai/v1")!

    let apiKey: String
    let model: String
    let session: URLSession

    init(apiKey: String, model: String = defaultModel, session: URLSession = AIServiceNetwork.makeSession()) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    func complete(prompt: String) async throws -> String {
        guard let url = URL(string: "chat/completions", relativeTo: Self.apiBaseURL) else {
            throw GroqChatError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            ChatRequest(
                model: model,
                messages: [ChatMessage(role: "user", content: prompt)],
                stream: false
            )
        )

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GroqChatError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw GroqChatError.httpError(statusCode: httpResponse.statusCode)
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !content.isEmpty
        else {
            throw GroqChatError.emptyResponse
        }
        return content
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let stream: Bool
    }

    private struct ChatMessage: Encodable {
        let role: String
        let content: String
    }

    private struct ChatResponse: Decodable {
        let choices: [Choice]

        struct Choice: Decodable {
            let message: Message
        }

        struct Message: Decodable {
            let content: String?
        }
    }
}
