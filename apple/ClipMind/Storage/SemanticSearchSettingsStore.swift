import Foundation

final class SemanticSearchSettingsStore: @unchecked Sendable {
    private let lock = NSLock()
    private var settings: SemanticSearchSettings

    init(_ settings: SemanticSearchSettings) {
        self.settings = settings
    }

    func update(_ settings: SemanticSearchSettings) {
        lock.lock()
        self.settings = settings
        lock.unlock()
    }

    func current() -> SemanticSearchSettings {
        lock.lock()
        defer { lock.unlock() }
        return settings
    }
}
