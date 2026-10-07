import Foundation

struct ClipAIMetadata: Equatable, Sendable {
    var title: String?
    var summary: String?
    var tags: [String]
}

enum AIMetadataService {
    static let minimumTextLength = 50
    static let llmThresholdLength = 200
    static let maxTitleLength = 80
    static let maxSummaryLength = 280
    static let maxTags = 5

    static func shouldProcess(text: String, type: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumTextLength else { return false }
        return type == "text" || type == "code"
    }

    static func generateRulesFirst(text: String, type: String) -> ClipAIMetadata? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard shouldProcess(text: trimmed, type: type) else { return nil }

        if trimmed.count < llmThresholdLength {
            return rulesBasedMetadata(text: trimmed, type: type)
        }
        return nil
    }

    static func generateWithLLM(
        text: String,
        type: String,
        provider: any LLMProvider
    ) async throws -> ClipAIMetadata? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard shouldProcess(text: trimmed, type: type) else { return nil }

        if trimmed.count < llmThresholdLength {
            return rulesBasedMetadata(text: trimmed, type: type)
        }

        let prompt = llmPrompt(for: trimmed, type: type)
        do {
            let response = try await provider.complete(prompt: prompt)
            if let parsed = parseLLMResponse(response) {
                return parsed
            }
        } catch {
            return rulesBasedMetadata(text: trimmed, type: type)
        }
        return rulesBasedMetadata(text: trimmed, type: type)
    }

    static func rulesBasedMetadata(text: String, type: String) -> ClipAIMetadata {
        let title = inferTitle(from: text, type: type)
        let summary = text.count >= llmThresholdLength
            ? inferSummary(from: text)
            : nil
        let tags = inferTags(from: text, type: type)
        return ClipAIMetadata(title: title, summary: summary, tags: tags)
    }

    private static func inferTitle(from text: String, type: String) -> String? {
        if let errorTitle = inferErrorTitle(from: text) {
            return truncate(errorTitle, maxLength: maxTitleLength)
        }

        let firstLine = text
            .components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let firstLine, !firstLine.isEmpty else { return nil }

        if type == "code", firstLine.count > maxTitleLength {
            return truncate(firstLine, maxLength: maxTitleLength)
        }

        if firstLine.count <= maxTitleLength {
            return firstLine
        }

        return truncate(firstLine, maxLength: maxTitleLength)
    }

    private static func inferErrorTitle(from text: String) -> String? {
        let patterns = [
            #"(?m)^(?:Error|Exception|TypeError|ReferenceError|SyntaxError)[:\s].+$"#,
            #"(?m)^\s*at\s+\w+"#,
        ]

        for pattern in patterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let line = String(text[range])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !line.isEmpty {
                    return line
                }
            }
        }
        return nil
    }

    private static func inferSummary(from text: String) -> String? {
        let collapsed = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard collapsed.count > maxTitleLength else { return nil }
        return truncate(collapsed, maxLength: maxSummaryLength)
    }

    private static func inferTags(from text: String, type: String) -> [String] {
        var tags: [String] = []

        switch type {
        case "code":
            tags.append("code")
            if text.contains("Error") || text.contains("Traceback") {
                tags.append("error")
            }
            if text.contains("import ") || text.contains("func ") || text.contains("def ") {
                tags.append("snippet")
            }
        case "text":
            tags.append("text")
            if text.contains("http://") || text.contains("https://") {
                tags.append("links")
            }
        default:
            break
        }

        if text.localizedCaseInsensitiveContains("TODO") {
            tags.append("tasks")
        }

        return Array(Set(tags)).prefix(maxTags).map { $0 }
    }

    private static func llmPrompt(for text: String, type: String) -> String {
        let clipped = String(text.prefix(4_000))
        return """
        You analyze clipboard snippets. Return ONLY valid JSON with keys title, summary, tags.
        title: short headline (max 80 chars)
        summary: one sentence (max 280 chars)
        tags: array of 1-5 lowercase single-word tags

        Type: \(type)
        Content:
        \(clipped)
        """
    }

    static func parseLLMResponse(_ response: String) -> ClipAIMetadata? {
        let jsonText = extractJSONObject(from: response)
        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONDecoder().decode(LLMMetadataResponse.self, from: data)
        else {
            return nil
        }

        let title = object.title?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            .map { truncate($0, maxLength: maxTitleLength) }

        let summary = object.summary?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
            .map { truncate($0, maxLength: maxSummaryLength) }

        let tags = (object.tags ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && !$0.contains(" ") }
            .prefix(maxTags)
            .map { $0 }

        guard title != nil || summary != nil || !tags.isEmpty else {
            return nil
        }

        return ClipAIMetadata(title: title, summary: summary, tags: Array(tags))
    }

    private static func extractJSONObject(from text: String) -> String {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}")
        else {
            return text
        }
        return String(text[start...end])
    }

    private static func truncate(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        let endIndex = text.index(text.startIndex, offsetBy: maxLength - 1)
        return String(text[..<endIndex]) + "…"
    }

    private struct LLMMetadataResponse: Decodable {
        let title: String?
        let summary: String?
        let tags: [String]?
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
