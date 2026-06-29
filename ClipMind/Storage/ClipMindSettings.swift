import Foundation
import LaunchAtLogin
import SwiftUI

@MainActor
final class ClipMindSettings: ObservableObject {
    private enum Keys {
        static let hasSeenLoginPrompt = "hasSeenLoginPrompt"
        static let retentionMaxCount = "retentionMaxCount"
        static let retentionMaxAgeDays = "retentionMaxAgeDays"
        static let retentionInfinite = "retentionInfinite"
        static let keepPaletteOpenAfterPaste = "keepPaletteOpenAfterPaste"
        static let pasteDirectlyFromPalette = "pasteDirectlyFromPalette"
        static let semanticSearchEnabled = "semanticSearchEnabled"
        static let embeddingBackend = "embeddingBackend"
        static let ollamaBaseURL = "ollamaBaseURL"
        static let ollamaEmbeddingModel = "ollamaEmbeddingModel"
        static let aiMetadataEnabled = "aiMetadataEnabled"
        static let ollamaChatModel = "ollamaChatModel"
        static let groqModel = "groqModel"
        static let ocrEnabled = "ocrEnabled"
    }

    private let defaults: UserDefaults

    @Published var launchAtLogin: Bool {
        didSet {
            LaunchAtLogin.isEnabled = launchAtLogin
        }
    }

    @Published var hasSeenLoginPrompt: Bool {
        didSet { defaults.set(hasSeenLoginPrompt, forKey: Keys.hasSeenLoginPrompt) }
    }

    @Published var retentionMaxCount: Int {
        didSet { defaults.set(retentionMaxCount, forKey: Keys.retentionMaxCount) }
    }

    @Published var retentionMaxAgeDays: Int {
        didSet { defaults.set(retentionMaxAgeDays, forKey: Keys.retentionMaxAgeDays) }
    }

    @Published var retentionInfinite: Bool {
        didSet { defaults.set(retentionInfinite, forKey: Keys.retentionInfinite) }
    }

    @Published var keepPaletteOpenAfterPaste: Bool {
        didSet { defaults.set(keepPaletteOpenAfterPaste, forKey: Keys.keepPaletteOpenAfterPaste) }
    }

    /// When true, activating a clip in the palette pastes it into the active app.
    /// When false, it only copies the clip to the clipboard for the user to paste later.
    @Published var pasteDirectlyFromPalette: Bool {
        didSet { defaults.set(pasteDirectlyFromPalette, forKey: Keys.pasteDirectlyFromPalette) }
    }

    @Published var semanticSearchEnabled: Bool {
        didSet { defaults.set(semanticSearchEnabled, forKey: Keys.semanticSearchEnabled) }
    }

    @Published var embeddingBackend: EmbeddingBackend {
        didSet { defaults.set(embeddingBackend.rawValue, forKey: Keys.embeddingBackend) }
    }

    @Published var ollamaBaseURL: String {
        didSet { defaults.set(ollamaBaseURL, forKey: Keys.ollamaBaseURL) }
    }

    @Published var ollamaEmbeddingModel: String {
        didSet { defaults.set(ollamaEmbeddingModel, forKey: Keys.ollamaEmbeddingModel) }
    }

    @Published var aiMetadataEnabled: Bool {
        didSet { defaults.set(aiMetadataEnabled, forKey: Keys.aiMetadataEnabled) }
    }

    @Published var ollamaChatModel: String {
        didSet { defaults.set(ollamaChatModel, forKey: Keys.ollamaChatModel) }
    }

    @Published var groqModel: String {
        didSet { defaults.set(groqModel, forKey: Keys.groqModel) }
    }

    @Published var ocrEnabled: Bool {
        didSet { defaults.set(ocrEnabled, forKey: Keys.ocrEnabled) }
    }

    private let secretsStore: SecretsStore
    @Published private(set) var hasGroqAPIKey: Bool

