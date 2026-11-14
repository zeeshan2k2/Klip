
import AppKit
import SwiftUI

@main
struct KlipApp: App {
    @NSApplicationDelegateAdaptor(KlipAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appDelegate.coordinator.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("Show Clipboard") {
                    appDelegate.coordinator.showHistory()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}

@MainActor
final class KlipAppDelegate: NSObject, NSApplicationDelegate {
    let coordinator = AppCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyAppIcon()
        coordinator.applyFirstLaunchDefaults()
        coordinator.start()
    }

    private func applyAppIcon() {
        guard let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String else { return }
        let filename = name as NSString
        let stem = filename.deletingPathExtension
        let fileExtension = filename.pathExtension.isEmpty ? "icns" : filename.pathExtension
        guard let url = Bundle.main.url(forResource: stem, withExtension: fileExtension),
              let image = NSImage(contentsOf: url) else { return }
        // Use the packaged artwork directly while macOS refreshes its app-icon cache.
        NSApp.applicationIconImage = image
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator.showHistory()
        return true
    }
}
