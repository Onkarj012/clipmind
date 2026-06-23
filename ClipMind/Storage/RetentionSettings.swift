import Foundation

struct RetentionSettings: Sendable, Equatable {
    var maxCount: Int
    var maxAgeDays: Int
    var infinite: Bool

    static let defaults = RetentionSettings(maxCount: 500, maxAgeDays: 30, infinite: false)
}
