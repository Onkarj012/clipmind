import Foundation

enum LibraryFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case all
    case text
    case code
    case links
    case images
    case files
    case favorites
    case sensitive
    case trash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .text: "Text"
        case .code: "Code"
        case .links: "Links"
        case .images: "Images"
        case .files: "Files"
        case .favorites: "Favorites"
        case .sensitive: "Sensitive"
        case .trash: "Trash"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "tray.full"
        case .text: "doc.text"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .links: "link"
        case .images: "photo"
        case .files: "doc"
        case .favorites: "star.fill"
        case .sensitive: "lock.shield"
        case .trash: "trash"
        }
    }
}
