import Foundation

final class EmbeddingIndexer: @unchecked Sendable {
    private let repository: ClipboardRepository
    private let lock = NSLock()
    private var pendingItemIDs: [String] = []
    private var isProcessing = false
    private let workQueue = DispatchQueue(label: "io.clipmind.embedding-indexer", qos: .utility)

    var settingsProvider: () -> SemanticSearchSettings = { .defaults }

    init(repository: ClipboardRepository) {
        self.repository = repository
    }

    func enqueue(item: ClipboardItem) {
        let settings = settingsProvider()
        guard settings.isEnabled else { return }

        let text = embeddingText(for: item)
        guard let text, !text.isEmpty else { return }

        let generator = EmbeddingGenerator.make(settings: settings)
        guard generator.shouldEmbed(text: text) else { return }

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
    }

    func embedQuery(_ text: String) async throws -> [Float] {
        let generator = EmbeddingGenerator.make(settings: settingsProvider())
        return try await generator.generateEmbedding(for: text)
    }

    var activeModelIdentifier: String {
        settingsProvider().embeddingModelIdentifier
    }

    private func embeddingText(for item: ClipboardItem) -> String? {
        if let contentText = item.contentText, !contentText.isEmpty {
            return contentText
        }
        if item.type == "image",
           let asset = try? repository.fetchAsset(for: item.id),
           let ocrText = asset.ocrText,
           !ocrText.isEmpty
        {
            return ocrText
        }
        return nil
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

            let settings = settingsProvider()
            guard settings.isEnabled else { continue }

            let generator = EmbeddingGenerator.make(settings: settings)

            do {
                guard let item = try repository.fetch(id: itemID),
                      let text = embeddingText(for: item),
                      generator.shouldEmbed(text: text)
                else {
                    continue
                }

                let vector = try awaitSync {
                    try await generator.generateEmbedding(for: text)
                }

                try repository.upsertEmbedding(
                    itemID: itemID,
                    model: generator.modelIdentifier,
                    vector: vector
                )
            } catch {
                NSLog("ClipMind: failed to index embedding for \(itemID): \(error.localizedDescription)")
            }
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
            throw AppleEmbeddingError.embeddingFailed
        }
    }
}
