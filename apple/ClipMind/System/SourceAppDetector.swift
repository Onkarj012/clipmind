import AppKit

enum SourceAppDetector {
    static func currentSourceApp() -> (name: String?, bundleID: String?) {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return (nil, nil)
        }
        return (app.localizedName, app.bundleIdentifier)
    }
}
