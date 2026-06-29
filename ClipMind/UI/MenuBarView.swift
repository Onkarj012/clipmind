import SwiftUI
import KeyboardShortcuts

struct MenuBarView: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.openWindow) private var openWindow
    @Binding var selectedLibraryTab: LibraryTab

    var body: some View {
        Group {
            Button("Open Library") {
                openLibrary(tab: .clips)
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
            Text("\(shortcutLabel(for: .commandPalette))  Command palette")
                .font(.caption)
            Text("\(shortcutLabel(for: .openLibrary))  Library window")
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
        openLibrary(tab: .settings)
    }

    private func openLibrary(tab: LibraryTab = .clips) {
        selectedLibraryTab = tab
        appModel.libraryWillOpen()
        openWindow(id: "library")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func shortcutLabel(for name: KeyboardShortcuts.Name) -> String {
        KeyboardShortcuts.getShortcut(for: name).map { "\($0)" } ?? "Not set"
    }
}
