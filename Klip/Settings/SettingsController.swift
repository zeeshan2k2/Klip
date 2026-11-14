import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class SettingsController: NSWindowController, NSWindowDelegate {
    private let model: HistoryViewModel
    let login: LaunchAtLoginController

    init(model: HistoryViewModel, login: LaunchAtLoginController? = nil) {
        self.model = model
        self.login = login ?? LaunchAtLoginController()
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init(window: panel)
        panel.title = "Klip Settings"
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.managed, .fullScreenNone, .fullScreenDisallowsTiling]
        panel.contentMinSize = NSSize(width: 520, height: 480)
        panel.contentView = NSHostingView(rootView: SettingsView(preferences: model.preferences, model: model, login: self.login,
            onAddExclusion: { [weak self] in self?.addExcludedApplications() }))
        panel.center()
    }

    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        login.refresh()
        super.showWindow(sender)
        NSApp.activate()
        window?.makeKeyAndOrderFront(sender)
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
