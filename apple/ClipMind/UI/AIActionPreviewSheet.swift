import SwiftUI

struct AIActionPreviewSheet: View {
    let action: AIClipAction
    let result: String
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(action.title)
                .font(.title2.weight(.semibold))

            ScrollView {
                Text(result)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                Spacer()
                Button("Copy", action: onCopy)
                Button("Paste", action: onPaste)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 320)
    }
}

struct AIActionErrorSheet: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Label("AI Unavailable", systemImage: "exclamationmark.triangle")
                .font(.title3.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("OK", action: onDismiss)
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 360)
    }
}

struct AIActionLoadingSheet: View {
    let action: AIClipAction

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Running \(action.title)…")
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(width: 280)
    }
}
