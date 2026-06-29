import SwiftUI

@main
struct ClipMindApp: App {
    @StateObject private var settings = ClipMindSettings()
    @StateObject private var appModel: AppModel
    @State private var selectedLibraryTab: LibraryTab = .clips
    @State private var showFirstRunLoginPrompt = false

    init() {
        let settings = ClipMindSettings()
        _settings = StateObject(wrappedValue: settings)
        _appModel = StateObject(wrappedValue: AppModel(settings: settings))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(selectedLibraryTab: $selectedLibraryTab)
                .environmentObject(appModel)
                .onAppear {
                    if !appModel.settings.hasSeenLoginPrompt {
                        showFirstRunLoginPrompt = true
                    }
                }
                .firstRunLoginPrompt(settings: appModel.settings, isPresented: $showFirstRunLoginPrompt)
        } label: {
            Image(systemName: appModel.isTrackingPaused ? "pause.circle.fill" : "doc.on.clipboard")
        }
        .menuBarExtraStyle(.menu)

        Window("ClipMind Library", id: "library") {
            LibraryView(selectedTab: $selectedLibraryTab)
                .environmentObject(appModel)
                .onAppear {
                    appModel.libraryWindowDidOpen()
                }
                .background {
                    LibraryWindowObserver {
                        appModel.libraryWindowDidClose()
                    }
                }
        }
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

private struct LibraryWindowObserver: NSViewRepresentable {
    let onClose: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.observe(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.observe(window: nsView.window)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onClose: onClose)
    }

    final class Coordinator {
        private let onClose: () -> Void
        private weak var observedWindow: NSWindow?
        private var closeObserver: NSObjectProtocol?

        init(onClose: @escaping () -> Void) {
            self.onClose = onClose
        }

        deinit {
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
        }

        func observe(window: NSWindow?) {
            guard let window, window !== observedWindow else { return }
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
            }
            observedWindow = window
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [onClose] _ in
                onClose()
            }
        }
    }
}
