import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        SettingsForm(settings: appModel.settings)
            .environmentObject(appModel)
    }
}

private struct SettingsForm: View {
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

            Section("Paste") {
                Toggle("Keep palette open after paste", isOn: $settings.keepPaletteOpenAfterPaste)
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
                    TextField("Local Ollama URL", text: $settings.ollamaBaseURL)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!settings.semanticSearchEnabled)

                    TextField("Embedding model", text: $settings.ollamaEmbeddingModel)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!settings.semanticSearchEnabled)
                }
            } header: {
                Text("Semantic Search")
            } footer: {
                Text("Uses Apple’s on-device Natural Language embeddings by default. Natural-language queries with 4+ words combine semantic and keyword search. Switch to Ollama for custom embedding models.")
            }

            Section {
                Toggle("Enable AI metadata", isOn: $settings.aiMetadataEnabled)

                HStack {
                    Label(
                        settings.hasGroqAPIKey ? "Groq configured" : "Groq API key missing",
                        systemImage: settings.hasGroqAPIKey ? "checkmark.circle.fill" : "exclamationmark.circle"
                    )
                    .foregroundStyle(settings.hasGroqAPIKey ? .green : .secondary)
                }
                .disabled(!settings.aiMetadataEnabled)

                GroqAPIKeyField(settings: settings)
                    .disabled(!settings.aiMetadataEnabled)

                TextField("Groq model", text: $settings.groqModel)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!settings.aiMetadataEnabled)

                    TextField("Local Ollama URL (fallback)", text: $settings.ollamaBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!settings.aiMetadataEnabled)

                TextField("Ollama chat model (fallback)", text: $settings.ollamaChatModel)
                    .textFieldStyle(.roundedBorder)
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
                HStack {
                    Label(
                        PasteController.isAccessibilityTrusted ? "Granted" : "Not granted",
                        systemImage: PasteController.isAccessibilityTrusted ? "checkmark.circle.fill" : "xmark.circle.fill"
                    )
                    .foregroundStyle(PasteController.isAccessibilityTrusted ? .green : .orange)

                    Spacer()

                    if !PasteController.isAccessibilityTrusted {
                        Button("Open System Settings") {
                            openAccessibilitySettings()
                        }
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
        .frame(minWidth: 420, minHeight: 460)
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

private struct GroqAPIKeyField: View {
    @ObservedObject var settings: ClipMindSettings
    @State private var draftKey = ""
    @State private var saveError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SecureField("Groq API key", text: $draftKey)
                .textFieldStyle(.roundedBorder)
                .onSubmit { saveKey() }
                .onAppear {
                    draftKey = settings.hasGroqAPIKey ? "••••••••" : ""
                }

            HStack {
                Button("Save Key") { saveKey() }
                    .disabled(draftKey.isEmpty || draftKey == "••••••••")

                if settings.hasGroqAPIKey {
                    Button("Clear Key", role: .destructive) {
                        do {
                            try settings.clearGroqAPIKey()
                            draftKey = ""
                            saveError = nil
                        } catch {
                            saveError = error.localizedDescription
                        }
                    }
                }
            }

            if let saveError {
                Text(saveError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func saveKey() {
        guard draftKey != "••••••••" else { return }
        do {
            try settings.saveGroqAPIKey(draftKey)
            draftKey = settings.hasGroqAPIKey ? "••••••••" : ""
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
