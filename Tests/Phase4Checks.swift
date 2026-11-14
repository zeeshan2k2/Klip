import AppKit
import Darwin
import ServiceManagement
import SwiftUI

@MainActor
private final class FailingPersistence: HistoryPersisting {
    var stored: [HistoryItem] = []
    var failLoad = false
    var failSave = false
    var failDelete = false
    var loads = 0
    func load() throws -> [HistoryItem] {
        loads += 1
        if failLoad { throw CocoaError(.fileReadCorruptFile) }
        return stored
    }
    func save(_ items: [HistoryItem]) throws {
        if failSave { throw CocoaError(.fileWriteNoPermission) }
        stored = items
    }
    func delete() throws {
        if failDelete { throw CocoaError(.fileWriteNoPermission) }
        stored = []
    }
}

@MainActor
private final class LoginFixture: LoginItemManaging {
    var status: SMAppService.Status = .notRegistered
    var fail = false
    var registrations = 0
    func register() throws {
        if fail { throw CocoaError(.fileWriteNoPermission) }
        registrations += 1
        status = .requiresApproval
    }
    func unregister() throws {
        if fail { throw CocoaError(.fileWriteNoPermission) }
        status = .notRegistered
    }
}

/// Isolated defaults, temporary files, fake login registration, and named pasteboards only.
@main
struct Phase4Checks {
    @MainActor
    static func main() throws {
        setbuf(stdout, nil)
        if CommandLine.arguments.count == 3 {
            try childProcess(mode: CommandLine.arguments[1], directory: URL(fileURLWithPath: CommandLine.arguments[2]))
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Klip.Phase4.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "Klip.Phase4.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let legacySuite = "Klip.LegacyLimit.\(UUID().uuidString)"
        let legacyDefaults = UserDefaults(suiteName: legacySuite)!
        defer { legacyDefaults.removePersistentDomain(forName: legacySuite) }
        legacyDefaults.set(500, forKey: "Klip.historyLimit")
        let upgraded = PreferencesStore(defaults: legacyDefaults)
        try check(upgraded.historyLimit == 1000)
        upgraded.historyLimit = 500
        try check(PreferencesStore(defaults: legacyDefaults).historyLimit == 500)
        let preferences = PreferencesStore(defaults: defaults)
        try check(preferences.saveHistory && preferences.historyLimit == 1000 && preferences.retentionDays == 0 && preferences.maximumAge == nil)
        try check(preferences.feedbackMode == .visual && preferences.historyShortcut == .commandShiftV)
        try check(preferences.expandedPreviewDuration == 1.0)
        try check(preferences.autoExpandCopyPreview && preferences.popupDuration == 1.0)
        preferences.autoExpandCopyPreview = false
        try check(!PreferencesStore(defaults: defaults).autoExpandCopyPreview, "Explicit preview-off must survive relaunch")
        preferences.autoExpandCopyPreview = true
        preferences.saveHistory = false
        try check(!PreferencesStore(defaults: defaults).saveHistory, "An explicit history-off choice must survive relaunch")
        preferences.saveHistory = true
        preferences.historyLimit = 250
        preferences.retentionDays = 30
        preferences.monitoringPaused = true
        preferences.hidePreviews = true
        preferences.feedbackMode = .both
        preferences.popupDuration = 2.2
        preferences.expandedPreviewDuration = 7.5
        preferences.excludedApplicationIDs = ["test.excluded"]
        preferences.historyShortcut = .controlOptionV
        preferences.appearance = .dark
        let restoredPreferences = PreferencesStore(defaults: defaults)
        try check(restoredPreferences.saveHistory && restoredPreferences.historyLimit == 250 && restoredPreferences.retentionDays == 30)
        try check(restoredPreferences.monitoringPaused && restoredPreferences.hidePreviews && restoredPreferences.feedbackMode == .both)
        try check(restoredPreferences.expandedPreviewDuration == 7.5)
        try check(restoredPreferences.autoExpandCopyPreview)
        try check(restoredPreferences.popupDuration == 2.2 && restoredPreferences.excludedApplicationIDs == ["test.excluded"])
        try check(restoredPreferences.historyShortcut == .controlOptionV && restoredPreferences.appearance == .dark)
        preferences.expandedPreviewDuration = 100
        try check(preferences.expandedPreviewDuration == 30)
        preferences.expandedPreviewDuration = -1
        try check(preferences.expandedPreviewDuration == 1)
        preferences.expandedPreviewDuration = .nan
        try check(preferences.expandedPreviewDuration == 1.0)
        preferences.historyLimit = 1001
        try check(preferences.historyLimit == 1000)
        preferences.historyLimit = -1
        preferences.retentionDays = -1
        preferences.popupDuration = .infinity
        try check(preferences.historyLimit == 1 && preferences.retentionDays == 0 && preferences.popupDuration == 1.0)
        print("PASS: first-launch saving and explicit opt-out, saved settings, and invalid preference bounds")

        // Launch two separate executables to verify save/restore across process exit.
        for mode in ["--write", "--verify"] {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = [mode, directory.path]
            try child.run()
            child.waitUntilExit()
            try check(child.terminationStatus == 0, "Cross-process save/restore failed")
        }
        print("PASS: separate-process history restore, exact content/order/identity/time, and minimal saved metadata")

        var date = Date(timeIntervalSince1970: 1_800_000_000)
        func snapshot(_ text: String, age: TimeInterval = 0) -> ClipboardSnapshot {
            ClipboardSnapshot(content: text, kind: ContentClassifier().classify(text), changeCount: 42,
                              capturedAt: date.addingTimeInterval(-age), sourceApplicationID: "not-to-be-persisted")
        }
        let archive = JSONHistoryPersistence(fileURL: directory.appendingPathComponent("retention/History.json"))
        let thousandArchive = JSONHistoryPersistence(fileURL: directory.appendingPathComponent("thousand.json"))
        let thousandItems = (0..<1000).map { HistoryItem(snapshot: snapshot("Entry \($0)")) }
        try thousandArchive.save(thousandItems)
        let thousandReloaded = try thousandArchive.load()
        try check(thousandReloaded.map(\.id) == thousandItems.map(\.id))
        try check(ClipboardHistoryStore(items: thousandItems).items.count == 1000)
        var rejectedOverflow = false
        do { try thousandArchive.save(thousandItems + [HistoryItem(snapshot: snapshot("overflow"))]) }
        catch { rejectedOverflow = true }
        try check(rejectedOverflow)
        print("PASS: 1000-item default capacity and exact archive round trip, with oversized archives rejected")
        try archive.save([HistoryItem(snapshot: snapshot("fresh", age: 3)), HistoryItem(snapshot: snapshot("expired", age: 20))])
        let retained = ClipboardHistoryStore(persistence: archive, persistenceEnabled: true, maxAge: 10, now: { date })
        try check(try retained.items.map(\.content) == ["fresh"] && (try archive.load()).map(\.content) == ["fresh"])
        retained.record(snapshot("newer"))
        retained.record(snapshot("latest"))
        retained.configure(persistenceEnabled: true, capacity: 2, maxAge: 10)
        try check(try retained.items.map(\.content) == ["latest", "newer"] && (try archive.load()).count == 2)
        let oldID = retained.items[0].id
        date.addTimeInterval(8)
        retained.record(snapshot("latest"))
        try check(retained.items[0].id == oldID && retained.items[0].snapshot.capturedAt == date,
               "Consecutive copies should refresh retention without adding another entry")
        date.addTimeInterval(5)
        retained.maintenance()
        try check(retained.items.map(\.content) == ["latest"])
        date.addTimeInterval(6)
        retained.startMaintenance(interval: 0.02)
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        retained.stopMaintenance()
        try check(retained.items.isEmpty && !FileManager.default.fileExists(atPath: archive.fileURL.path))
        print("PASS: expiration on load, immediate count changes, repeat-copy timestamp refresh, and timer-driven disk expiration")

        retained.record(snapshot("delete me"))
        retained.remove(retained.items[0])
        try check(try archive.load().isEmpty)
        retained.record(snapshot("clear me"))
        retained.clear()
        try check(try archive.load().isEmpty)
        retained.record(snapshot("keep in memory"))
        retained.configure(persistenceEnabled: false, capacity: 100, maxAge: nil)
        try check(retained.items.count == 1 && !FileManager.default.fileExists(atPath: archive.fileURL.path))
        retained.record(snapshot("memory only"))
        try check(!FileManager.default.fileExists(atPath: archive.fileURL.path))
        retained.configure(persistenceEnabled: true, capacity: 100, maxAge: nil)
        try check((try archive.load()).map(\.content) == ["memory only", "keep in memory"])
        let offStore = ClipboardHistoryStore(persistence: archive, persistenceEnabled: false)
        try check(offStore.items.isEmpty && !FileManager.default.fileExists(atPath: archive.fileURL.path))
        print("PASS: durable item deletion/clear, disable deletion, in-memory continuation, explicit re-enable, and disabled startup cleanup")

        let badURL = directory.appendingPathComponent("corrupt.json")
        let corrupt = Data("not JSON".utf8)
        try corrupt.write(to: badURL)
        let badArchive = JSONHistoryPersistence(fileURL: badURL)
        let damaged = ClipboardHistoryStore(persistence: badArchive, persistenceEnabled: true)
        try check(damaged.loadBlocked && damaged.storageError != nil && damaged.items.isEmpty)
        damaged.record(snapshot("new in-memory content"))
        try check(try Data(contentsOf: badURL) == corrupt, "Do not silently overwrite an unreadable archive")
        damaged.clear()
        try check(!damaged.loadBlocked && damaged.storageError == nil)
        damaged.record(snapshot("recovered"))
        try check((try badArchive.load()).first?.content == "recovered")
        let failures = FailingPersistence()
        failures.failSave = true
        let failing = ClipboardHistoryStore(persistence: failures, persistenceEnabled: true)
        failing.record(snapshot("write failure"))
        try check(failing.storageError != nil && failures.stored.isEmpty && failing.items.count == 1)
        failures.failSave = false
        failing.retryStorage()
        try check(failing.storageError == nil && failures.stored.count == 1)
        failures.failDelete = true
        failing.configure(persistenceEnabled: false, capacity: 100, maxAge: nil)
        try check(failing.storageError != nil && failing.needsDeletion && failures.stored.count == 1)
        failures.failDelete = false
        failing.retryStorage()
        try check(failing.storageError == nil && failures.stored.isEmpty)
        let unread = FailingPersistence()
        unread.failLoad = true
        _ = ClipboardHistoryStore(persistence: unread, persistenceEnabled: false)
        try check(unread.loads == 0, "Storage-off startup must not read saved payloads")
        print("PASS: corrupt archive preservation/recovery, visible write/delete failures, retry, and no reads with storage off")

        let runtimeDefaults = UserDefaults(suiteName: suite + ".runtime")!
        defer { runtimeDefaults.removePersistentDomain(forName: suite + ".runtime") }
        let runtimePreferences = PreferencesStore(defaults: runtimeDefaults)
        runtimePreferences.saveHistory = false
        runtimePreferences.feedbackMode = .off
        runtimePreferences.deletionSoundEnabled = false
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let runtimeArchive = JSONHistoryPersistence(fileURL: directory.appendingPathComponent("runtime/History.json"))
        var source = "test.source"
        let coordinator = AppCoordinator(preferences: runtimePreferences, persistence: runtimeArchive, pasteboard: board, sourceApplication: { source })
        defer { coordinator.stop() }
        func copy(_ text: String) {
            board.clearContents()
            board.setString(text, forType: .string)
            coordinator.model.monitor!.poll()
        }
        copy("captured before enabling")
        try check(coordinator.history.items.count == 1 && !FileManager.default.fileExists(atPath: runtimeArchive.fileURL.path))
        runtimePreferences.saveHistory = true
        try check((try runtimeArchive.load()).first?.content == "captured before enabling")
        copy("saved copy")
        runtimePreferences.monitoringPaused = true
        copy("paused copy")
        try check(coordinator.history.items.count == 2)
        runtimePreferences.monitoringPaused = false
        runtimePreferences.excludedApplicationIDs = ["test.excluded"]
        source = "test.excluded"
        copy("excluded copy")
        try check(coordinator.history.items.count == 2)
        source = "test.source"
        runtimePreferences.hidePreviews = true
        let ids = coordinator.history.items.map(\.id)
        try check(try coordinator.history.persistenceEnabled && (try runtimeArchive.load()).map(\.id) == ids,
               "Hiding previews must not change saved history or capture policy")
        copy("saved with previews hidden")
        try check(coordinator.history.items.count == 3)
        runtimePreferences.historyLimit = 1
        try check(try coordinator.history.items.count == 1 && (try runtimeArchive.load()).count == 1)
        coordinator.model.clearHistory()
        try check(try runtimeArchive.load().isEmpty)
        print("PASS: actual coordinator settings wiring, opt-in existing data, saved new captures, pause, exclusions, hidden-preview independence, and immediate retention")

        let fixture = LoginFixture()
        let login = LaunchAtLoginController(service: fixture, defaults: defaults)
        try check(!login.isEnabled)
        login.enableByDefaultIfNeeded()
        try check(login.status == .requiresApproval && login.isEnabled)
        fixture.status = .enabled
        login.refresh()
        try check(login.status == .enabled)
        fixture.fail = true
        login.setEnabled(false)
        try check(login.errorMessage != nil && login.isEnabled, "Failed unregister must not falsely report disabled")
        fixture.fail = false
        login.setEnabled(false)
        try check(login.status == .notRegistered && !login.isEnabled)
        login.enableByDefaultIfNeeded()
        try check(fixture.registrations == 1 && !login.isEnabled, "Startup must preserve explicit login opt-out")
        let failedDefaults = UserDefaults(suiteName: suite + ".login-failure")!
        defer { failedDefaults.removePersistentDomain(forName: suite + ".login-failure") }
        let failedFixture = LoginFixture()
        failedFixture.fail = true
        let failedLogin = LaunchAtLoginController(service: failedFixture, defaults: failedDefaults)
        failedLogin.enableByDefaultIfNeeded()
        try check(failedLogin.errorMessage != nil && !failedLogin.isEnabled)
        failedFixture.fail = false
        failedLogin.enableByDefaultIfNeeded()
        try check(failedLogin.isEnabled && failedFixture.registrations == 1, "Failed default registration must be retryable")
        print("PASS: native login-item status model, approval state, and registration failure reporting with no system changes")

        // Render native Settings forms and a hidden-preview history panel using known fixtures.
        let renderPreferences = PreferencesStore(defaults: defaults)
        renderPreferences.historyLimit = 100
        renderPreferences.retentionDays = 7
        renderPreferences.hidePreviews = true
        let renderModel = HistoryViewModel(store: ClipboardHistoryStore(items: HistoryItem.examples), preferences: renderPreferences)
        let settings = SettingsController(model: renderModel, login: login)
        let settingsWindow = settings.window!
        try check(settingsWindow.level == .normal && !settingsWindow.styleMask.contains(.nonactivatingPanel))
        try check(settingsWindow.collectionBehavior.contains([.managed, .fullScreenNone, .fullScreenDisallowsTiling]))
        try check(settingsWindow.collectionBehavior.intersection([.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .moveToActiveSpace]).isEmpty,
                  "Settings must stay on desktop Spaces rather than join fullscreen apps")
        print("PASS: Settings uses a normal desktop window without fullscreen overlay behavior")
        for (name, tab) in [("history", SettingsTab.history), ("privacy", .privacy), ("feedback", .feedback), ("general", .general)] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560), styleMask: [.borderless], backing: .buffered, defer: false)
            let hosting = NSHostingView(rootView: SettingsView(preferences: renderPreferences, model: renderModel, login: login, onAddExclusion: {}, selectedTab: tab))
            window.contentView = hosting
            window.orderFront(nil)
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            hosting.layoutSubtreeIfNeeded()
            let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/klip-phase4-settings-\(name).png"))
            window.orderOut(nil)
        }
        let hiddenName = "Klip.Phase4.Hidden.\(UUID().uuidString)"
        let hiddenPanel = HistoryPanelController(model: renderModel, frameAutosaveName: hiddenName)
        hiddenPanel.showWindow(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        let hosting = hiddenPanel.window!.contentView!
        hosting.layoutSubtreeIfNeeded()
        let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/klip-phase4-hidden-preview.png"))
        hiddenPanel.dismiss()
        hiddenPanel.window?.setFrameAutosaveName("")
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(hiddenName)")
        print("PASS: rendered four native settings tabs and hidden-preview history for visual review")
        print("All Phase 4 checks passed. No general clipboard, real login registration, or user history files were used.")
    }

    @MainActor
    private static func check(_ condition: @autoclosure () throws -> Bool, _ message: String = "Phase 4 check failed",
                              file: StaticString = #fileID, line: UInt = #line) throws {
        let passed = try condition()
        precondition(passed, message, file: file, line: line)
    }

    @MainActor
    private static func childProcess(mode: String, directory: URL) throws {
        let archive = JSONHistoryPersistence(fileURL: directory.appendingPathComponent("process/History.json"))
        let date = Date(timeIntervalSince1970: 1_800_000_000.125)
        if mode == "--write" {
            let store = ClipboardHistoryStore(persistence: archive, persistenceEnabled: true)
            for content in ["  whitespace\nUnicode مرحبا 👋\t", "https://example.com/path?keep=1"] {
                store.record(ClipboardSnapshot(content: content, kind: ContentClassifier().classify(content), changeCount: 123,
                                               capturedAt: date, sourceApplicationID: "do.not.persist.this.app"))
            }
            let ids = store.items.map { $0.id.uuidString }
            try JSONEncoder().encode(ids).write(to: directory.appendingPathComponent("identities.json"))
        } else if mode == "--verify" {
            let store = ClipboardHistoryStore(persistence: archive, persistenceEnabled: true)
            try check(store.items.map(\.content) == ["https://example.com/path?keep=1", "  whitespace\nUnicode مرحبا 👋\t"])
            let identities = try JSONDecoder().decode([String].self, from: Data(contentsOf: directory.appendingPathComponent("identities.json")))
            try check(store.items.map { $0.id.uuidString } == identities)
            try check(store.items[0].kind == .link && store.items[1].kind == .text)
            try check(abs(store.items[0].snapshot.capturedAt.timeIntervalSince(date)) < 0.001)
            try check(store.items.allSatisfy { $0.snapshot.sourceApplicationID == nil && $0.snapshot.changeCount == 0 })
            let data = try Data(contentsOf: archive.fileURL)
            try check(!String(decoding: data, as: UTF8.self).contains("do.not.persist.this.app"))
            let fileMode = try FileManager.default.attributesOfItem(atPath: archive.fileURL.path)[.posixPermissions] as! NSNumber
            try check(fileMode.intValue & 0o777 == 0o600)
        } else { fatalError("Unknown test mode") }
    }
}
