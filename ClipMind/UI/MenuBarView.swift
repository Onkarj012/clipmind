import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Button("Open Library") {
                openLibrary()
            }
            Button(appModel.isTrackingPaused ? "Resume Tracking" : "Pause Tracking") {
                appModel.toggleTrackingPause()
            }

            Button("Settings…") {
                openSettings()
            }

            Divider()

            Text("Shortcuts")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("⌘⇧V  Command palette")
                .font(.caption)
            Text("⌘⇧L  Library window")
                .font(.caption)

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .onAppear {
            appModel.setOpenLibraryHandler(openLibrary)
        }
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openLibrary() {
        openWindow(id: "library")
        NSApp.activate(ignoringOtherApps: true)
    }
}
