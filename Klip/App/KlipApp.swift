
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
        coordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator.showHistory()
        return true
    }
}
