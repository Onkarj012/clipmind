import AppKit
import ApplicationServices
import Foundation

enum PasteResult: Equatable {
    case pasted
    case copiedOnly
    case accessibilityRequired
    case noContent
}

enum PasteController {
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func copyToPasteboard(_ item: ClipboardItem, repository: ClipboardRepository) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        switch item.type {
        case "image":
            guard
                let asset = try? repository.fetchAsset(for: item.id),
                let data = FileManager.default.contents(atPath: asset.filePath)
            else {
                return false
            }

            let pasteboardType: NSPasteboard.PasteboardType
            switch asset.mimeType.lowercased() {
            case "image/png":
                pasteboardType = .png
            case "image/tiff":
                pasteboardType = .tiff
            default:
                return false
            }

            return pasteboard.setData(data, forType: pasteboardType)

        case "file":
            guard let path = item.filePath else {
                return false
            }

            let url = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: path) else {
                return false
            }

            return pasteboard.writeObjects([url as NSURL])

        default:
            guard let text = item.contentText, !text.isEmpty else {
                return false
            }
            return pasteboard.setString(text, forType: .string)
        }
    }

    static func paste(
        item: ClipboardItem,
        repository: ClipboardRepository,
        simulateKeystroke: Bool = true
    ) -> PasteResult {
        guard copyToPasteboard(item, repository: repository) else {
            return .noContent
        }

        do {
            try repository.touchLastUsed(id: item.id)
        } catch {
            NSLog("ClipMind: failed to update last_used_at: \(error.localizedDescription)")
        }

        guard simulateKeystroke else {
            return .copiedOnly
        }

        guard isAccessibilityTrusted else {
            requestAccessibilityPrompt()
            return .accessibilityRequired
        }

        simulateCommandV()
        return .pasted
    }

    static func pasteText(_ text: String) -> PasteResult {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            return .noContent
        }

        guard isAccessibilityTrusted else {
            requestAccessibilityPrompt()
            return .accessibilityRequired
        }

        simulateCommandV()
        return .pasted
    }

    static func postCommandV() {
        simulateCommandV()
    }

    private static func simulateCommandV() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
