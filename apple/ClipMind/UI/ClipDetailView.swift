import SwiftUI

struct ClipDetailView: View {
    @EnvironmentObject private var appModel: AppModel

    let item: ClipboardItem

    @State private var activeAIAction: AIClipAction?
    @State private var aiActionResult: String?
    @State private var aiActionError: String?
    @State private var isRunningAIAction = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let title = item.title, !title.isEmpty {
                    Text(title)
                        .font(.title2.weight(.semibold))
                }

                if let summary = item.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.body)
                        .foregroundStyle(.secondary)
                }

                if !appModel.tags(for: item.id).isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(appModel.tags(for: item.id)) { tag in
                            Text(tag.name)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }

                if appModel.isIndexing(item.id) {
                    Label("Indexing metadata…", systemImage: "sparkles")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                contentSection
                similarClipsSection
                metadataSection
                actionsSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(item.title ?? item.preview ?? "Clip Detail")
        .sheet(item: $activeAIAction) { action in
            if let result = aiActionResult {
                AIActionPreviewSheet(
                    action: action,
                    result: result,
                    onCopy: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result, forType: .string)
                    },
                    onPaste: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result, forType: .string)
                        switch PasteController.pasteText(result) {
                        case .accessibilityRequired:
                            aiActionError = "Accessibility permission is required to paste into other apps."
                            dismissAIActionSheet()
                        case .noContent:
                            aiActionError = "Could not place the transformed text on the clipboard."
                            dismissAIActionSheet()
                        case .pasted, .copiedOnly:
                            dismissAIActionSheet()
                        }
                    },
                    onCancel: dismissAIActionSheet
                )
            } else if isRunningAIAction {
                AIActionLoadingSheet(action: action)
            }
        }
        .alert("AI Unavailable", isPresented: Binding(
            get: { aiActionError != nil },
            set: { if !$0 { aiActionError = nil } }
        )) {
            Button("OK", role: .cancel) { aiActionError = nil }
        } message: {
            Text(aiActionError ?? "No AI provider is available.")
        }
    }

    private func dismissAIActionSheet() {
        activeAIAction = nil
        aiActionResult = nil
        isRunningAIAction = false
    }

    private var supportsAIActions: Bool {
        (item.type == "text" || item.type == "code")
            && !item.isSensitive
            && !(item.contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private var similarClipsSection: some View {
        let similar = appModel.similarClips(for: item)
        if !similar.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Similar Clips")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(similar) { clip in
                    NavigationLink {
                        ClipDetailView(item: clip)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(clip.title ?? clip.preview ?? "Clip")
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                            if let summary = clip.summary, !summary.isEmpty {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Content")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if item.type == "image" {
                imageContentSection
            } else if item.type == "file" {
                fileContentSection
            } else {
                Text(item.contentText ?? item.preview ?? "")
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private var imageContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ClipThumbnailView(
                path: appModel.asset(for: item.id)?.thumbnailPath,
                maxSize: 320
            )

            if let asset = appModel.asset(for: item.id) {
                Text("\(asset.width) × \(asset.height) pixels")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(asset.mimeType)
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if let ocrText = asset.ocrText, !ocrText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Extracted Text")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(ocrText)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                    .padding(.top, 4)
                }
            } else {
                Text(item.preview ?? "Image")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private var fileContentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let path = item.filePath {
                FileIconView(path: path, size: 64)
            }

            if let name = item.fileDisplayName {
                Text(name)
                    .font(.headline)
            }

            if let path = item.filePath {
                Text(path)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Metadata")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                metadataRow("Type", value: item.type.uppercased())
                metadataRow("Source App", value: item.sourceApp ?? "—")
                metadataRow("Bundle ID", value: item.sourceBundleId ?? "—")
                if item.type == "image", let asset = appModel.asset(for: item.id) {
                    metadataRow("Dimensions", value: "\(asset.width) × \(asset.height)")
                    metadataRow("Format", value: asset.mimeType)
                }
                metadataRow("Created", value: formatted(date: item.createdAt))
                metadataRow("Last Used", value: item.lastUsedAt.map { formatted(date: $0) } ?? "—")
                metadataRow("Copy Count", value: "\(item.copyCount)")
                metadataRow("Favorite", value: item.isFavorite ? "Yes" : "No")
                metadataRow("Sensitive", value: item.isSensitive ? "Yes" : "No")
            }
            .font(.callout)
        }
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if supportsAIActions {
                Menu {
                    ForEach(AIClipAction.allCases) { action in
                        Button {
                            runAIAction(action)
                        } label: {
                            Label(action.title, systemImage: action.systemImage)
                        }
                    }
                } label: {
                    Label("AI Actions", systemImage: "sparkles")
                }
                .menuStyle(.borderlessButton)
            }

            HStack(spacing: 12) {
            Button("Copy") {
                appModel.copyClip(item)
            }

            Button("Paste") {
                appModel.pasteClip(item)
            }
            .keyboardShortcut(.return, modifiers: .command)

            Button(item.isFavorite ? "Unfavorite" : "Favorite") {
                appModel.toggleFavorite(item)
            }

            if item.isDeleted {
                Button("Restore") {
                    appModel.restoreClip(item)
                }
            } else {
                Button("Delete", role: .destructive) {
                    appModel.softDeleteClip(item)
                }
            }
            }
        }
    }

    private func runAIAction(_ action: AIClipAction) {
        guard let text = item.contentText else { return }
        activeAIAction = action
        aiActionResult = nil
        aiActionError = nil
        isRunningAIAction = true

        Task {
            do {
                let result = try await appModel.runAIAction(action, on: text)
                await MainActor.run {
                    aiActionResult = result
                    isRunningAIAction = false
                }
            } catch {
                await MainActor.run {
                    aiActionError = error.localizedDescription
                    dismissAIActionSheet()
                }
            }
        }
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func formatted(date: TimeInterval) -> String {
        Self.dateFormatter.string(from: Date(timeIntervalSince1970: date))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
