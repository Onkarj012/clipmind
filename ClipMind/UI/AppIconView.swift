import AppKit
import SwiftUI

/// Resolves and renders the real application icon for a clip's source app.
/// Falls back to a generic SF Symbol when the bundle id is missing or unresolvable.
struct AppIconView: View {
    let bundleId: String?
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let icon = AppIconResolver.icon(for: bundleId) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app")
                    .font(.system(size: size * 0.85))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Caches resolved app icons keyed by bundle identifier to avoid repeated workspace lookups.
@MainActor
private enum AppIconResolver {
    private static var cache: [String: NSImage?] = [:]

    static func icon(for bundleId: String?) -> NSImage? {
        guard let bundleId, !bundleId.isEmpty else { return nil }
        if let cached = cache[bundleId] { return cached }

        let resolved: NSImage?
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            resolved = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            resolved = nil
        }
        cache[bundleId] = resolved
        return resolved
    }
}
