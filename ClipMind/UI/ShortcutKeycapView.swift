import SwiftUI
import KeyboardShortcuts

/// Renders the currently-assigned shortcut for a `KeyboardShortcuts.Name` as a row of
/// individual keycap boxes joined by "+", e.g. ⌘ + ⇧ + V.
struct ShortcutKeycapView: View {
    let name: KeyboardShortcuts.Name

    private var keys: [String] {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return [] }
        return shortcut.description.map(String.init)
    }

    var body: some View {
        if keys.isEmpty {
            Text("Not set")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                    if index > 0 {
                        Text("+")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.tertiary)
                    }
                    Keycap(symbol: key)
                }
            }
        }
    }
}

private struct Keycap: View {
    let symbol: String

    var body: some View {
        Text(symbol)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.quaternary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.separator, lineWidth: 0.5)
            )
    }
}
