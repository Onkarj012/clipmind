import Foundation

struct OCRSettings: Equatable, Sendable {
    var isEnabled: Bool

    static let defaults = OCRSettings(isEnabled: true)
}

final class OCRSettingsStore: @unchecked Sendable {
    private let lock = NSLock()
    private var settings: OCRSettings

    init(_ settings: OCRSettings) {
        self.settings = settings
    }

    func current() -> OCRSettings {
        lock.lock()
        defer { lock.unlock() }
        return settings
    }

    func update(_ settings: OCRSettings) {
        lock.lock()
        self.settings = settings
        lock.unlock()
    }
}
