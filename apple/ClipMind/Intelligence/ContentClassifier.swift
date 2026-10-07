import Foundation

enum ContentClassifier {
    static func classify(_ text: String) -> String {
        if isURL(text) {
            return "url"
        }
        if isCodeLike(text) {
            return "code"
        }
        return "text"
    }

    private static func isURL(_ text: String) -> Bool {
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased()
        else {
            return false
        }

        switch scheme {
        case "http", "https", "ftp":
            return url.host != nil
        case "mailto":
            return url.user != nil || url.host != nil
        default:
            return false
        }
    }

    private static func isCodeLike(_ text: String) -> Bool {
        if text.contains("{"), text.contains("}") {
            return true
        }

        let patterns = [
            #"\bimport\s+\w+"#,
            #"(?m)^\s*def\s+\w+"#,
            #"(?m)^\s*func\s+\w+"#,
            #"(?m)^\s*class\s+\w+"#,
            #"Traceback \(most recent call last\)"#,
            #"File \".*\", line \d+"#,
            #"(?m)^\s*#\s*include\b"#,
            #"\bpublic\s+static\s+void\b"#,
            #"(?m)^\s*package\s+\w+"#,
            #"(?m)^\s*const\s+\w+\s*="#,
            #"(?m)^\s*let\s+\w+\s*="#,
        ]

        for pattern in patterns {
            if text.range(of: pattern, options: .regularExpression) != nil {
                return true
            }
        }

        return false
    }
}
