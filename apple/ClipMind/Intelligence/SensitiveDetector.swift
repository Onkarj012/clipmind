import Foundation

enum SensitiveDetector {
    private static let jwtPattern = #"[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"#

    static func isSensitive(_ text: String) -> Bool {
        if text.contains("sk-") {
            return true
        }
        if text.contains("ghp_") {
            return true
        }
        if text.contains("-----BEGIN") {
            return true
        }
        if text.range(of: jwtPattern, options: .regularExpression) != nil {
            return true
        }
        return false
    }
}
