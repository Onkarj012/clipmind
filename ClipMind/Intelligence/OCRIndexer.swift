import Foundation

final class OCRIndexer: @unchecked Sendable {
    typealias OCRTextProvider = (URL) async throws -> String

    private let repository: ClipboardRepository
    private let lock = NSLock()
    private var pendingItemIDs: [String] = []
    private var isProcessing = false
    private var hasBackfilled = false
    private let workQueue = DispatchQueue(label: "io.clipmind.ocr-indexer", qos: .utility)

    var settingsProvider: () -> OCRSettings = { .defaults }
    var ocrTextProvider: OCRTextProvider = { url in
        try await VisionOCRService().recognizeText(at: url)
    }
    var onOCRCompleted: ((ClipboardItem) -> Void)?

    init(repository: ClipboardRepository) {
        self.repository = repository
    }

    func enqueue(item: ClipboardItem) {
        guard item.type == "image" else { return }
        guard settingsProvider().isEnabled else { return }

        lock.lock()
        pendingItemIDs.append(item.id)
        let shouldStart = !isProcessing
        if shouldStart {
            isProcessing = true
        }
        lock.unlock()

        if shouldStart {
            workQueue.async { [weak self] in
                self?.processQueue()
            }
        }

        scheduleBackfillIfNeeded()
    }

    func scheduleBackfillIfNeeded() {
        guard settingsProvider().isEnabled else { return }
        lock.lock()
        let shouldRun = !hasBackfilled
        if shouldRun {
            hasBackfilled = true
        }
        lock.unlock()
        guard shouldRun else { return }

        workQueue.async { [weak self] in
            self?.backfillExistingImages()
        }
    }

    private func backfillExistingImages() {
        guard settingsProvider().isEnabled else { return }

        do {
            let itemIDs = try repository.fetchImageItemIDsMissingOCR()
            for itemID in itemIDs {
                processItem(itemID: itemID)
            }
        } catch {
            NSLog("ClipMind: OCR backfill failed: \(error.localizedDescription)")
        }
    }

    private func processQueue() {
        while true {
            let itemID: String? = {
                lock.lock()
                defer { lock.unlock() }
                return pendingItemIDs.isEmpty ? nil : pendingItemIDs.removeFirst()
            }()

            guard let itemID else {
                lock.lock()
                isProcessing = false
                lock.unlock()
                return
            }

            processItem(itemID: itemID)
        }
    }

    private func processItem(itemID: String) {
        guard settingsProvider().isEnabled else { return }

        do {
            guard let asset = try repository.fetchAsset(for: itemID),
                  asset.ocrText?.isEmpty != false
            else {
                return
            }

            let imageURL = URL(fileURLWithPath: asset.filePath)
            let text = try awaitSync {
                try await self.ocrTextProvider(imageURL)
            }

            let updatedItem = try repository.applyOCRText(itemID: itemID, text: text)
            onOCRCompleted?(updatedItem)
        } catch VisionOCRError.noTextFound {
            return
        } catch {
            NSLog("ClipMind: failed OCR for \(itemID): \(error.localizedDescription)")
        }
    }

    private func awaitSync<T>(_ operation: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: Result<T, Error>?
        Task {
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        switch result {
        case let .success(value):
            return value
        case let .failure(error):
            throw error
        case .none:
            throw VisionOCRError.invalidImage
        }
    }
}
