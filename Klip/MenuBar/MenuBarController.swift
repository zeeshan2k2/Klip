import AppKit
import Carbon

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let model: HistoryViewModel
    private let onShow: () -> Void
    private let onPause: () -> Void
    private let statusItem: NSStatusItem
    private let menu = NSMenu()

    init(model: HistoryViewModel, onShow: @escaping () -> Void, onPause: @escaping () -> Void) {
        self.model = model
        self.onShow = onShow
        self.onPause = onPause
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        refreshIcon()
    }

    func refreshIcon() {
        let symbol = model.privacy.isPaused ? "pause.rectangle" : "doc.on.clipboard"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Klip clipboard")
        statusItem.button?.toolTip = model.privacy.isPaused ? "Klip — monitoring paused" : "Klip — clipboard history"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = add("Show Clipboard", action: #selector(show))
        if model.shortcutIssue == nil {
            open.keyEquivalent = model.preferences.historyShortcut.menuKey
            open.keyEquivalentModifierMask = model.preferences.historyShortcut.menuModifiers
        }
        if let issue = model.shortcutIssue { add(issue, action: nil).isEnabled = false }
        if let message = model.monitor?.status.message { add(message, action: nil).isEnabled = false }
        menu.addItem(.separator())
        add(model.privacy.isPaused ? "Resume Monitoring" : "Pause Monitoring", action: #selector(togglePause))
        add("Clear History (\(model.items.count))", action: #selector(clear)).isEnabled = !model.items.isEmpty
        menu.addItem(.separator())
        let feedback = add("Copy Feedback", action: nil)
        let choices = NSMenu()
        choices.autoenablesItems = false
        for (index, mode) in FeedbackMode.allCases.enumerated() {
            let choice = NSMenuItem(title: mode.label, action: #selector(selectFeedback(_:)), keyEquivalent: "")
            choice.target = self
            choice.tag = index
            choice.state = model.preferences.feedbackMode == mode ? .on : .off
            choices.addItem(choice)
        }
        feedback.submenu = choices
        menu.addItem(.separator())
        let settings = add("Settings…", action: #selector(settings))
        settings.keyEquivalent = ","
        settings.keyEquivalentModifierMask = .command
        menu.addItem(.separator())
        add("Quit Klip", action: #selector(quit)).keyEquivalent = "q"
    }

    func stop() { NSStatusBar.system.removeStatusItem(statusItem) }

    @discardableResult
    private func add(_ title: String, action: Selector?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc private func selectFeedback(_ item: NSMenuItem) {
        guard FeedbackMode.allCases.indices.contains(item.tag) else { return }
        model.preferences.feedbackMode = FeedbackMode.allCases[item.tag]
    }

    @objc private func settings() { model.onShowSettings?() }
    @objc private func show() { onShow() }
    @objc private func togglePause() { onPause() }
    @objc private func clear() { model.clearHistory() }
    @objc private func quit() { NSApp.terminate(nil) }
}

/// A registered system hotkey works without a global keyboard listener or Accessibility permission.
@MainActor
final class HistoryHotKey {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onInvoke: () -> Void

    init(onInvoke: @escaping () -> Void) { self.onInvoke = onInvoke }

    @discardableResult
    func register(shortcut: HistoryShortcut = .commandShiftV) -> Bool {
        stop()
        guard shortcut != .off else { return true }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard result == noErr, identifier.signature == 0x4B4C4950, identifier.id == 1 else { return OSStatus(eventNotHandledErr) }
            MainActor.assumeIsolated {
                Unmanaged<HistoryHotKey>.fromOpaque(context).takeUnretainedValue().onInvoke()
            }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return false }
        let identifier = EventHotKeyID(signature: 0x4B4C4950, id: 1)
        let result = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, identifier,
                                        GetApplicationEventTarget(), 0, &hotKey)
        guard result == noErr else { stop(); return false }
        return true
    }

    func stop() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}

extension HistoryShortcut {
    var keyCode: UInt32 { self == .controlShiftSpace ? UInt32(kVK_Space) : UInt32(kVK_ANSI_V) }
    var carbonModifiers: UInt32 {
        switch self {
        case .commandShiftV: UInt32(cmdKey | shiftKey)
        case .controlOptionV: UInt32(controlKey | optionKey)
        case .controlShiftSpace: UInt32(controlKey | shiftKey)
        case .off: 0
        }
    }
    var menuKey: String { self == .off ? "" : self == .controlShiftSpace ? " " : "v" }
    var menuModifiers: NSEvent.ModifierFlags {
        switch self {
        case .commandShiftV: [.command, .shift]
        case .controlOptionV: [.control, .option]
        case .controlShiftSpace: [.control, .shift]
        case .off: []
        }
    }
}
