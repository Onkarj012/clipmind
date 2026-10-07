import Foundation

final class AIMetadataSettingsStore: @unchecked Sendable {
    private let lock = NSLock()
    private var settings: AIMetadataSettings

    init(_ settings: AIMetadataSettings) {
        self.settings = settings
    }

    func current() -> AIMetadataSettings {
        lock.lock()
        defer { lock.unlock() }
        return settings
    }

    func update(_ settings: AIMetadataSettings) {
        lock.lock()
        self.settings = settings
        lock.unlock()
    }
}
