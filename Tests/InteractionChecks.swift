import AppKit
import AVFAudio
import Darwin
import ServiceManagement
import SwiftUI

@MainActor
private final class InteractionSound: FeedbackSoundPlaying {
    var plays = 0
    var stops = 0
    var volumes: [Double] = []
    func play() { plays += 1 }
    func stop() { stops += 1 }
    func setVolume(_ volume: Double) { volumes.append(volume) }
}

@MainActor
private final class CueTransport: CopyCuePlayback {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var volume: Float = 1
    var preparations = 0
    var starts: [TimeInterval] = []
    var pauses = 0
    func prepareToPlay() -> Bool { preparations += 1; return true }
    func play() -> Bool { starts.append(currentTime); isPlaying = true; return true }
    func pause() { pauses += 1; isPlaying = false }
}

@MainActor
private final class InteractionPopup: CopyPopupPresenting {
    var shows = 0
    func showCopied() { shows += 1 }
    func dismiss() {}
    func stop() {}
}

@MainActor
private final class InteractionLogin: LoginItemManaging {
    var status: SMAppService.Status { .notRegistered }
    func register() throws {}
    func unregister() throws {}
}

/// Verifies audio routing without audible playback and renders only known test items.
@main
struct InteractionChecks {
    @MainActor
    static func main() throws {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let suite = "Klip.Interactions.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = PreferencesStore(defaults: defaults)
        assert(preferences.copySoundVolume == 0.50 && preferences.deletionSoundEnabled)
        preferences.copySoundVolume = 0.63
        preferences.deletionSoundEnabled = false
        let restored = PreferencesStore(defaults: defaults)
        assert(restored.copySoundVolume == 0.63 && !restored.deletionSoundEnabled)
        preferences.copySoundVolume = 2
        assert(preferences.copySoundVolume == 1)
        preferences.copySoundVolume = -1
        assert(preferences.copySoundVolume == 0)
        preferences.copySoundVolume = .nan
        assert(preferences.copySoundVolume == 0.50)
        preferences.copySoundVolume = 0.58
        assert(Int((preferences.copySoundVolume * 100).rounded()) == 58)
        print("PASS: saved copy volume/deletion preference, bounds, mute, and percentage rounding")

        let transport = CueTransport()
        let retriggeringCue = CopyFeedbackSound(player: transport)
        assert(transport.preparations == 1)
        retriggeringCue.setVolume(0.4)
        retriggeringCue.play()
        transport.currentTime = 0.01
        retriggeringCue.play()
        assert(transport.starts == [0, 0] && transport.pauses == 1 && abs(transport.volume - Float(0.4.squareRoot())) < 0.0001,
               "A second copy must immediately retrigger the single prepared voice, even while playing")
        retriggeringCue.stop()
        assert(!transport.isPlaying && transport.currentTime == 0)
        let cue = try AVAudioPlayer(data: CopyFeedbackSound.cueData())
        assert(cue.duration > 0.025 && cue.duration < 0.030 && cue.numberOfChannels == 1)
        assert(CopyFeedbackSound.outputVolume(for: 0) == 0)
        assert(abs(CopyFeedbackSound.outputVolume(for: 0.01) - 0.1) < 0.0001)
        assert(CopyFeedbackSound.outputVolume(for: 1) == 1)
        var previousGain: Float = 0
        for step in 0...100 {
            let gain = CopyFeedbackSound.outputVolume(for: Double(step) / 100)
            assert(gain >= previousGain && gain <= 1)
            previousGain = gain
        }
        let deleteTransport = CueTransport()
        let deletionCue = DeletionFeedbackSound(player: deleteTransport)
        deletionCue.play()
        deletionCue.play()
        assert(deleteTransport.starts == [0], "Deletion must stay a single nonoverlapping voice")
        deletionCue.stop()
        assert(!deleteTransport.isPlaying)
        let deletionAudio = try AVAudioPlayer(data: DeletionFeedbackSound.cueData())
        assert(deletionAudio.duration > 0.04 && deletionAudio.duration < 0.05 && deletionAudio.numberOfChannels == 1)
        for (data, expectedPeak) in [(CopyFeedbackSound.cueData(), 0.85), (DeletionFeedbackSound.cueData(), 0.72)] {
            let pcm = Array(data.dropFirst(44))
            let samples = stride(from: 0, to: pcm.count, by: 2).map {
                Double(Int16(bitPattern: UInt16(pcm[$0]) | UInt16(pcm[$0 + 1]) << 8)) / Double(Int16.max)
            }
            assert(samples.first == 0 && samples.last == 0)
            assert(abs(samples.map { abs($0) }.max()! - expectedPeak) < 0.0001)
        }
        print("PASS: audible low-end gain, exact mute, monotonic volume, normalized unclipped waveforms, and single prepared deletion tap")
        print("PASS: one short mono cue, prepared transport, immediate rapid-copy retrigger, volume, and stop")

        let copySound = InteractionSound()
        let deleteSound = InteractionSound()
        let popup = InteractionPopup()
        var clock: TimeInterval = 0
        let feedback = FeedbackController(preferences: preferences, popup: popup, sound: copySound,
                                          deletionSound: deleteSound, now: { clock })
        assert(copySound.volumes.last == 0.58)
        preferences.feedbackMode = .sound
        feedback.clipboardDidChange()
        assert(copySound.plays == 1 && popup.shows == 0 && copySound.volumes.last == 0.58)
        preferences.copySoundVolume = 0.4
        feedback.applySoundPreferences()
        assert(copySound.volumes.last == 0.4)
        preferences.feedbackMode = .visual
        feedback.previewCopySound()
        assert(copySound.plays == 2 && popup.shows == 0, "Preview must play just audio, independent of copy mode")
        preferences.copySoundVolume = 0
        feedback.applySoundPreferences()
        let before = copySound.plays
        preferences.feedbackMode = .both
        clock = 1
        feedback.clipboardDidChange()
        feedback.previewCopySound()
        assert(copySound.plays == before && popup.shows == 1 && copySound.stops > 0)
        preferences.deletionSoundEnabled = true
        preferences.feedbackMode = .off
        feedback.historyDidDelete()
        clock = 1.05
        feedback.historyDidDelete()
        assert(deleteSound.plays == 1)
        clock = 1.2
        feedback.historyDidDelete()
        assert(deleteSound.plays == 2, "Deletion is independently controlled, not tied to copy mode")
        preferences.deletionSoundEnabled = false
        feedback.applySoundPreferences()
        clock = 2
        feedback.historyDidDelete()
        assert(deleteSound.plays == 2 && deleteSound.stops > 0)
        preferences.deletionSoundEnabled = true
        feedback.stop()
        clock = 3
        feedback.historyDidDelete()
        feedback.previewCopySound()
        assert(deleteSound.plays == 2 && copySound.plays == before)
        assert(DeletionFeedbackSound().isAvailable)
        print("PASS: actual volume routing, explicit preview, silent zero volume, independent deletion cue, burst coalescing, and shutdown")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Klip.Interactions.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = JSONHistoryPersistence(fileURL: directory.appendingPathComponent("History.json"))
        let store = ClipboardHistoryStore(persistence: archive, persistenceEnabled: true)
        for item in HistoryItem.examples.prefix(3) { store.record(item.snapshot) }
        let model = HistoryViewModel(store: store, preferences: preferences, reduceMotion: { false })
        model.isPanelPresented = true
        var deletionEvents = 0
        model.onDeletion = { deletionEvents += 1 }
        assert(model.deletionAnimation != nil)
        let removed = model.items[1]
        model.selectedID = removed.id
        model.inspectedItem = removed
        model.remove(removed)
        assert(model.inspectedItem == nil && model.items.count == 2 && model.selectedID != removed.id && deletionEvents == 1)
        let restoredItems = try archive.load()
        assert(!restoredItems.contains(where: { $0.id == removed.id }), "Animation must never delay disk deletion")
        model.remove(removed)
        assert(deletionEvents == 1, "Deleting an already-removed row must not replay the cue")
        model.clearHistory()
        assert(deletionEvents == 2 && model.items.isEmpty)
        assert(!FileManager.default.fileExists(atPath: archive.fileURL.path))
        model.clearHistory()
        assert(deletionEvents == 2)
        let reduced = HistoryViewModel(store: ClipboardHistoryStore(items: HistoryItem.examples), preferences: preferences, reduceMotion: { true })
        reduced.isPanelPresented = true
        assert(reduced.deletionAnimation == nil)
        let automatic = HistoryViewModel(store: ClipboardHistoryStore(items: HistoryItem.examples), preferences: preferences)
        automatic.onDeletion = { deletionEvents += 1 }
        automatic.store.configure(persistenceEnabled: false, capacity: 1, maxAge: nil)
        automatic.historyDidChange()
        assert(deletionEvents == 2, "Automatic retention changes must be silent")
        print("PASS: row/preview deletion, immediate persisted removal, selection validity, single clear cue, silent stale/automatic deletion, and Reduce Motion")

        // Capture a real SwiftUI row transition including the last-row empty state.
        let renderStore = ClipboardHistoryStore(items: [HistoryItem.examples[0]])
        let renderModel = HistoryViewModel(store: renderStore, preferences: preferences, reduceMotion: { false })
        let frameName = "Klip.Interactions.Render.\(UUID().uuidString)"
        let controller = HistoryPanelController(model: renderModel, frameAutosaveName: frameName)
        controller.showWindow(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        func snapshot(_ name: String, view: NSView) throws {
            view.layoutSubtreeIfNeeded()
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/klip-\(name).png"))
        }
        try snapshot("deletion-before", view: controller.window!.contentView!)
        renderModel.remove(renderStore.items[0])
        assert(renderModel.items.isEmpty)
        RunLoop.main.run(until: Date().addingTimeInterval(0.09))
        try snapshot("deletion-during", view: controller.window!.contentView!)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        try snapshot("deletion-after", view: controller.window!.contentView!)
        controller.dismiss()
        controller.window?.setFrameAutosaveName("")
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(frameName)")

        preferences.copySoundVolume = 0.58
        let login = LaunchAtLoginController(service: InteractionLogin())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 560), styleMask: [.borderless], backing: .buffered, defer: false)
        let settings = NSHostingView(rootView: SettingsView(preferences: preferences, model: renderModel, login: login, onAddExclusion: {}, selectedTab: .feedback))
        window.contentView = settings
        window.orderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        try snapshot("sound-settings", view: settings)
        window.orderOut(nil)
        print("PASS: rendered row minimization/empty state and volume/deletion Settings for visual review")
        print("All interaction checks passed. No clipboard access, real history files, or audible playback was used.")
    }
}
