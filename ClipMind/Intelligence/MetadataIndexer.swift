import Foundation

final class MetadataIndexer: @unchecked Sendable {
    typealias IndexingStateHandler = (String, Bool) -> Void

    private let repository: ClipboardRepository
    private let lock = NSLock()
    private var pendingItemIDs: [String] = []
    private var isProcessing = false
    private let workQueue = DispatchQueue(label: "io.clipmind.metadata-indexer", qos: .utility)

    var settingsProvider: () -> AIMetadataSettings = { .defaults }
    var providerFactory: (AIMetadataSettings) -> any LLMProvider = { settings in
        LLMProviderChain.make(settings: settings)
    }
    var onIndexingStateChange: IndexingStateHandler?

    init(repository: ClipboardRepository) {
        self.repository = repository
    }

    func enqueue(item: ClipboardItem) {
        guard let text = item.contentText, !text.isEmpty else { return }
        guard AIMetadataService.shouldProcess(text: text, type: item.type) else { return }

        let settings = settingsProvider()
        guard settings.isEnabled else { return }

        lock.lock()
        pendingItemIDs.append(item.id)
        let shouldStart = !isProcessing
        if shouldStart {
            isProcessing = true
        }
        lock.unlock()

        onIndexingStateChange?(item.id, true)

        if shouldStart {
            workQueue.async { [weak self] in
                self?.processQueue()
            }
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

            defer {
                onIndexingStateChange?(itemID, false)
            }

            let settings = settingsProvider()
            guard settings.isEnabled else { continue }

            do {
                guard let item = try repository.fetch(id: itemID),
                      let text = item.contentText
                else {
                    continue
                }

                guard AIMetadataService.shouldProcess(text: text, type: item.type) else {
                    continue
                }

                let metadata: ClipAIMetadata?
                if item.isSensitive {
                    metadata = AIMetadataService.generateRulesFirst(text: text, type: item.type)
                        ?? AIMetadataService.rulesBasedMetadata(text: text, type: item.type)
                } else if let rules = AIMetadataService.generateRulesFirst(text: text, type: item.type) {
                    metadata = rules
                } else {
                    let provider = providerFactory(settings)
                    metadata = try awaitSync {
                        try await AIMetadataService.generateWithLLM(
                            text: text,
                            type: item.type,
                            provider: provider
                        )
                    }
                }

                guard let metadata else { continue }

                try repository.applyAIMetadata(itemID: itemID, metadata: metadata)
            } catch {
                NSLog("ClipMind: failed to index metadata for \(itemID): \(error.localizedDescription)")
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
            throw OllamaChatError.emptyResponse
        }
    }
}
