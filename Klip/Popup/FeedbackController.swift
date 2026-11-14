import AppKit
import AVFAudio

@MainActor
protocol FeedbackSoundPlaying: AnyObject {
    func play()
    func stop()
    func setVolume(_ volume: Double)
}

extension FeedbackSoundPlaying {
    func setVolume(_ volume: Double) {}
}

/// Injectable transport keeps rapid-retrigger tests silent.
@MainActor
protocol CopyCuePlayback: AnyObject {
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get set }
    var volume: Float { get set }
    @discardableResult func prepareToPlay() -> Bool
    @discardableResult func play() -> Bool
    func pause()
}

extension AVAudioPlayer: CopyCuePlayback {}

@MainActor
final class CopyFeedbackSound: FeedbackSoundPlaying {
    private let player: (any CopyCuePlayback)?
    var isAvailable: Bool { player != nil }

    /// One 28 ms tapered tick, normalized so the volume control is useful.
    static func cueData() -> Data {
        FeedbackCueWave.make(duration: 0.028, peak: 0.85) { t in
            let envelope = (1 - exp(-t / 0.001)) * exp(-t / 0.006)
            return envelope * (0.8 * sin(2 * .pi * 1400 * t) + 0.2 * sin(2 * .pi * 2100 * t))
        }
    }

    static func outputVolume(for level: Double) -> Float {
        guard level.isFinite else { return 0 }
        return Float(min(1, max(0, level)).squareRoot())
    }

    init(player suppliedPlayer: (any CopyCuePlayback)? = nil) {
        player = suppliedPlayer ?? (try? AVAudioPlayer(data: Self.cueData()))
        player?.volume = Self.outputVolume(for: 0.50)
        player?.prepareToPlay()
    }

    func play() {
        guard let player else { return }
        // A new copy owns the single voice immediately; never drop it or queue it.
        if player.isPlaying { player.pause() }
        player.currentTime = 0
        player.play()
    }

    func stop() { player?.pause(); player?.currentTime = 0 }
    func setVolume(_ volume: Double) { player?.volume = Self.outputVolume(for: volume) }
}

@MainActor
final class DeletionFeedbackSound: FeedbackSoundPlaying {
    private let player: (any CopyCuePlayback)?
    var isAvailable: Bool { player != nil }

    /// One short descending tap, with no trash rustle or additional notes.
    static func cueData() -> Data {
        FeedbackCueWave.make(duration: 0.045, peak: 0.72) { t in
            let phase = 2 * Double.pi * (520 * t - 2000 * t * t)
            let envelope = (1 - exp(-t / 0.0015)) * exp(-t / 0.010)
            return envelope * (0.88 * sin(phase) + 0.12 * sin(phase * 2))
        }
    }

    init(player suppliedPlayer: (any CopyCuePlayback)? = nil) {
        player = suppliedPlayer ?? (try? AVAudioPlayer(data: Self.cueData()))
        player?.volume = 0.4
        player?.prepareToPlay()
    }

    func play() {
        guard let player, !player.isPlaying else { return }
        player.currentTime = 0
        player.play()
    }

    func stop() { player?.pause(); player?.currentTime = 0 }
}

/// A short mono PCM cue, tapered to zero and normalized without clipping.
private enum FeedbackCueWave {
    static func make(duration: Double, peak: Double, sample: (Double) -> Double) -> Data {
        let sampleRate = 44_100
        let count = Int(Double(sampleRate) * duration)
        let samples = (0..<count).map { index in
            let tail = min(1, Double(count - 1 - index) / (0.002 * Double(sampleRate)))
            return sample(Double(index) / Double(sampleRate)) * tail
        }
        let normalization = peak / max(samples.map { abs($0) }.max() ?? 1, 0.0001)
        var data = Data()
        func word<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        word(UInt32(36 + count * 2))
        data.append(contentsOf: "WAVEfmt ".utf8)
        word(UInt32(16)); word(UInt16(1)); word(UInt16(1))
        word(UInt32(sampleRate)); word(UInt32(sampleRate * 2))
        word(UInt16(2)); word(UInt16(16))
        data.append(contentsOf: "data".utf8)
        word(UInt32(count * 2))
        for value in samples { word(Int16((value * normalization * Double(Int16.max)).rounded())) }
        return data
    }
}

@MainActor
final class FeedbackController {
    let preferences: PreferencesStore
    private let popup: CopyPopupPresenting
    private let sound: FeedbackSoundPlaying
    private let deletionSound: FeedbackSoundPlaying
    private let now: () -> TimeInterval
    private var lastDeletionSoundTime: TimeInterval?
    private var stopped = false

    init(preferences: PreferencesStore, popup: CopyPopupPresenting? = nil,
         sound: FeedbackSoundPlaying? = nil, deletionSound: FeedbackSoundPlaying? = nil,
         now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.preferences = preferences
        self.popup = popup ?? PopupController(durationProvider: { preferences.popupDuration },
                                               autoExpandProvider: { preferences.autoExpandCopyPreview },
                                               previewDurationProvider: { preferences.expandedPreviewDuration })
        self.sound = sound ?? CopyFeedbackSound()
        self.deletionSound = deletionSound ?? DeletionFeedbackSound()
        self.now = now
        self.sound.setVolume(preferences.copySoundVolume)
        preferences.onFeedbackModeChanged = { [weak self] mode in
            guard let self, !self.stopped else { return }
            if !mode.showsPopup { self.popup.dismiss() }
            if !mode.playsSound { self.sound.stop() }
        }
    }

    /// Only accepted copies reach feedback; hidden previews supply no payload.
    func clipboardDidChange(preview: ClipboardSnapshot? = nil) {
        guard !stopped else { return }
        let mode = preferences.feedbackMode
        if mode.playsSound && preferences.copySoundVolume > 0 {
            sound.setVolume(preferences.copySoundVolume)
            sound.play()
        }
        if mode.showsPopup { popup.setPreview(preview); popup.showCopied() }
    }

    func applySoundPreferences() {
        sound.setVolume(preferences.copySoundVolume)
        if preferences.copySoundVolume == 0 { sound.stop() }
        if !preferences.deletionSoundEnabled { deletionSound.stop() }
    }

    func previewCopySound() {
        guard !stopped, preferences.copySoundVolume > 0 else { return }
        sound.setVolume(preferences.copySoundVolume)
        sound.play()
    }

    func historyDidDelete() {
        guard !stopped, preferences.deletionSoundEnabled else { return }
        let time = now()
        guard lastDeletionSoundTime.map({ time - $0 >= 0.1 }) ?? true else { return }
        lastDeletionSoundTime = time
        deletionSound.play()
    }

    func dismissCurrentFeedback() {
        popup.dismiss()
        sound.stop()
    }

    func stop() {
        stopped = true
        popup.stop()
        sound.stop()
        deletionSound.stop()
    }
}
