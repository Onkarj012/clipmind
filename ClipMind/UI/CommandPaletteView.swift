import SwiftUI

enum CommandPaletteMetrics {
    static let width: CGFloat = 720
    static let height: CGFloat = 520
    static let resultsWidth: CGFloat = 380
}

struct CommandPaletteView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            HStack(spacing: 0) {
                resultsList
                Divider()
                previewPanel
            }
        }
        .frame(width: CommandPaletteMetrics.width, height: CommandPaletteMetrics.height)
        .clipMindGlass()
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .top) {
            if appModel.showAccessibilityBanner {
                accessibilityBanner
            }
        }
        .onAppear {
            appModel.refreshPaletteClips()
        }
        .onChange(of: appModel.paletteQuery) { _, _ in
            appModel.refreshPaletteClips()
            appModel.paletteSelectedIndex = 0
        }
        .onExitCommand {
            appModel.hideCommandPalette()
        }
        .background(
            PaletteKeyHandler(
                onCopy: { appModel.copySelectedPaletteClip() },
                onFavorite: { appModel.toggleFavoriteSelectedPaletteClip() },
                onDelete: { appModel.deleteSelectedPaletteClip() },
                onEscape: { appModel.hideCommandPalette() }
            )
        )
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
            PaletteSearchField(
                text: $appModel.paletteQuery,
                focusToken: appModel.paletteFocusToken,
                placeholder: "Search clips (type:code, from:safari, is:sensitive)",
                onMoveSelection: { appModel.movePaletteSelection(delta: $0) },
                onSubmit: { appModel.pasteSelectedPaletteClip() }
            )
            .frame(height: 32)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if appModel.paletteClips.isEmpty {
                        ContentUnavailableView(
                            "No Results",
                            systemImage: "doc.on.clipboard",
                            description: Text("Try another keyword or prefix.")
                        )
                        .frame(maxWidth: .infinity, minHeight: 280)
                    } else {
                        ForEach(Array(appModel.paletteClips.enumerated()), id: \.element.id) { index, item in
                            ClipRowView(item: item, isSelected: index == appModel.paletteSelectedIndex)
                                .environmentObject(appModel)
                                .id(item.id)
                                .onTapGesture {
                                    appModel.paletteSelectedIndex = index
                                    appModel.pasteSelectedPaletteClip()
                                }
                        }
                    }
                }
                .padding(10)
            }
            .frame(width: CommandPaletteMetrics.resultsWidth)
            .onChange(of: appModel.paletteSelectedIndex) { _, newIndex in
                guard appModel.paletteClips.indices.contains(newIndex) else { return }
                proxy.scrollTo(appModel.paletteClips[newIndex].id, anchor: .center)
            }
        }
    }

    private var previewPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let item = appModel.selectedPaletteClip {
                Text("Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView {
                    if item.type == "image" {
                        imagePreview(for: item)
                    } else if item.type == "file" {
                        filePreview(for: item)
                    } else {
                        Text(item.contentText ?? item.preview ?? "")
                            .font(.body.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }

                Spacer(minLength: 0)

                paletteFooter(for: item)
            } else {
                Spacer()
                Text("Select a clip to preview")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func imagePreview(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ClipThumbnailView(
                path: appModel.asset(for: item.id)?.thumbnailPath,
                maxSize: 280
            )
            .frame(maxWidth: .infinity)

            if let asset = appModel.asset(for: item.id) {
                Text("\(asset.width) × \(asset.height) · \(asset.mimeType)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(item.preview ?? "Image")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func filePreview(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let path = item.filePath {
                FileIconView(path: path, size: 64)
                    .frame(maxWidth: .infinity)
            }

            if let name = item.fileDisplayName {
                Text(name)
                    .font(.headline)
            }

            if let path = item.filePath {
                Text(path)
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func paletteFooter(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let sourceApp = item.sourceApp {
                Label(sourceApp, systemImage: "app")
                    .font(.caption)
            }
            Text("↑↓ navigate · ↵ paste · ⌘C copy · ⌘F favorite · ⌘⌫ delete · esc close")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private var accessibilityBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
            Text("Enable Accessibility for ClipMind in System Settings to paste into other apps.")
                .font(.caption)
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            .controlSize(.small)
            Button {
                appModel.showAccessibilityBanner = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(8)
    }
}

private struct PaletteKeyHandler: NSViewRepresentable {
    let onCopy: () -> Void
    let onFavorite: () -> Void
    let onDelete: () -> Void
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = KeyCatcherView()
        view.onCopy = onCopy
        view.onFavorite = onFavorite
        view.onDelete = onDelete
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? KeyCatcherView else { return }
        view.onCopy = onCopy
        view.onFavorite = onFavorite
        view.onDelete = onDelete
        view.onEscape = onEscape
    }
}

private final class KeyCatcherView: NSView {
    var onCopy: (() -> Void)?
    var onFavorite: (() -> Void)?
    var onDelete: (() -> Void)?
    var onEscape: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.keyCode {
        case 53: onEscape?()
        case 51 where flags.contains(.command): onDelete?()
        case 8 where flags.contains(.command): onCopy?()
        default:
            if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "f" {
                onFavorite?()
            } else if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "c" {
                onCopy?()
            } else {
                super.keyDown(with: event)
            }
        }
    }
}
