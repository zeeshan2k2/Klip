import AppKit
import SwiftUI

@MainActor
protocol CopyPopupPresenting: AnyObject {
    func setPreview(_ snapshot: ClipboardSnapshot?)
    func showCopied()
    func dismiss()
    func stop()
}

extension CopyPopupPresenting {
    func setPreview(_ snapshot: ClipboardSnapshot?) {}
}

@MainActor
final class PopupController: CopyPopupPresenting {
    let state = PopupState()
    let panel: NSPanel
    private(set) var targetDisplayID: UInt32?
    private let displays: () -> [PopupDisplay]
    private let pointer: () -> NSPoint
    private let reduceMotion: () -> Bool
    private let visibleDuration: TimeInterval
    private let previewDurationProvider: () -> TimeInterval
    private let autoExpandProvider: () -> Bool
    private let durationProvider: (() -> TimeInterval)?
    private var previewSnapshot: ClipboardSnapshot?
    private var generation = 0
    private var dismissalTask: Task<Void, Never>?
    private var screenObserver: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?

    init(visibleDuration: TimeInterval = 1.15,
         displays: (() -> [PopupDisplay])? = nil,
         pointer: (() -> NSPoint)? = nil,
         reduceMotion: (() -> Bool)? = nil,
         durationProvider: (() -> TimeInterval)? = nil,
         autoExpandProvider: @escaping () -> Bool = { false },
         previewDurationProvider: @escaping () -> TimeInterval = { 1.0 }) {
        self.displays = displays ?? { PopupDisplay.current() }
        self.pointer = pointer ?? { NSEvent.mouseLocation }
        self.reduceMotion = reduceMotion ?? { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        self.visibleDuration = max(0.01, visibleDuration)
        self.durationProvider = durationProvider
        self.autoExpandProvider = autoExpandProvider
        self.previewDurationProvider = previewDurationProvider
        panel = CopyFeedbackPanel(contentRect: NSRect(origin: .zero, size: PopupLayout.size),
                                  styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Klip — Copied"
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.isExcludedFromWindowsMenu = true
        panel.level = .statusBar
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .ignoresCycle]
        let hosting = PopupHostingView(rootView: PopupView(state: state, onClick: { [weak self] in self?.expandPreview() }))
        hosting.sizingOptions = []
        hosting.wantsLayer = true
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenConfigurationDidChange() }
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.state.reduceMotion = self?.reduceMotion() ?? true }
        }
    }

    func setPreview(_ snapshot: ClipboardSnapshot?) {
        previewSnapshot = snapshot
        state.previewText = snapshot.map { String($0.content.prefix(500)) } ?? "Preview hidden"
        state.previewSymbol = snapshot?.kind.symbol ?? "lock"
        state.previewIsImage = snapshot.map { ClipboardMedia.isImageContent($0) } ?? false
        state.previewImage = nil
    }

    func showCopied() {
        guard let display = PopupPlacement.target(pointer: pointer(), displays: displays()) else { dismiss(); return }
        generation += 1
        let current = generation
        dismissalTask?.cancel()
        targetDisplayID = display.id
        state.reduceMotion = reduceMotion()
        state.presentationCount += 1
        let automaticPreview = autoExpandProvider()
        let alreadyVisible = state.isVisible && panel.isVisible
        state.isVisible = true
        if !alreadyVisible { state.isExpanded = false }
        if automaticPreview {
            // Configure the preview before ordering the window onscreen. No
            // compact copy-indicator state is ever presented in this mode.
            preparePreview(on: display, animated: false)
        } else {
            let target = PopupPlacement.frame(on: display)
            state.showsPreview = false
            state.canvasWidth = target.width
            state.canvasHeight = target.height
            state.width = target.width
            panel.setFrame(target, display: true)
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        let duration = automaticPreview ? previewDurationProvider() : (durationProvider?() ?? visibleDuration)
        scheduleDismissal(after: max(0.01, duration), generation: current)
        if state.reduceMotion || alreadyVisible {
            state.isExpanded = true
        } else {
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, self.generation == current, self.state.isVisible else { return }
                self.state.isExpanded = true
            }
        }
    }

    /// Grow the transparent canvas without moving its top-center attachment.
    /// Only SwiftUI's black surface animates, avoiding AppKit's frame-origin animation.
    func expandPreview() {
        guard state.isVisible, state.isExpanded else { return }
        generation += 1
        dismissalTask?.cancel()
        if !state.showsPreview {
            guard let display = displays().first(where: { $0.id == targetDisplayID }) else { dismiss(); return }
            preparePreview(on: display, animated: true)
        }
        scheduleDismissal(after: max(0.01, previewDurationProvider()), generation: generation)
    }

    private func preparePreview(on display: PopupDisplay, animated: Bool) {
        if let snapshot = previewSnapshot, snapshot.kind == .image || snapshot.kind == .document || snapshot.kind == .files {
            state.previewImage = ClipboardMedia.image(for: snapshot, maximumPixels: 400)
        }
        previewSnapshot = nil
        let maximumWidth = PopupPlacement.previewFrame(on: display).width
        let width = PopupLayout.previewWidth(for: state, maximum: maximumWidth)
        let height = PopupLayout.previewSize.height
        let target = PopupPlacement.previewFrame(on: display, height: height, preferredWidth: width)
        state.canvasWidth = width
        state.canvasHeight = height
        panel.setFrame(target, display: true)
        panel.contentView?.layoutSubtreeIfNeeded()
        if animated {
            withAnimation(state.reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 1)) {
                state.width = width
                state.showsPreview = true
            }
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                state.width = width
                state.showsPreview = true
            }
        }
    }

    private func scheduleDismissal(after duration: TimeInterval, generation current: Int) {
        dismissalTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(duration)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.hideAfterDelay(generation: current)
        }
    }

    func dismiss() {
        generation += 1
        dismissalTask?.cancel()
        dismissalTask = nil
        panel.orderOut(nil)
        panel.alphaValue = 0
        state.isVisible = false
        state.isExpanded = false
        state.showsPreview = false
        state.previewImage = nil
        state.previewText = "Preview hidden"
        previewSnapshot = nil
        targetDisplayID = nil
    }

    func screenConfigurationDidChange() {
        guard state.isVisible else { return }
        let available = displays()
        guard let target = available.first(where: { $0.id == targetDisplayID })
                ?? PopupPlacement.target(pointer: pointer(), displays: available) else { dismiss(); return }
        targetDisplayID = target.id
        let frame = PopupPlacement.frame(on: target)
        if state.showsPreview {
            let maximumWidth = PopupPlacement.previewFrame(on: target).width
            let width = PopupLayout.previewWidth(for: state, maximum: maximumWidth)
            let height = PopupLayout.previewSize.height
            let expandedFrame = PopupPlacement.previewFrame(on: target, height: height, preferredWidth: width)
            state.canvasHeight = height
            state.width = expandedFrame.width
            state.canvasWidth = expandedFrame.width
            panel.setFrame(expandedFrame, display: true)
        } else {
            state.width = frame.width
            panel.setFrame(frame, display: true)
        }
    }

    func stop() {
        dismiss()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        screenObserver = nil
        accessibilityObserver = nil
    }

    private func hideAfterDelay(generation expected: Int) {
        guard expected == generation else { return }
        if reduceMotion() { dismiss(); return }
        state.isExpanded = false
        dismissalTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(PopupLayout.retractionDuration)) } catch { return }
            guard let self, !Task.isCancelled, self.generation == expected else { return }
            self.dismiss()
        }
    }
}

private final class CopyFeedbackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class PopupHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
