import AppKit
import Darwin
import SwiftUI

@MainActor
private final class PopupSpy: CopyPopupPresenting {
    var shows = 0
    var dismissals = 0
    var stops = 0
    func showCopied() { shows += 1 }
    func dismiss() { dismissals += 1 }
    func stop() { stops += 1 }
}

@MainActor
private final class SoundSpy: FeedbackSoundPlaying {
    var plays = 0
    var stops = 0
    func play() { plays += 1 }
    func stop() { stops += 1 }
}

/// No general clipboard reads/writes and no audible sound playback.
@main
struct Phase3Checks {
    @MainActor
    static func main() throws {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let suiteName = "Klip.Phase3.Checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = PreferencesStore(defaults: defaults)
        assert(preferences.feedbackMode == .visual)
        let popupSpy = PopupSpy()
        let soundSpy = SoundSpy()
        var time: TimeInterval = 0
        let feedback = FeedbackController(preferences: preferences, popup: popupSpy, sound: soundSpy, now: { time })
        feedback.clipboardDidChange()
        assert(popupSpy.shows == 1 && soundSpy.plays == 0)
        preferences.feedbackMode = .sound
        assert(popupSpy.dismissals == 1)
        feedback.clipboardDidChange()
        time = 0.03
        feedback.clipboardDidChange()
        time = 0.06
        feedback.clipboardDidChange()
        assert(soundSpy.plays == 3 && popupSpy.shows == 1)
        time = 0.13
        feedback.clipboardDidChange()
        assert(soundSpy.plays == 4)
        preferences.feedbackMode = .both
        time = 1.3
        feedback.clipboardDidChange()
        assert(popupSpy.shows == 2 && soundSpy.plays == 5)
        assert(PreferencesStore(defaults: defaults).feedbackMode == .both)
        preferences.feedbackMode = .off
        let shows = popupSpy.shows
        let sounds = soundSpy.plays
        feedback.clipboardDidChange()
        assert(popupSpy.shows == shows && soundSpy.plays == sounds)
        assert(popupSpy.dismissals == 2 && soundSpy.stops > 0)
        preferences.feedbackMode = .visual
        feedback.dismissCurrentFeedback()
        feedback.clipboardDidChange()
        assert(popupSpy.shows == shows + 1)
        feedback.stop()
        feedback.clipboardDidChange()
        assert(popupSpy.stops == 1 && popupSpy.shows == shows + 1)
        assert(CopyFeedbackSound().isAvailable)
        print("PASS: visual default, four feedback modes, preference persistence, per-copy audio without cooldown, interruption, and shutdown")

        let display1 = PopupDisplay(id: 1, frame: NSRect(x: 0, y: 0, width: 1512, height: 982),
                                    visibleFrame: NSRect(x: 0, y: 40, width: 1512, height: 910), topInset: 32, scale: 2, notchWidth: 180)
        let display2 = PopupDisplay(id: 2, frame: NSRect(x: -1920, y: 0, width: 1920, height: 1080),
                                    visibleFrame: NSRect(x: -1920, y: 0, width: 1920, height: 1056), topInset: 0, scale: 1)
        let display3 = PopupDisplay(id: 3, frame: NSRect(x: 1512, y: -500, width: 1200, height: 800),
                                    visibleFrame: NSRect(x: 1560, y: -500, width: 1152, height: 800), topInset: 0, scale: 2)
        for display in [display1, display2, display3] {
            let rect = PopupPlacement.frame(on: display)
            assert(display.frame.contains(rect))
            if display.topInset > 0 {
                assert(rect.maxY == display.frame.maxY - display.topInset + PopupLayout.notchOverlap)
                assert(rect.width == PopupLayout.size.width)
            } else {
                assert(rect.maxY == display.frame.maxY && rect.width == PopupLayout.size.width)
            }
            let expandedRect = PopupPlacement.previewFrame(on: display)
            assert(expandedRect.width == (display.topInset > 0 ? display.notchWidth : PopupLayout.previewSize.width))
            assert(expandedRect.maxY == rect.maxY && expandedRect.midX == rect.midX)
            assert(rect.height == PopupLayout.size.height)
            assert(rect.minX * display.scale == (rect.minX * display.scale).rounded())
        }
        assert(PopupPlacement.target(pointer: NSPoint(x: -500, y: 500), displays: [display1, display2])?.id == 2)
        assert(PopupPlacement.target(pointer: NSPoint(x: 9000, y: 9000), displays: [display1, display2])?.id == 1)
        assert(PopupPlacement.target(pointer: .zero, displays: []) == nil)
        print("PASS: flush notch attachment, top-edge fallback, negative origins, side docks, pixel alignment, and pointer targeting")

        // Live NSPanel lifecycle with injected display geometry and accelerated timing.
        var available = [display1, display2]
        var pointer = NSPoint(x: 300, y: 400)
        let popup = PopupController(visibleDuration: 0.14, displays: { available }, pointer: { pointer }, reduceMotion: { true })
        defer { popup.stop() }
        let fixture = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 260, height: 160),
                               styleMask: [.titled], backing: .buffered, defer: false)
        fixture.isReleasedWhenClosed = false
        let field = NSTextField(string: "Typing stays here")
        field.frame = NSRect(x: 20, y: 60, width: 200, height: 24)
        fixture.contentView?.addSubview(field)
        fixture.makeKeyAndOrderFront(nil)
        fixture.makeFirstResponder(field)
        app.activate(ignoringOtherApps: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        let keyWindow = app.keyWindow
        let responder = fixture.firstResponder
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        popup.showCopied()
        assert(popup.panel.styleMask.contains(.nonactivatingPanel))
        assert(!popup.panel.canBecomeKey && !popup.panel.canBecomeMain && !popup.panel.ignoresMouseEvents)
        assert(popup.panel.collectionBehavior.contains([.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary]))
        assert(!popup.panel.collectionBehavior.contains(.moveToActiveSpace))
        assert(popup.state.reduceMotion && popup.state.isExpanded && popup.panel.alphaValue == 1)
        assert(!popup.panel.hasShadow && popup.panel.level == .statusBar)
        assert(popup.panel.frame == PopupPlacement.frame(on: display1))
        assert(app.keyWindow === keyWindow && fixture.firstResponder === responder)
        assert(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostPID)
        let identity = ObjectIdentifier(popup.panel)
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        popup.showCopied()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        assert(popup.state.isVisible && popup.panel.isVisible, "A fresh copy must reset the dismissal deadline")
        assert(ObjectIdentifier(popup.panel) == identity && popup.state.presentationCount == 2)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        assert(!popup.state.isVisible && !popup.panel.isVisible)
        popup.showCopied()
        pointer = NSPoint(x: -500, y: 500)
        popup.showCopied()
        assert(popup.targetDisplayID == 2)
        available = [display1]
        popup.screenConfigurationDidChange()
        assert(popup.targetDisplayID == 1 && popup.panel.frame == PopupPlacement.frame(on: display1))
        available = []
        popup.screenConfigurationDidChange()
        assert(!popup.state.isVisible)
        print("PASS: nonactivating interactive panel, retained key focus, reduced motion, one-window reuse, timer refresh, and screen removal")

        available = [display1]
        pointer = NSPoint(x: 300, y: 400)
        popup.showCopied()
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        let hosting = popup.panel.contentView!
        hosting.layoutSubtreeIfNeeded()
        let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/klip-phase3-popup.png"))
        for (x, y) in [(0, bitmap.pixelsHigh - 1), (bitmap.pixelsWide - 1, bitmap.pixelsHigh - 1)] {
            assert(bitmap.colorAt(x: x, y: y)!.alphaComponent < 0.01, "Lower corners must be transparent")
        }
        let join = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 1)!.usingColorSpace(.deviceRGB)!
        assert(join.alphaComponent > 0.99 && join.redComponent < 0.01 && join.greenComponent < 0.01 && join.blueComponent < 0.01,
               "The attachment must be solid black rather than a glass capsule")
        let sample = ClipboardSnapshot(content: "A compact preview of the text just copied.\nSecond line stays inside the notch.",
            kind: .text, changeCount: 1, capturedAt: Date(), sourceApplicationID: nil)
        popup.setPreview(sample)
        let compactFrame = popup.panel.frame
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: NSPoint(x: 40, y: 15), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: popup.panel.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
            popup.panel.sendEvent(event)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        assert(popup.state.showsPreview, "An actual mouse click must open the preview")
        assert(popup.state.previewText == sample.content)
        assert(popup.panel.frame.width == display1.notchWidth)
        assert(popup.panel.frame.maxY == compactFrame.maxY && popup.panel.frame.midX == compactFrame.midX,
               "Expansion must keep the notch attachment fixed")
        assert(!popup.panel.isMovable && !popup.panel.isMovableByWindowBackground)
        assert(app.keyWindow === keyWindow && fixture.firstResponder === responder)
        assert(NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmostPID)
        let expandedFrame = popup.panel.frame
        popup.expandPreview()
        assert(popup.panel.frame == expandedFrame, "Repeated clicks must not move the preview")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        assert(popup.state.showsPreview && popup.state.isVisible, "The original copy timer must not dismiss a clicked preview")
        hosting.layoutSubtreeIfNeeded()
        let expandedBitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: expandedBitmap)
        try expandedBitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/klip-expanded-notch.png"))
        popup.setPreview(nil)
        popup.showCopied()
        assert(!popup.state.showsPreview && popup.panel.frame == compactFrame)
        popup.expandPreview()
        assert(popup.state.previewText == "Preview hidden" && popup.state.previewImage == nil)
        available = [display2]
        popup.screenConfigurationDidChange()
        assert(popup.panel.frame.midX == display2.frame.midX && popup.panel.frame.maxY == display2.frame.maxY)
        popup.dismiss()
        assert(popup.state.previewText == "Preview hidden" && !popup.state.showsPreview)
        available = [display1]
        print("PASS: actual click opens bounded preview, fixed top-center attachment, no dragging/focus change, timer renewal, privacy, display change, and fresh-copy reset")
        let animated = PopupController(visibleDuration: 0.2, displays: { [display1] }, pointer: { .zero }, reduceMotion: { false })
        animated.showCopied()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        assert(animated.state.isExpanded, "The notch should expand on presentation")
        RunLoop.main.run(until: Date().addingTimeInterval(0.16))
        assert(!animated.state.isExpanded && animated.state.isVisible, "The notch should retract before its window is hidden")
        animated.showCopied()
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        assert(animated.state.isVisible && animated.panel.isVisible && animated.panel.alphaValue > 0.8,
               "An older retraction must not hide a newer copy")
        RunLoop.main.run(until: Date().addingTimeInterval(0.2 + PopupLayout.retractionDuration + 0.12))
        assert(!animated.state.isVisible)
        animated.stop()
        print("PASS: black notch rendering, expansion/retraction, and a new copy during retraction")
        let motion = PopupController(visibleDuration: 2, displays: { [display1] }, pointer: { .zero }, reduceMotion: { false })
        func renderMotion(_ name: String) throws {
            let host = motion.panel.contentView!
            host.layoutSubtreeIfNeeded()
            let image = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: image)
            try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/klip-notch-motion-\(name).png"))
        }
        motion.setPreview(sample)
        motion.showCopied()
        let attachment = motion.panel.frame.maxY
        RunLoop.main.run(until: Date().addingTimeInterval(0.04))
        try renderMotion("entering")
        RunLoop.main.run(until: Date().addingTimeInterval(0.40))
        try renderMotion("compact")
        motion.expandPreview()
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        try renderMotion("expanding")
        RunLoop.main.run(until: Date().addingTimeInterval(0.40))
        try renderMotion("preview")
        assert(motion.panel.frame.maxY == attachment && motion.panel.frame.width == display1.notchWidth)
        motion.state.isExpanded = false
        RunLoop.main.run(until: Date().addingTimeInterval(0.10))
        try renderMotion("retracting")
        motion.stop()
        print("PASS: rendered whole-surface slide, compact-to-preview morph, and retraction with fixed notch attachment")

        var autoExpand = true
        let automatic = PopupController(displays: { [display1] }, pointer: { .zero }, reduceMotion: { false },
            autoExpandProvider: { autoExpand })
        automatic.setPreview(sample)
        automatic.showCopied()
        assert(automatic.state.showsPreview && automatic.panel.frame.height == PopupLayout.previewSize.height,
               "Automatic mode must present the preview immediately, without a compact icon phase")
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        assert(automatic.state.showsPreview && automatic.panel.frame.width == display1.notchWidth)
        assert(automatic.state.previewText == sample.content)
        automatic.setPreview(sample)
        automatic.showCopied()
        assert(automatic.state.showsPreview && automatic.panel.frame.height == PopupLayout.previewSize.height,
               "A successive copy in automatic mode must never reset to the copy icon")
        autoExpand = false
        automatic.setPreview(sample)
        automatic.showCopied()
        assert(!automatic.state.showsPreview && automatic.panel.frame.width == PopupLayout.size.width)
        automatic.stop()
        print("PASS: automatic mode opens preview directly with no compact-icon phase, including successive copies; disabling restores click-to-preview")


        var previewDuration: TimeInterval = 0.25
        let fitted = PopupController(displays: { [display1] }, pointer: { .zero }, reduceMotion: { true },
            previewDurationProvider: { previewDuration })
        var shortText = sample
        shortText = ClipboardSnapshot(content: "Hi", kind: .text, changeCount: 1, capturedAt: Date(), sourceApplicationID: nil)
        fitted.setPreview(shortText)
        fitted.showCopied()
        fitted.expandPreview()
        let shortHeight = fitted.panel.frame.height
        assert(shortHeight == 58 && PopupLayout.previewPadding == 5 && PopupLayout.previewHorizontalPadding == 10)
        let shortWidth = fitted.panel.frame.width
        assert(shortWidth < display1.notchWidth && abs(fitted.panel.frame.midX - display1.frame.midX) <= 0.5, "Unexpected compact frame: \(fitted.panel.frame)")
        let textWidth = ceil(NSAttributedString(string: "Hi", attributes: [.font: NSFont.systemFont(ofSize: 12)]).size().width)
        assert(shortWidth == 20 + 5 + textWidth + 20 + PopupLayout.shoulder * 2,
               "Short content must have ten-point horizontal body padding, without spare horizontal space")
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        fitted.expandPreview()
        RunLoop.main.run(until: Date().addingTimeInterval(0.16))
        assert(fitted.state.isVisible, "Click must renew the configured preview timer")
        RunLoop.main.run(until: Date().addingTimeInterval(0.13))
        assert(!fitted.state.isVisible)
        previewDuration = 5
        for (name, text) in [("short", "Hi"), ("multiline", "First line\nSecond line\nThird line"), ("long", String(repeating: "Long text wraps naturally. ", count: 30))] {
            let snapshot = ClipboardSnapshot(content: text, kind: .text, changeCount: 1, capturedAt: Date(), sourceApplicationID: nil)
            fitted.setPreview(snapshot)
            fitted.showCopied()
            fitted.expandPreview()
            assert(fitted.panel.frame.maxY == PopupPlacement.frame(on: display1).maxY)
            assert(fitted.panel.frame.width <= display1.notchWidth)
            if name == "long" { assert(fitted.panel.frame.width == display1.notchWidth) }
            assert(fitted.panel.frame.height == shortHeight, "Content must not change the fixed compact preview height")
            RunLoop.main.run(until: Date().addingTimeInterval(0.03))
            let host = fitted.panel.contentView!
            host.layoutSubtreeIfNeeded()
            let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/klip-fitting-\(name).png"))
        }
        previewDuration = 0.08
        fitted.expandPreview()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        assert(!fitted.state.isVisible, "Next click must use the newly configured duration")
        fitted.stop()
        print("PASS: configurable preview timer and renewal, fixed 58-point height, content-fitting width capped at notch width, ten-point side padding, five-point vertical padding, and stable attachment")

        preferences.feedbackMode = .visual
        let realFeedback = FeedbackController(preferences: preferences, popup: popup, sound: SoundSpy())
        realFeedback.clipboardDidChange()
        assert(popup.state.isVisible)
        preferences.feedbackMode = .off
        assert(!popup.state.isVisible && !popup.panel.isVisible)
        realFeedback.stop()
        let historyName = "Klip.Phase3.History.\(UUID().uuidString)"
        let history = HistoryPanelController(frameAutosaveName: historyName)
        assert(history.window!.styleMask.contains(.nonactivatingPanel))
        assert(history.window!.canBecomeKey && !history.window!.canBecomeMain)
        assert(history.window!.collectionBehavior.contains([.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary]))
        assert(!history.window!.collectionBehavior.contains(.moveToActiveSpace))
        let historyFrontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        history.showWindow(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        assert(NSWorkspace.shared.frontmostApplication?.processIdentifier == historyFrontmostPID)
        history.dismiss()
        history.window?.setFrameAutosaveName("")
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(historyName)")
        fixture.orderOut(nil)
        print("PASS: switching feedback off cancels immediately; history uses a nonactivating fullscreen-capable panel")

        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let capturePopup = PopupSpy()
        let captureSound = SoundSpy()
        preferences.feedbackMode = .both
        var captureTime: TimeInterval = 0
        let captureFeedback = FeedbackController(preferences: preferences, popup: capturePopup, sound: captureSound, now: { captureTime })
        let writer = ClipboardWriter(pasteboard: board)
        let privacy = PrivacyPolicy()
        let store = ClipboardHistoryStore()
        let monitor = ClipboardMonitor(pasteboard: board, writer: writer, privacy: privacy, sourceApplication: { "test.source" }) { snapshot in
            store.record(snapshot)
            captureTime += 1
            captureFeedback.clipboardDidChange()
        }
        func externalCopy(_ text: String) {
            board.clearContents()
            board.setString(text, forType: .string)
            monitor.poll()
        }
        externalCopy("external copy")
        externalCopy("external copy")
        assert(store.items.count == 1 && capturePopup.shows == 2 && captureSound.plays == 2)
        writer.write(store.items[0].snapshot)
        monitor.poll()
        assert(capturePopup.shows == 2)
        privacy.isPaused = true
        externalCopy("paused copy")
        assert(capturePopup.shows == 2)
        privacy.isPaused = false
        monitor.rebaseline()
        let sensitive = NSPasteboardItem()
        sensitive.setString("sensitive fixture", forType: .string)
        sensitive.setString("1", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        board.clearContents()
        board.writeObjects([sensitive])
        monitor.poll()
        assert(capturePopup.shows == 2)
        preferences.feedbackMode = .off
        externalCopy("new external copy")
        assert(store.items.count == 2 && capturePopup.shows == 2 && captureSound.plays == 2)
        preferences.feedbackMode = .both
        let beforeRapidSounds = captureSound.plays
        let beforeRapidPopups = capturePopup.shows
        monitor.start()
        board.clearContents()
        board.setString("rapid first", forType: .string)
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        board.clearContents()
        board.setString("rapid second", forType: .string)
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        monitor.stop()
        assert(Array(store.items.prefix(2).map(\.content)) == ["rapid second", "rapid first"])
        assert(captureSound.plays == beforeRapidSounds + 2 && capturePopup.shows == beforeRapidPopups + 2,
               "Two successive copies must both enter history and produce their own cue and popup")
        print("PASS: successive 80-ms timer-driven copies both captured, with one cue and popup per copy")
        captureFeedback.stop()
        print("PASS: external-copy feedback, feedback on repeated copies despite history deduplication, own-write/privacy suppression, and off-mode capture")
        print("All Phase 3 checks passed. No general clipboard access or audible playback was used.")
    }
}
