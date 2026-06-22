import AppKit
import Foundation

@MainActor
final class ClipboardWatcher: ObservableObject {
    @Published private(set) var changeToken = 0
    var isPaused = false

    private let repository: ClipboardRepository
    private let pasteboard: NSPasteboard
    private let ownBundleID: String?
    private var lastChangeCount: Int
    private var timer: Timer?
    var retentionSettingsProvider: (() -> RetentionSettings)?
    var onItemInserted: ((ClipboardItem) -> Void)?

    init(
        repository: ClipboardRepository,
        pasteboard: NSPasteboard = .general,
        ownBundleID: String? = Bundle.main.bundleIdentifier
    ) {
        self.repository = repository
        self.pasteboard = pasteboard
        self.ownBundleID = ownBundleID
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        lastChangeCount = pasteboard.changeCount

        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.poll()
            }
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        guard !isPaused else { return }

        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        let source = SourceAppDetector.currentSourceApp()
        if let ownBundleID, source.bundleID == ownBundleID {
            return
        }

        if CaptureDenylist.shouldIgnore(bundleID: source.bundleID) {
            return
        }

        if let extractedImage = PasteboardImageExtractor.extract(from: pasteboard) {
            do {
                let retention = retentionSettingsProvider?() ?? RetentionSettings.defaults
                let item = try repository.insertImage(
                    ClipboardImageInsertInput(
                        imageData: extractedImage.data,
                        format: extractedImage.format,
                        sourceApp: source.name,
                        sourceBundleId: source.bundleID
                    ),
                    retention: retention
                )
                onItemInserted?(item)
                changeToken += 1
            } catch ClipboardRepositoryError.emptyContent {
                return
            } catch {
                NSLog("ClipMind: failed to save image clipboard item: \(error.localizedDescription)")
            }
            return
        }

        if let file = PasteboardFileExtractor.extract(from: pasteboard) {
            do {
                let retention = retentionSettingsProvider?() ?? RetentionSettings.defaults
                let item = try repository.insertFile(
                    ClipboardFileInsertInput(
                        path: file.path,
                        displayName: file.displayName,
                        sourceApp: source.name,
                        sourceBundleId: source.bundleID
                    ),
                    retention: retention
                )
                onItemInserted?(item)
                changeToken += 1
            } catch ClipboardRepositoryError.emptyContent {
                return
            } catch {
                NSLog("ClipMind: failed to save file clipboard item: \(error.localizedDescription)")
            }
            return
        }

        if let extracted = PasteboardTextExtractor.extract(from: pasteboard) {
            do {
                let retention = retentionSettingsProvider?() ?? RetentionSettings.defaults
                let item = try repository.insertText(
                    ClipboardInsertInput(
                        text: extracted.plainText,
                        sourceApp: source.name,
                        sourceBundleId: source.bundleID,
                        metadata: extracted.metadata
                    ),
                    retention: retention
                )
                onItemInserted?(item)
                changeToken += 1
            } catch ClipboardRepositoryError.emptyContent {
                return
            } catch {
                NSLog("ClipMind: failed to save clipboard item: \(error.localizedDescription)")
            }
        }
    }
}