    var retentionSettings: RetentionSettings {
        RetentionSettings(
            maxCount: retentionMaxCount,
            maxAgeDays: retentionMaxAgeDays,
            infinite: retentionInfinite
        )
    }

    var semanticSearchSettings: SemanticSearchSettings {
        SemanticSearchSettings(
            isEnabled: semanticSearchEnabled,
            backend: embeddingBackend,
            ollamaBaseURL: ollamaBaseURL,
            ollamaEmbeddingModel: ollamaEmbeddingModel
        )
    }

    var ocrSettings: OCRSettings {
        OCRSettings(isEnabled: ocrEnabled)
    }

    var aiMetadataSettings: AIMetadataSettings {
        AIMetadataSettings(
            isEnabled: aiMetadataEnabled,
            groqModel: groqModel,
            ollamaBaseURL: ollamaBaseURL,
            ollamaChatModel: ollamaChatModel,
            hasGroqKey: hasGroqAPIKey
        )
    }

    init(defaults: UserDefaults = .standard, secretsStore: SecretsStore = KeychainSecretsStore()) {
        self.defaults = defaults
        self.secretsStore = secretsStore
        self.launchAtLogin = LaunchAtLogin.isEnabled
        self.hasSeenLoginPrompt = defaults.bool(forKey: Keys.hasSeenLoginPrompt)
        self.retentionMaxCount = defaults.object(forKey: Keys.retentionMaxCount) as? Int ?? 500
        self.retentionMaxAgeDays = defaults.object(forKey: Keys.retentionMaxAgeDays) as? Int ?? 30
        self.retentionInfinite = defaults.bool(forKey: Keys.retentionInfinite)
        self.keepPaletteOpenAfterPaste = defaults.bool(forKey: Keys.keepPaletteOpenAfterPaste)
        self.pasteDirectlyFromPalette = defaults.object(forKey: Keys.pasteDirectlyFromPalette) as? Bool ?? true
        self.semanticSearchEnabled = defaults.object(forKey: Keys.semanticSearchEnabled) as? Bool ?? true
        if let rawBackend = defaults.string(forKey: Keys.embeddingBackend),
           let backend = EmbeddingBackend(rawValue: rawBackend)
        {
            self.embeddingBackend = backend
        } else {
            self.embeddingBackend = .apple
        }
        self.ollamaBaseURL = defaults.string(forKey: Keys.ollamaBaseURL) ?? SemanticSearchSettings.defaults.ollamaBaseURL
        self.ollamaEmbeddingModel = defaults.string(forKey: Keys.ollamaEmbeddingModel) ?? EmbeddingGenerator.defaultOllamaModel
        self.aiMetadataEnabled = defaults.object(forKey: Keys.aiMetadataEnabled) as? Bool ?? true
        self.ollamaChatModel = defaults.string(forKey: Keys.ollamaChatModel) ?? AIMetadataSettings.defaults.ollamaChatModel
        self.groqModel = defaults.string(forKey: Keys.groqModel) ?? AIMetadataSettings.defaults.groqModel
        self.ocrEnabled = defaults.object(forKey: Keys.ocrEnabled) as? Bool ?? true
        self.hasGroqAPIKey = (try? secretsStore.read(key: .groqAPIKey)).flatMap { $0?.isEmpty == false ? true : nil } ?? false
    }

    func saveGroqAPIKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try secretsStore.delete(key: .groqAPIKey)
            hasGroqAPIKey = false
        } else {
            try secretsStore.write(key: .groqAPIKey, value: trimmed)
            hasGroqAPIKey = true
        }
    }

    func clearGroqAPIKey() throws {
        try secretsStore.delete(key: .groqAPIKey)
        hasGroqAPIKey = false
    }

    /// Reads the stored Groq API key back from the keychain so the UI can reveal it.
    func revealGroqAPIKey() -> String? {
        (try? secretsStore.read(key: .groqAPIKey)).flatMap { $0 }
    }

    func completeFirstRunLoginPrompt(enable: Bool) {
        launchAtLogin = enable
        hasSeenLoginPrompt = true
    }
}
