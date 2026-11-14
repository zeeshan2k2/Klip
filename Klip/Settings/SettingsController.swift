import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsController: NSWindowController, NSWindowDelegate {
    private let model: HistoryViewModel
    private let activateApplication: (() -> Void)?
    let login: LaunchAtLoginController

    init(model: HistoryViewModel, login: LaunchAtLoginController? = nil, activateApplication: (() -> Void)? = nil) {
        self.model = model
        self.activateApplication = activateApplication
        self.login = login ?? LaunchAtLoginController()
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = "Klip Settings"
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.primary, .managed, .fullScreenNone, .fullScreenDisallowsTiling]
        panel.contentMinSize = NSSize(width: 520, height: 480)
        panel.contentView = NSHostingView(rootView: SettingsView(preferences: model.preferences, model: model, login: self.login,
            onAddExclusion: { [weak self] in self?.addExcludedApplications() }))
        panel.center()
    }

    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        focusWindow(sender)
        // A nonactivating history panel may leave the user in another app’s
        // fullscreen Space. Use the normal app-open activation to switch to
        // Klip’s desktop window, including when Klip is already active.
        if let activateApplication {
            activateApplication()
        } else if Bundle.main.bundleURL.pathExtension == "app" {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] _, error in
                guard error == nil else { return }
                Task { @MainActor in
                    guard let self, self.window?.isVisible == true else { return }
                    self.focusWindow()
                }
            }
        }
    }

    func focusWindow(_ sender: Any? = nil) {
        login.refresh()
        guard let window else { return }
        if window.isMiniaturized { window.deminiaturize(sender) }
        super.showWindow(sender)
        NSApp.activate(ignoringOtherApps: true)
        window.makeMain()
        window.makeKeyAndOrderFront(sender)
    }

    func windowDidBecomeKey(_ notification: Notification) { login.refresh() }

    private func addExcludedApplications() {
        guard let window else { return }
        let picker = NSOpenPanel()
        picker.title = "Exclude Applications"
        picker.prompt = "Exclude"
        picker.allowedContentTypes = [.applicationBundle]
        picker.canChooseDirectories = false
        picker.canChooseFiles = true
        picker.allowsMultipleSelection = true
        picker.directoryURL = URL(fileURLWithPath: "/Applications")
        picker.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                let identifiers = picker.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
                self.model.preferences.excludedApplicationIDs = Array(Set(self.model.preferences.excludedApplicationIDs + identifiers)).sorted()
            }
        }
    }
}
