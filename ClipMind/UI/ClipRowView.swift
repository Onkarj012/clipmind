import AppKit
import SwiftUI

struct ClipThumbnailView: View {
    let path: String?
    var maxSize: CGFloat = 40

    var body: some View {
        Group {
            if let path, let nsImage = NSImage(contentsOfFile: path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.quaternary.opacity(0.5))
            }
        }
        .frame(width: maxSize, height: maxSize)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct ClipRowView: View {
    private static let relativeFormatter = RelativeDateTimeFormatter()

    @EnvironmentObject private var appModel: AppModel

    let item: ClipboardItem
    var isSelected = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if item.type == "image" {
                ClipThumbnailView(path: appModel.asset(for: item.id)?.thumbnailPath)
            } else if item.type == "file", let path = item.filePath {
                FileIconView(path: path, size: 40)
            }

            VStack(alignment: .leading, spacing: 6) {
                if let title = item.title, !title.isEmpty {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                }

                if item.type == "image" {
                    Text(item.preview ?? "Image")
                        .font(item.title == nil ? .body : .callout)
                        .foregroundStyle(item.title == nil ? .primary : .secondary)
                        .lineLimit(2)
                } else if item.type == "file" {
                    Text(item.fileDisplayName ?? item.preview ?? "File")
                        .font(item.title == nil ? .body : .callout)
                        .foregroundStyle(item.title == nil ? .primary : .secondary)
                        .lineLimit(2)
                } else if let summary = item.summary, !summary.isEmpty, item.title != nil {
                    Text(summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Text(item.preview ?? item.contentText ?? "")
                        .font(.body)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if appModel.isIndexing(item.id) {
                        Label("Indexing…", systemImage: "sparkles")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    ForEach(appModel.tags(for: item.id)) { tag in
                        Text(tag.name)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }

                    if !item.type.isEmpty {
                        Text(item.type.uppercased())
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }

                    if item.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }

                    if let sourceApp = item.sourceApp, !sourceApp.isEmpty {
                        HStack(spacing: 4) {
                            AppIconView(bundleId: item.sourceBundleId, size: 14)
                            Text(sourceApp)
                        }
                    }

                    Text(relativeTimestamp(for: item))
                        .foregroundStyle(.secondary)

                    if item.copyCount > 1 {
                        Text("×\(item.copyCount)")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }

                    Spacer(minLength: 0)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private func relativeTimestamp(for item: ClipboardItem) -> String {
        let date = Date(timeIntervalSince1970: item.lastUsedAt ?? item.createdAt)
        return Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
