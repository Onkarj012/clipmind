import AppKit
import SwiftUI

@MainActor
final class FloatingPanelManager: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    private var onClose: (() -> Void)?
    private var escapeMonitor: Any?

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func show<Content: View>(
        content: Content,
        size: CGSize,
        onClose: @escaping () -> Void
    ) {
        self.onClose = onClose

        if let panel, panel.isVisible {
            panel.close()
        }

        let root = AnyView(content)
        let controller = NSHostingController(rootView: root)
        controller.view.frame = CGRect(origin: .zero, size: size)
        hostingController = controller

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.delegate = self
        panel.contentViewController = controller
        panel.setContentSize(size)

        positionCentered(panel: panel, size: size)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
        installEscapeMonitor(for: panel)
    }

    func hide() {
        removeEscapeMonitor()
        panel?.close()
        panel = nil
        hostingController = nil
        onClose?()
        onClose = nil
    }

    func toggle<Content: View>(
        content: Content,
        size: CGSize,
        onClose: @escaping () -> Void
    ) {
        if isVisible {
            hide()
        } else {
            show(content: content, size: size, onClose: onClose)
        }
    }

    func windowWillClose(_ notification: Notification) {
        removeEscapeMonitor()
        panel = nil
        hostingController = nil
        onClose?()
        onClose = nil
    }

    private func installEscapeMonitor(for panel: NSPanel) {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, panel.isKeyWindow, event.keyCode == 53 else {
                return event
            }
            self.hide()
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }

    private func positionCentered(panel: NSPanel, size: CGSize) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let screen else { return }

        let visible = screen.visibleFrame
        let origin = CGPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }
}
