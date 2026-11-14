import AppKit
import Carbon

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let model: HistoryViewModel
    private let onShow: () -> Void
    private let onPause: () -> Void
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let statusIcon: NSImage

    init(model: HistoryViewModel, onShow: @escaping () -> Void, onPause: @escaping () -> Void) {
        self.model = model
        self.onShow = onShow
        self.onPause = onPause
        statusIcon = Self.makeStatusIcon()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        refreshIcon()
    }

    /// A vector silhouette of the brand mark, tinted by macOS for the menu bar.
    static func makeStatusIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            // Broad, chamfered paperclip with an inner return, matching the app artwork.
            let mark = NSBezierPath()
            mark.windingRule = .evenOdd
            func polygon(_ points: [NSPoint]) {
                mark.move(to: points[0])
                for point in points.dropFirst() { mark.line(to: point) }
                mark.close()
            }
            polygon([
                NSPoint(x: -1.7, y: -7.5), NSPoint(x: 1.7, y: -7.5),
                NSPoint(x: 3.2, y: -6), NSPoint(x: 3.2, y: 6),
                NSPoint(x: 1.7, y: 7.5), NSPoint(x: -1.7, y: 7.5),
                NSPoint(x: -3.2, y: 6), NSPoint(x: -3.2, y: -6)
            ])
            polygon([
                NSPoint(x: -1, y: -5.8), NSPoint(x: 1, y: -5.8),
                NSPoint(x: 1.7, y: -5.1), NSPoint(x: 1.7, y: 5.1),
                NSPoint(x: 1, y: 5.8), NSPoint(x: -1, y: 5.8),
                NSPoint(x: -1.7, y: 5.1), NSPoint(x: -1.7, y: -5.1)
            ])
            let tongue = NSBezierPath(roundedRect: NSRect(x: -0.65, y: -1.8, width: 1.3, height: 8.3),
                                      xRadius: 0.5, yRadius: 0.5)
            var transform = AffineTransform(translationByX: 9, byY: 9)
            transform.rotate(byDegrees: 36)
            mark.transform(using: transform)
            tongue.transform(using: transform)
            NSColor.black.setFill()
            mark.fill()
            tongue.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Klip clipboard"
        return image
    }

    func refreshIcon() {
        statusItem.button?.image = statusIcon
        statusItem.button?.appearsDisabled = model.privacy.isPaused
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
