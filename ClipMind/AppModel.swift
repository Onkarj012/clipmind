import AppKit
import Combine
import Foundation
import KeyboardShortcuts
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var clips: [ClipboardItem] = []
    @Published var searchQuery = "" {
        didSet { refreshClips() }
    }

    @Published var libraryFilter: LibraryFilter = .all {
        didSet { refreshLibraryClips() }
    }
    @Published var librarySearchQuery = "" {
        didSet { refreshLibraryClips() }
    }
    @Published private(set) var libraryClips: [ClipboardItem] = []
    @Published private(set) var indexingItemIDs: Set<String> = []

    @Published var paletteQuery = ""
    @Published private(set) var paletteClips: [ClipboardItem] = []
    @Published var paletteSelectedIndex = 0
    @Published var paletteFocusToken = UUID()
    @Published var showAccessibilityBanner = false

    @Published var isTrackingPaused = false {
        didSet { clipboardWatcher.isPaused = isTrackingPaused }
    }
    @Published var showLibraryAccessibilityAlert = false

    let repository: ClipboardRepository
    let clipboardWatcher: ClipboardWatcher
    let settings: ClipMindSettings
    let embeddingIndexer: EmbeddingIndexer
    let metadataIndexer: MetadataIndexer
    let ocrIndexer: OCRIndexer

    private let commandPalettePanel = FloatingPanelManager()
    private var paletteShortcutMonitor: Any?
    private var openLibraryHandler: ((LibraryTab) -> Void)?
    private var paletteTargetApplication: NSRunningApplication?
    private var cancellables = Set<AnyCancellable>()
    private var semanticSearchTask: Task<Void, Never>?
    private let semanticSettingsStore: SemanticSearchSettingsStore
    private let metadataSettingsStore: AIMetadataSettingsStore
    private let ocrSettingsStore: OCRSettingsStore

    private var assetCache: [String: ClipboardAsset] = [:]
    private var tagCache: [String: [Tag]] = [:]

    var selectedPaletteClip: ClipboardItem? {
        guard paletteClips.indices.contains(paletteSelectedIndex) else { return nil }
        return paletteClips[paletteSelectedIndex]
    }

    init(settings: ClipMindSettings) {
        self.settings = settings
        self.semanticSettingsStore = SemanticSearchSettingsStore(settings.semanticSearchSettings)
        self.metadataSettingsStore = AIMetadataSettingsStore(settings.aiMetadataSettings)
        self.ocrSettingsStore = OCRSettingsStore(settings.ocrSettings)
        do {
            let queue = try DatabaseManager.openProductionQueue()
            let repository = ClipboardRepository(dbWriter: queue)
            self.repository = repository
            let indexer = EmbeddingIndexer(repository: repository)
            self.embeddingIndexer = indexer
            let metadataIndexer = MetadataIndexer(repository: repository)
            self.metadataIndexer = metadataIndexer
            let ocrIndexer = OCRIndexer(repository: repository)
            self.ocrIndexer = ocrIndexer
            let watcher = ClipboardWatcher(repository: repository)
            self.clipboardWatcher = watcher
            watcher.retentionSettingsProvider = { [weak self] in
                self?.settings.retentionSettings ?? RetentionSettings.defaults
            }
            indexer.settingsProvider = { [semanticSettingsStore] in
                semanticSettingsStore.current()
            }
            metadataIndexer.settingsProvider = { [metadataSettingsStore] in
                metadataSettingsStore.current()
            }
            ocrIndexer.settingsProvider = { [ocrSettingsStore] in
                ocrSettingsStore.current()
            }
            ocrIndexer.onOCRCompleted = { [weak indexer] item in
                indexer?.enqueue(item: item)
            }
            metadataIndexer.onIndexingStateChange = { [weak self] itemID, isIndexing in
                Task { @MainActor in
                    guard let self else { return }
                    if isIndexing {
                        self.indexingItemIDs.insert(itemID)
                    } else {
                        self.indexingItemIDs.remove(itemID)
                        self.tagCache.removeValue(forKey: itemID)
                        self.refreshAll()
                    }
                }
            }
            watcher.onItemInserted = { [weak indexer, weak metadataIndexer, weak ocrIndexer] item in
                indexer?.enqueue(item: item)
                metadataIndexer?.enqueue(item: item)
                ocrIndexer?.enqueue(item: item)
            }
            clipboardWatcher.start()

            settings.$semanticSearchEnabled
                .combineLatest(
                    settings.$embeddingBackend,
                    settings.$ollamaBaseURL,
                    settings.$ollamaEmbeddingModel
                )
                .sink { [weak self] _, _, _, _ in
                    guard let self else { return }
                    self.semanticSettingsStore.update(self.settings.semanticSearchSettings)
                }
                .store(in: &cancellables)

            settings.$aiMetadataEnabled
                .combineLatest(
                    settings.$ollamaBaseURL,
                    settings.$ollamaChatModel,
                    settings.$groqModel
                )
                .combineLatest(settings.$hasGroqAPIKey)
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.metadataSettingsStore.update(self.settings.aiMetadataSettings)
                }
                .store(in: &cancellables)

            settings.$ocrEnabled
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.ocrSettingsStore.update(self.settings.ocrSettings)
                    if self.settings.ocrEnabled {
                        self.ocrIndexer.scheduleBackfillIfNeeded()
                    }
                }
                .store(in: &cancellables)

            clipboardWatcher.$changeToken
                .dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.handleClipboardChange()
                }
                .store(in: &cancellables)

            registerShortcuts()
            refreshClips()
            refreshLibraryClips()
        } catch {
            fatalError("Failed to open database: \(error)")
        }
    }

    func setOpenLibraryHandler(_ handler: @escaping (LibraryTab) -> Void) {
        openLibraryHandler = handler
    }

    func refreshClips() {
        performSearch(
            query: searchQuery,
            limit: 200,
            assign: { [weak self] results in
                self?.clips = results
            }
        )
    }

    func refreshLibraryClips() {
        if libraryFilter == .trash {
            do {
                libraryClips = try repository.list(filter: .trash)
            } catch {
                NSLog("ClipMind: failed to load library clips: \(error.localizedDescription)")
            }
            return
        }

        var query = librarySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            do {
                libraryClips = try repository.list(filter: libraryFilter)
            } catch {
                NSLog("ClipMind: failed to load library clips: \(error.localizedDescription)")
            }
            return
        }

        switch libraryFilter {
        case .all:
            break
        case .text, .code:
            query += " type:\(libraryFilter.rawValue)"
        case .links:
            query += " type:url"
        case .images:
            query += " type:image"
        case .files:
            query += " type:file"
        case .favorites:
            query += " is:favorite"
        case .sensitive:
            query += " is:sensitive"
        case .trash:
            return
        }

        performSearch(
            query: query,
            limit: 200,
            assign: { [weak self] results in
                self?.libraryClips = results
            }
        )
    }

    func refreshPaletteClips() {
        performSearch(
            query: paletteQuery,
            limit: 50,
            assign: { [weak self] results in
                guard let self else { return }
                self.paletteClips = results
                self.paletteSelectedIndex = min(self.paletteSelectedIndex, max(results.count - 1, 0))
            }
        )
    }

    func asset(for itemID: String) -> ClipboardAsset? {
        if let cached = assetCache[itemID] {
            return cached
        }
        guard let asset = try? repository.fetchAsset(for: itemID) else {
            return nil
        }
        assetCache[itemID] = asset
        return asset
    }

    func tags(for itemID: String) -> [Tag] {
        if let cached = tagCache[itemID] {
            return cached
        }
        guard let tags = try? repository.fetchTags(for: itemID) else {
            return []
        }
        tagCache[itemID] = tags
        return tags
    }

    func similarClips(for item: ClipboardItem, limit: Int = 5) -> [ClipboardItem] {
        let model = semanticSettingsStore.current().embeddingModelIdentifier
        return (try? repository.fetchSimilarItems(
            for: item.id,
            embeddingModel: model,
            limit: limit
        )) ?? []
    }

    func isIndexing(_ itemID: String) -> Bool {
        indexingItemIDs.contains(itemID)
    }

    func toggleTrackingPause() {
        isTrackingPaused.toggle()
    }

    // MARK: - Command Palette

    func toggleCommandPalette() {
        if commandPalettePanel.isVisible {
            hideCommandPalette()
        } else {
            showCommandPalette(reset: true, targetApplication: NSWorkspace.shared.frontmostApplication)
        }
    }

    private func showCommandPalette(reset: Bool, targetApplication: NSRunningApplication?) {
        paletteTargetApplication = targetApplication
        if reset {
            paletteQuery = ""
            paletteSelectedIndex = 0
        }
        paletteFocusToken = UUID()
        refreshPaletteClips()
        showAccessibilityBanner = false

        commandPalettePanel.show(
            content: CommandPaletteView().environmentObject(self),
            size: CGSize(
                width: CommandPaletteMetrics.width,
                height: CommandPaletteMetrics.height
            ),
            onPresented: { [weak self] in
                self?.paletteFocusToken = UUID()
            },
            onClose: { [weak self] in
                self?.removePaletteShortcutMonitor()
                self?.showAccessibilityBanner = false
            }
        )
        installPaletteShortcutMonitor()
    }

    func hideCommandPalette() {
        removePaletteShortcutMonitor()
        commandPalettePanel.hide()
        showAccessibilityBanner = false
        paletteTargetApplication = nil
    }

    func movePaletteSelection(delta: Int) {
        guard !paletteClips.isEmpty else { return }
        paletteSelectedIndex = (paletteSelectedIndex + delta + paletteClips.count) % paletteClips.count
    }

    func pasteSelectedPaletteClip() {
        guard let item = selectedPaletteClip else { return }
        if settings.pasteDirectlyFromPalette {
            pastePaletteClip(item, keepPaletteOpen: settings.keepPaletteOpenAfterPaste)
        } else {
            // Copy-only mode: set the clip as the latest clipboard entry for manual paste later.
            copyClip(item)
            if !settings.keepPaletteOpenAfterPaste {
                hideCommandPalette()
            }
        }
    }

    func copySelectedPaletteClip() {
        guard let item = selectedPaletteClip else { return }
        copyClip(item)
    }

    func toggleFavoriteSelectedPaletteClip() {
        guard let item = selectedPaletteClip else { return }
        toggleFavorite(item)
    }

    func deleteSelectedPaletteClip() {
        guard let item = selectedPaletteClip else { return }
        softDeleteClip(item)
        refreshPaletteClips()
        if paletteClips.isEmpty {
            paletteSelectedIndex = 0
        } else {
            paletteSelectedIndex = min(paletteSelectedIndex, paletteClips.count - 1)
        }
    }

    func runAIAction(_ action: AIClipAction, on text: String) async throws -> String {
        let settings = metadataSettingsStore.current()
        let provider = LLMProviderChain.make(settings: settings)
        return try await AIActionService.run(action: action, text: text, provider: provider)
    }

    // MARK: - Clip Actions

    func copyClip(_ item: ClipboardItem) {
        _ = PasteController.copyToPasteboard(item, repository: repository)
        touchLastUsed(item)
    }

    func pasteClip(_ item: ClipboardItem, closePalette: (() -> Void)? = nil) {
        let result = PasteController.paste(item: item, repository: repository)
        switch result {
        case .pasted, .copiedOnly:
            if !settings.keepPaletteOpenAfterPaste {
                closePalette?()
            }
            refreshAll()
        case .accessibilityRequired:
            showAccessibilityBanner = true
            showLibraryAccessibilityAlert = true
        case .noContent:
            break
        }
    }

    func toggleFavorite(_ item: ClipboardItem) {
        do {
            _ = try repository.toggleFavorite(id: item.id)
            refreshAll()
        } catch {
            NSLog("ClipMind: failed to toggle favorite: \(error.localizedDescription)")
        }
    }

    func softDeleteClip(_ item: ClipboardItem) {
        do {
            try repository.softDelete(id: item.id)
            refreshAll()
        } catch {
            NSLog("ClipMind: failed to delete clip: \(error.localizedDescription)")
        }
    }

    func restoreClip(_ item: ClipboardItem) {
        do {
            try repository.restore(id: item.id)
            refreshAll()
        } catch {
            NSLog("ClipMind: failed to restore clip: \(error.localizedDescription)")
        }
    }

    func clearHistory() {
        do {
            try repository.clearHistory()
            refreshAll()
        } catch {
            NSLog("ClipMind: failed to clear history: \(error.localizedDescription)")
        }
    }

    func emptyTrash() {
        do {
            try repository.emptyTrash()
            refreshAll()
        } catch {
            NSLog("ClipMind: failed to empty trash: \(error.localizedDescription)")
        }
    }

    func openLibrary(tab: LibraryTab = .clips) {
        openLibraryHandler?(tab)
    }

    func libraryWillOpen() {
        NSApp.setActivationPolicy(.regular)
    }

    func libraryWindowDidOpen() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func libraryWindowDidClose() {
        if !commandPalettePanel.isVisible {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Private

    private func performSearch(
        query: String,
        limit: Int,
        assign: @escaping ([ClipboardItem]) -> Void
    ) {
        semanticSearchTask?.cancel()
        semanticSearchTask = nil
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            do {
                assign(try repository.listByRecency(limit: limit))
            } catch {
                NSLog("ClipMind: failed to load clips: \(error.localizedDescription)")
            }
            return
        }

        let parsed = ClipboardRepository.parseSearchQuery(trimmedQuery)
        let shouldUseSemantic = settings.semanticSearchEnabled && parsed.qualifiesForSemanticSearch

        if shouldUseSemantic {
            let embeddingModel = semanticSettingsStore.current().embeddingModelIdentifier
            semanticSearchTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let embedding = try await embeddingIndexer.embedQuery(parsed.keywords)
                    guard !Task.isCancelled else { return }
                    let results = try repository.search(
                        trimmedQuery,
                        limit: limit,
                        queryEmbedding: embedding,
                        embeddingModel: embeddingModel
                    )
                    guard !Task.isCancelled else { return }
                    assign(results)
                } catch is CancellationError {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    NSLog("ClipMind: semantic search failed, falling back to FTS: \(error.localizedDescription)")
                    fallbackSearch(query: trimmedQuery, limit: limit, assign: assign)
                }
            }
        } else {
            fallbackSearch(query: trimmedQuery, limit: limit, assign: assign)
        }
    }

    private func fallbackSearch(
        query: String,
        limit: Int,
        assign: ([ClipboardItem]) -> Void
    ) {
        do {
            assign(try repository.search(query, limit: limit))
        } catch {
            NSLog("ClipMind: failed to search clips: \(error.localizedDescription)")
        }
    }

    private func registerShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .commandPalette) { [weak self] in
            Task { @MainActor in
                self?.toggleCommandPalette()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .openLibrary) { [weak self] in
            Task { @MainActor in
                self?.openLibrary()
            }
        }
    }

    private func handleClipboardChange() {
        refreshAll()
        if commandPalettePanel.isVisible {
            refreshPaletteClips()
        }
    }

    private func refreshAll() {
        assetCache.removeAll()
        tagCache.removeAll()
        refreshClips()
        refreshLibraryClips()
    }

    private func touchLastUsed(_ item: ClipboardItem) {
        do {
            try repository.touchLastUsed(id: item.id)
            refreshAll()
        } catch {
            NSLog("ClipMind: failed to touch last used: \(error.localizedDescription)")
        }
    }

    private func installPaletteShortcutMonitor() {
        removePaletteShortcutMonitor()
        paletteShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.commandPalettePanel.isVisible else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            switch event.keyCode {
            case 53:
                self.hideCommandPalette()
                return nil
            case 36, 76:
                self.pasteSelectedPaletteClip()
                return nil
            case 125:
                self.movePaletteSelection(delta: 1)
                return nil
            case 126:
                self.movePaletteSelection(delta: -1)
                return nil
            case 8 where flags.contains(.command):
                self.copySelectedPaletteClip()
                return nil
            case 3 where flags.contains(.command):
                self.toggleFavoriteSelectedPaletteClip()
                return nil
            case 51 where flags.contains(.command):
                self.deleteSelectedPaletteClip()
                return nil
            default:
                return event
            }
        }
    }

    private func removePaletteShortcutMonitor() {
        if let paletteShortcutMonitor {
            NSEvent.removeMonitor(paletteShortcutMonitor)
            self.paletteShortcutMonitor = nil
        }
    }

    private func pastePaletteClip(_ item: ClipboardItem, keepPaletteOpen: Bool) {
        guard PasteController.copyToPasteboard(item, repository: repository) else { return }
        do {
            try repository.touchLastUsed(id: item.id)
        } catch {
            NSLog("ClipMind: failed to update last_used_at: \(error.localizedDescription)")
        }

        guard PasteController.isAccessibilityTrusted else {
            PasteController.requestAccessibilityPrompt()
            showAccessibilityBanner = true
            showLibraryAccessibilityAlert = true
            return
        }

        let targetApplication = paletteTargetApplication
        let preservedQuery = paletteQuery
        let preservedIndex = paletteSelectedIndex
        hideCommandPalette()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self, targetApplication] in
            targetApplication?.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                PasteController.postCommandV()
                Task { @MainActor in
                    guard let self else { return }
                    self.refreshAll()
                    if keepPaletteOpen {
                        self.paletteQuery = preservedQuery
                        self.paletteSelectedIndex = preservedIndex
                        self.showCommandPalette(reset: false, targetApplication: targetApplication)
                    }
                }
            }
        }
    }
}
