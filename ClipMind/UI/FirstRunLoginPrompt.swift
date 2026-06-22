import SwiftUI

struct FirstRunLoginPrompt: ViewModifier {
    @ObservedObject var settings: ClipMindSettings
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content
            .alert("Launch ClipMind at Login?", isPresented: $isPresented) {
                Button("Launch at Login") {
                    settings.completeFirstRunLoginPrompt(enable: true)
                }
                Button("Not Now", role: .cancel) {
                    settings.completeFirstRunLoginPrompt(enable: false)
                }
            } message: {
                Text("ClipMind can start automatically when you log in so your clipboard history is always available.")
            }
    }
}

extension View {
    func firstRunLoginPrompt(settings: ClipMindSettings, isPresented: Binding<Bool>) -> some View {
        modifier(FirstRunLoginPrompt(settings: settings, isPresented: isPresented))
    }
}
