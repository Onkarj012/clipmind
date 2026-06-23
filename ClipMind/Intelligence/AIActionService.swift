import Foundation

enum AIClipAction: String, CaseIterable, Identifiable, Hashable, Sendable {
    case summarize
    case shorter
    case explain
    case formatJSON
    case bulletPoints
    case extractLinks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .summarize: return "Summarize"
        case .shorter: return "Make Shorter"
        case .explain: return "Explain"
        case .formatJSON: return "Format JSON"
        case .bulletPoints: return "Bullet Points"
        case .extractLinks: return "Extract Links"
        }
    }

    var systemImage: String {
        switch self {
        case .summarize: return "text.alignleft"
        case .shorter: return "arrow.down.right.and.arrow.up.left"
        case .explain: return "questionmark.circle"
        case .formatJSON: return "curlybraces"
        case .bulletPoints: return "list.bullet"
        case .extractLinks: return "link"
        }
    }
}

enum AIActionError: Error, Equatable {
    case emptyInput
    case providerUnavailable
    case invalidJSONOutput
}

enum AIActionService {
    static func run(
        action: AIClipAction,
        text: String,
        provider: any LLMProvider
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIActionError.emptyInput }

        let prompt = prompt(for: action, text: trimmed)
        let response = try await provider.complete(prompt: prompt)
        let result = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { throw AIActionError.providerUnavailable }

        if action == .formatJSON {
            guard let json = normalizedJSON(result) else { throw AIActionError.invalidJSONOutput }
            return json
        }

        return result
    }

    static func prompt(for action: AIClipAction, text: String) -> String {
        let clipped = String(text.prefix(12_000))
        switch action {
        case .summarize:
            return """
            Summarize the following clipboard content in 1-3 concise sentences.
            Return only the summary, no preamble.

            \(clipped)
            """
        case .shorter:
            return """
            Condense the following text while preserving the essential meaning.
            Return only the shortened text.

            \(clipped)
            """
        case .explain:
            return """
            Explain the following content in plain language for a developer.
            If it contains code or errors, clarify what it means and likely causes.
            Return only the explanation.

            \(clipped)
            """
        case .formatJSON:
            return """
            Format the following content as valid, pretty-printed JSON.
            Fix minor syntax issues if needed.
            Return only valid JSON with no markdown fences or commentary.

            \(clipped)
            """
        case .bulletPoints:
            return """
            Extract the key points from the following content as a Markdown bullet list.
            Return only the bullet list.

            \(clipped)
            """
        case .extractLinks:
            return """
            List every URL found in the following content, one per line.
            Return only URLs, no numbering or extra text.

            \(clipped)
            """
        }
    }

    static func isValidJSON(_ text: String) -> Bool {
        normalizedJSON(text) != nil
    }

    private static func normalizedJSON(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidates = [trimmed, extractDelimitedJSON(from: trimmed)].compactMap { $0 }
        for candidate in candidates {
            guard let data = candidate.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  JSONSerialization.isValidJSONObject(object),
                  let normalized = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
                  let string = String(data: normalized, encoding: .utf8)
            else { continue }
            return string
        }
        return nil
    }

    private static func extractDelimitedJSON(from text: String) -> String? {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
        let closing: Character = text[start] == "{" ? "}" : "]"
        guard let end = text[start...].lastIndex(of: closing) else { return nil }
        return String(text[start...end])
    }
}
