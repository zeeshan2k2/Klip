import AppKit

@MainActor
final class AppCoordinator {
    let history: ClipboardHistoryStore
    let model: HistoryViewModel
    private let writer: ClipboardWriter
    private let monitor: ClipboardMonitor
    private let historyPanel: HistoryPanelController
    private let feedback: FeedbackController
    private let login = LaunchAtLoginController()
    private var settingsPanel: SettingsController?
    private var menuBar: MenuBarController?
    private var hotKey: HistoryHotKey?
    private var registeredShortcut: HistoryShortcut?
    private var started = false

    init(preferences suppliedPreferences: PreferencesStore? = nil,
         persistence suppliedPersistence: HistoryPersisting? = nil,
         pasteboard: NSPasteboard? = nil,
         sourceApplication: (() -> String?)? = nil) {
        let preferences = suppliedPreferences ?? PreferencesStore()
        let pasteboard = pasteboard ?? .general
        let history = ClipboardHistoryStore(capacity: preferences.historyLimit,
            persistence: suppliedPersistence ?? JSONHistoryPersistence(), persistenceEnabled: preferences.saveHistory, maxAge: preferences.maximumAge)
        let privacy = PrivacyPolicy()
        privacy.isPaused = preferences.monitoringPaused
        privacy.excludedApplicationIDs = Set(preferences.excludedApplicationIDs)
        let model = HistoryViewModel(store: history, privacy: privacy, preferences: preferences)
        let feedback = FeedbackController(preferences: preferences)
        let writer = ClipboardWriter(pasteboard: pasteboard)
        self.history = history
        self.model = model
        self.writer = writer
        self.feedback = feedback
        historyPanel = HistoryPanelController(model: model)
        monitor = ClipboardMonitor(pasteboard: pasteboard, writer: writer, privacy: privacy,
            sourceApplication: sourceApplication ?? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }) { snapshot in
            feedback.clipboardDidChange(preview: preferences.hidePreviews ? nil : snapshot)
            history.record(snapshot)
            model.historyDidChange()
        }
        model.monitor = monitor
        model.onCopy = { [weak self] item in self?.copy(item) }
        model.onTogglePause = { [weak self] in self?.toggleMonitoring() }
        model.onShowSettings = { [weak self] in self?.showSettings() }
        model.onDeletion = { [weak feedback] in feedback?.historyDidDelete() }
        model.onPreviewCopySound = { [weak feedback] in feedback?.previewCopySound() }
        preferences.onSettingsChanged = { [weak self] in self?.applyPreferences() }
    }

    func applyFirstLaunchDefaults() { login.enableByDefaultIfNeeded() }

    func start() {
        guard !started else { return }
        started = true
        monitor.start()
        history.startMaintenance()
        menuBar = MenuBarController(model: model, onShow: { [weak self] in self?.showHistory() },
                                    onPause: { [weak self] in self?.toggleMonitoring() })
        hotKey = HistoryHotKey { [weak self] in self?.showHistory() }
        applyPreferences()
        showHistory()
    }

    func stop() {
        monitor.stop()
        history.maintenance()
        history.stopMaintenance()
        feedback.stop()
        hotKey?.stop()
        menuBar?.stop()
    }

    func showHistory() {
        history.maintenance()
        model.historyDidChange()
        model.query = ""
        model.selectedID = model.items.first?.id
        model.copyError = nil
        historyPanel.showWindow(nil)
        historyPanel.window?.makeKeyAndOrderFront(nil)
    }

    func showSettings() {
        historyPanel.dismiss()
        if settingsPanel == nil { settingsPanel = SettingsController(model: model, login: login) }
        settingsPanel?.showWindow(nil)
    }

    private func applyPreferences() {
        let preferences = model.preferences
        feedback.applySoundPreferences()
        let changed = model.privacy.isPaused != preferences.monitoringPaused
            || model.privacy.excludedApplicationIDs != Set(preferences.excludedApplicationIDs)
        model.privacy.isPaused = preferences.monitoringPaused
        model.privacy.excludedApplicationIDs = Set(preferences.excludedApplicationIDs)
        if changed { monitor.rebaseline() }
        if preferences.monitoringPaused || preferences.hidePreviews { feedback.dismissCurrentFeedback() }
        history.configure(persistenceEnabled: preferences.saveHistory, capacity: preferences.historyLimit, maxAge: preferences.maximumAge)
        model.historyDidChange()
        if let hotKey, registeredShortcut != preferences.historyShortcut {
            registeredShortcut = preferences.historyShortcut
            model.shortcutIssue = hotKey.register(shortcut: preferences.historyShortcut) ? nil
                : "Couldn’t register \(preferences.historyShortcut.label). Choose another shortcut or use the menu bar."
        }
        menuBar?.refreshIcon()
    }

    private func toggleMonitoring() {
        model.preferences.monitoringPaused.toggle()
    }

    private func copy(_ item: HistoryItem) {
        if writer.write(item.snapshot) {
            model.copyError = nil
            historyPanel.dismiss()
        } else {
            model.copyError = writer.lastError ?? "Couldn’t copy this item. Please try again."
        }
    }
}
