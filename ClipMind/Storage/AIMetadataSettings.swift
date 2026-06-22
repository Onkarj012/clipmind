import Foundation

struct AIMetadataSettings: Equatable, Sendable {
    var isEnabled: Bool
    var groqModel: String
    var ollamaBaseURL: String
    var ollamaChatModel: String
    var hasGroqKey: Bool

    static let defaults = AIMetadataSettings(
        isEnabled: true,
        groqModel: GroqChatProvider.defaultModel,
        ollamaBaseURL: "http://localhost:11434",
        ollamaChatModel: "llama3.2:3b",
        hasGroqKey: false
    )

    var ollamaURL: URL {
        OllamaEndpointPolicy.localURL(from: ollamaBaseURL)
    }
}

enum OllamaEndpointPolicy {
    private static let defaultURL = URL(string: "http://localhost:11434")!

    static func localURL(from value: String) -> URL {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              url.user == nil,
              url.password == nil,
              let host = url.host?.lowercased(),
              isLoopback(host: host)
        else {
            return defaultURL
        }
        return url
    }

    private static func isLoopback(host: String) -> Bool {
        host == "localhost" || host == "127.0.0.1" || host == "::1"
    }
}
