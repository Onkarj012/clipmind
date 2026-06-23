import SwiftUI

@main
struct ClipMindApp: App {
    @StateObject private var settings = ClipMindSettings()
    @StateObject private var appModel: AppModel
    @State private var showFirstRunLoginPrompt = false

    init() {
        let settings = ClipMindSettings()
        _settings = StateObject(wrappedValue: settings)
        _appModel = StateObject(wrappedValue: AppModel(settings: settings))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
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
            LibraryView()
                .environmentObject(appModel)
        }
        .defaultSize(width: 960, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Window("Settings", id: "settings") {
            SettingsView()
                .environmentObject(appModel)
        }
        .defaultSize(width: 480, height: 520)
    }
}
