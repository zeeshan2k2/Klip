import AppKit
import SwiftUI

/// The deliberate history browsing surface, separate from transient copy feedback.
@MainActor
final class HistoryPanelController: NSWindowController, NSWindowDelegate {
    let model: HistoryViewModel
    private let autosaveName: NSWindow.FrameAutosaveName
    private var localEventMonitor: Any?
    private var outsideClickMonitor: Any?

    init(model: HistoryViewModel? = nil, frameAutosaveName: NSWindow.FrameAutosaveName = "Klip.HistoryPanel") {
        let model = model ?? HistoryViewModel()
        self.model = model
        autosaveName = frameAutosaveName
        let panel = HistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: HistoryStyle.width, height: HistoryStyle.height),
            styleMask: [.borderless, .resizable, .nonactivatingPanel], backing: .buffered, defer: false
        )
        super.init(window: panel)
        panel.title = "Klip — Clipboard"
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentMinSize = NSSize(width: HistoryStyle.minimumWidth, height: HistoryStyle.minimumHeight)
        let hostingView = NSHostingView(rootView: ContentView(model: model, onDismiss: { [weak self] in
            self?.dismiss()
        }))
        // Let the window determine the layout size, rather than the view's ideal size.
        hostingView.sizingOptions = []
        // Also clip native backing layers: SwiftUI's clip alone does not contain
        // every AppKit-backed view or the separately composited backdrop.
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = HistoryStyle.cornerRadius
        hostingView.layer?.masksToBounds = true
        panel.contentView = hostingView
        panel.delegate = self
        if !panel.setFrameUsingName(autosaveName) {
            panel.center()
        }
        panel.setFrameAutosaveName(autosaveName)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        model.isPanelPresented = true
        super.showWindow(sender)
        window?.orderFrontRegardless()
        window?.makeKey()
        startDismissalMonitors()
    }

    func dismiss() {
        guard let window else { return }
        window.saveFrame(usingName: autosaveName)
        model.isPanelPresented = false
        model.inspectedItem = nil
        if let sheet = window.attachedSheet {
            window.endSheet(sheet)
        }
        window.orderOut(nil)
        stopDismissalMonitors()
    }

    func windowDidResize(_ notification: Notification) {
        window?.saveFrame(usingName: autosaveName)
        window?.invalidateShadow()
    }

    func windowDidMove(_ notification: Notification) {
        window?.saveFrame(usingName: autosaveName)
    }

    func windowWillClose(_ notification: Notification) {
        window?.saveFrame(usingName: autosaveName)
        stopDismissalMonitors()
    }

    private func startDismissalMonitors() {
        stopDismissalMonitors()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self, let panel = self.window, panel.isVisible else { return false }
                if event.type == .keyDown {
                    if event.keyCode == 53 {
                        self.dismiss()
                        return true
                    }
                    let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
                    if modifiers == .command, event.charactersIgnoringModifiers == "," {
                        self.model.onShowSettings?()
                        return true
                    }
                    if modifiers == .command, panel.attachedSheet == nil,
                       self.model.inspectedItem == nil,
                       let characters = event.charactersIgnoringModifiers,
                       let number = Int(characters), (1...9).contains(number) {
                        self.model.copyNumberedItem(number - 1)
                        return true
                    }
                    return false
                }
                // Keep the panel's own controls, preview sheet, share picker, and
                // transient popovers usable. Clicks in another main window dismiss it.
                if let target = event.window,
                   target === panel || target.parent === panel || target.sheetParent === panel || !target.canBecomeMain {
                    return false
                }
                self.dismiss()
                return false
            }
            return consumed ? nil : event
        }
    }

    private func stopDismissalMonitors() {
        if let monitor = localEventMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        localEventMonitor = nil
        outsideClickMonitor = nil
    }
}

private final class HistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
