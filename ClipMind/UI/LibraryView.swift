import SwiftUI

enum LibraryTab: Hashable {
    case clips
    case settings
}

struct LibraryView: View {
    @EnvironmentObject private var appModel: AppModel
    @Binding var selectedTab: LibraryTab
    @State private var selectedClipID: ClipboardItem.ID?
    @State private var filterSelection: LibraryFilter?

    private var selectedClip: ClipboardItem? {
        guard let selectedClipID else { return nil }
        return appModel.libraryClips.first { $0.id == selectedClipID }
    }

    private var showingSettings: Bool { selectedTab == .settings }

    var body: some View {
        Group {
            if showingSettings {
                // Settings is a focused two-column layout — no detail column.
                NavigationSplitView {
                    sidebar
                } detail: {
                    SettingsForm(settings: appModel.settings)
                        .environmentObject(appModel)
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationSplitView {
                    sidebar
                } content: {
                    timeline
                } detail: {
                    if let selectedClip {
                        ClipDetailView(item: selectedClip)
                    } else {
                        ContentUnavailableView(
                            "Select a Clip",
                            systemImage: "sidebar.right",
                            description: Text("Choose a clip from the timeline to see details and actions.")
                        )
                    }
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .onAppear {
            filterSelection = appModel.libraryFilter
            appModel.refreshLibraryClips()
        }
        .onChange(of: filterSelection) { _, newValue in
            guard let newValue else { return }
            if selectedTab != .clips { selectedTab = .clips }
            if appModel.libraryFilter != newValue {
                appModel.libraryFilter = newValue
            }
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .clips {
                filterSelection = appModel.libraryFilter
            }
        }
        .onChange(of: appModel.libraryFilter) { _, _ in
            selectedClipID = nil
            appModel.refreshLibraryClips()
        }
        .onChange(of: appModel.librarySearchQuery) { _, _ in
            appModel.refreshLibraryClips()
        }
        .alert("Accessibility Required", isPresented: $appModel.showLibraryAccessibilityAlert) {
            Button("Open System Settings") {
                if let url = URL(string: "x-apple.systemsettings:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text("Enable Accessibility for ClipMind to paste into other apps. Copy still works without it.")
        }
    }

    private var sidebar: some View {
        List(selection: $filterSelection) {
            Section("Library") {
                ForEach(LibraryFilter.allCases) { filter in
                    Label(filter.title, systemImage: filter.systemImage)
                        .tag(filter)
                }
            }
        }
        .navigationTitle("ClipMind")
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        .safeAreaInset(edge: .bottom) {
            settingsButton
        }
    }

    private var settingsButton: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                if selectedTab != .settings {
                    selectedTab = .settings
                    filterSelection = nil
                }
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                showingSettings
                    ? Color.accentColor.opacity(0.18)
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }

    private var timeline: some View {
        Group {
            if appModel.libraryClips.isEmpty {
                ContentUnavailableView(
                    emptyStateTitle,
                    systemImage: "doc.on.clipboard",
                    description: Text(emptyStateDescription)
                )
            } else {
                List(selection: $selectedClipID) {
                    ForEach(appModel.libraryClips) { item in
                        ClipRowView(item: item, isSelected: item.id == selectedClipID)
                            .environmentObject(appModel)
                            .tag(item.id)
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(appModel.libraryFilter.title)
        .searchable(text: $appModel.librarySearchQuery, placement: .toolbar, prompt: "Search in \(appModel.libraryFilter.title.lowercased())")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    appModel.refreshLibraryClips()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh")
            }
        }
    }

    private var emptyStateTitle: String {
        if appModel.libraryFilter == .trash {
            return "Trash is Empty"
        }
        if !appModel.librarySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No Results"
        }
        switch appModel.libraryFilter {
        case .images, .files:
            return "No \(appModel.libraryFilter.title) Yet"
        default:
            return "No Clips Yet"
        }
    }

    private var emptyStateDescription: String {
        if appModel.libraryFilter == .trash {
            return "Deleted clips will appear here."
        }
        if !appModel.librarySearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try a different keyword or prefix such as type:code or from:safari."
        }
        switch appModel.libraryFilter {
        case .images, .files:
            return "Copy images or files in any app and they will appear here."
        case .sensitive:
            return "Sensitive clips are hidden from default views until detected."
        case .favorites:
            return "Star clips from the palette with ⌘F or from the detail pane."
        default:
            return "Copy plain text in any app and it will appear here."
        }
    }
}

#Preview {
    let settings = ClipMindSettings()
    LibraryView(selectedTab: .constant(.clips))
        .environmentObject(AppModel(settings: settings))
}
