import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        SettingsForm(settings: appModel.settings)
            .environmentObject(appModel)
    }
}

struct SettingsForm: View {
    @ObservedObject var settings: ClipMindSettings
    @EnvironmentObject private var appModel: AppModel
    @State private var showClearHistoryConfirmation = false
    @State private var showEmptyTrashConfirmation = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }

            Section {
                Stepper(
                    "Max items: \(settings.retentionMaxCount)",
                    value: $settings.retentionMaxCount,
                    in: 50...10_000,
                    step: 50
                )
                .disabled(settings.retentionInfinite)

                Stepper(
                    "Max age: \(settings.retentionMaxAgeDays) days",
                    value: $settings.retentionMaxAgeDays,
                    in: 1...365
                )
                .disabled(settings.retentionInfinite)

                Toggle("Keep history forever", isOn: $settings.retentionInfinite)
            } header: {
                Text("Retention")
            } footer: {
                Text("Oldest non-favorite clips are removed when limits are exceeded. Favorites and trashed items are not affected.")
            }

            Section {
                Picker("On Enter", selection: $settings.pasteDirectlyFromPalette) {
                    Text("Paste into active app").tag(true)
                    Text("Copy to clipboard").tag(false)
                }
                Toggle("Keep palette open after paste", isOn: $settings.keepPaletteOpenAfterPaste)
            } header: {
                Text("Paste")
            } footer: {
                Text("Choose what pressing ↵ in the palette does. “Copy to clipboard” sets the clip as the latest entry so you can paste it yourself. ⌘C always copies without pasting.")
            }

            Section("Shortcuts") {
                ShortcutSettingRow(title: "Quick Clipboard", name: .commandPalette)
                ShortcutSettingRow(title: "Library", name: .openLibrary)
            }

            Section {
                Toggle("Enable semantic search", isOn: $settings.semanticSearchEnabled)

                Picker("Embedding provider", selection: $settings.embeddingBackend) {
                    ForEach(EmbeddingBackend.allCases) { backend in
                        Text(backend.displayName).tag(backend)
                    }
                }
                .disabled(!settings.semanticSearchEnabled)

                if settings.embeddingBackend == .ollama {
                    LabeledContent("Local Ollama URL") {
                        TextField("http://localhost:11434", text: $settings.ollamaBaseURL)
                            .multilineTextAlignment(.trailing)
                    }
                    .disabled(!settings.semanticSearchEnabled)

                    LabeledContent("Embedding model") {
                        TextField("model name", text: $settings.ollamaEmbeddingModel)
                            .multilineTextAlignment(.trailing)
                    }
                    .disabled(!settings.semanticSearchEnabled)
                }
            } header: {
                Text("Semantic Search")
            } footer: {
                Text("Uses Apple’s on-device Natural Language embeddings by default. Natural-language queries with 4+ words combine semantic and keyword search. Switch to Ollama for custom embedding models.")
            }

            Section {
                Toggle("Enable AI metadata", isOn: $settings.aiMetadataEnabled)

                LabeledContent("Groq API key") {
                    GroqAPIKeyField(settings: settings)
                }
                .disabled(!settings.aiMetadataEnabled)

                LabeledContent("Groq model") {
                    TextField("model name", text: $settings.groqModel)
                        .multilineTextAlignment(.trailing)
                }
                .disabled(!settings.aiMetadataEnabled)

                LabeledContent("Ollama URL (fallback)") {
                    TextField("http://localhost:11434", text: $settings.ollamaBaseURL)
                        .multilineTextAlignment(.trailing)
                }
                .disabled(!settings.aiMetadataEnabled)

                LabeledContent("Ollama chat model (fallback)") {
                    TextField("model name", text: $settings.ollamaChatModel)
                        .multilineTextAlignment(.trailing)
                }
                .disabled(!settings.aiMetadataEnabled)
            } header: {
                Text("AI Metadata")
            } footer: {
                Text("Generates titles, summaries, and tags for text clips. Groq is used when an API key is set; otherwise a local Ollama server is tried. Remote Ollama URLs are ignored. Short clips use fast rules without calling a model.")
            }

            Section {
                Toggle("Enable screenshot OCR", isOn: $settings.ocrEnabled)
            } header: {
                Text("Screenshot OCR")
            } footer: {
                Text("Extracts text from captured screenshots so you can search for words visible in images. Runs on-device using Apple Vision.")
            }

            Section {
                StatusRow(
                    title: "Accessibility",
                    isOK: PasteController.isAccessibilityTrusted,
                    okText: "Granted",
                    notOKText: "Not granted"
                ) {
                    if !PasteController.isAccessibilityTrusted {
                        Button("Open System Settings") {
                            openAccessibilitySettings()
                        }
                        .controlSize(.small)
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("Accessibility is required to paste into other apps with simulated ⌘V.")
            }

            Section("Data") {
                Button("Clear History…", role: .destructive) {
                    showClearHistoryConfirmation = true
                }

                Button("Empty Trash…", role: .destructive) {
                    showEmptyTrashConfirmation = true
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 440, minHeight: 480)
        .navigationTitle("Settings")
        .confirmationDialog(
            "Clear History?",
            isPresented: $showClearHistoryConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) {
                appModel.clearHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all active clips. Favorites in trash are not affected.")
        }
        .confirmationDialog(
            "Empty Trash?",
            isPresented: $showEmptyTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("Empty Trash", role: .destructive) {
                appModel.emptyTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes all trashed clips and their associated files.")
        }
    }

    private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// A settings row that shows a shortcut as keycaps with an inline "Change" affordance
/// that reveals the native recorder only while editing.
private struct ShortcutSettingRow: View {
    let title: String
    let name: KeyboardShortcuts.Name
    @State private var isEditing = false

    var body: some View {
        LabeledContent(title) {
            if isEditing {
                HStack(spacing: 8) {
                    KeyboardShortcuts.Recorder(for: name)
                    Button("Done") { isEditing = false }
                        .controlSize(.small)
                }
            } else {
                HStack(spacing: 8) {
                    ShortcutKeycapView(name: name)
                    Button("Change") { isEditing = true }
                        .controlSize(.small)
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}

/// A status row with a leading colored indicator and an optional trailing accessory,
/// laid out so the indicator never stretches.
private struct StatusRow<Accessory: View>: View {
    let title: String
    let isOK: Bool
    let okText: String
    let notOKText: String
    @ViewBuilder var accessory: Accessory

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Label(isOK ? okText : notOKText, systemImage: isOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isOK ? .green : .orange)
                    .labelStyle(.titleAndIcon)
                accessory
            }
        }
    }
}

private struct GroqAPIKeyField: View {
    @ObservedObject var settings: ClipMindSettings
    @State private var draftKey = ""
    @State private var originalKey = ""
    @State private var isRevealed = false
    @State private var saveError: String?

    private var isDirty: Bool { draftKey != originalKey }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                Group {
                    if isRevealed {
                        TextField("sk-…", text: $draftKey)
                    } else {
                        SecureField("sk-…", text: $draftKey)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 200)
                .onSubmit { saveKey() }

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(isRevealed ? "Hide key" : "Reveal key")
            }

            HStack(spacing: 8) {
                if settings.hasGroqAPIKey {
                    Label("Configured", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Not set", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button("Save") { saveKey() }
                    .controlSize(.small)
                    .disabled(!isDirty || draftKey.isEmpty)

                if settings.hasGroqAPIKey {
                    Button("Clear", role: .destructive) { clearKey() }
                        .controlSize(.small)
                }
            }

            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear(perform: loadKey)
    }

    private func loadKey() {
        let current = settings.revealGroqAPIKey() ?? ""
        draftKey = current
        originalKey = current
    }

    private func saveKey() {
        do {
            try settings.saveGroqAPIKey(draftKey)
            originalKey = draftKey
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func clearKey() {
        do {
            try settings.clearGroqAPIKey()
            draftKey = ""
            originalKey = ""
            isRevealed = false
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
