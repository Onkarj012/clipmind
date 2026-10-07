import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let commandPalette = Self(
        "commandPalette",
        default: .init(.v, modifiers: [.command, .shift])
    )
    static let openLibrary = Self(
        "openLibrary",
        default: .init(.l, modifiers: [.command, .shift])
    )
}
