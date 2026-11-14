import AppKit
import SwiftUI

enum HistoryStyle {
    static let width: CGFloat = 360
    static let height: CGFloat = 404
    static let minimumWidth: CGFloat = 300
    static let minimumHeight: CGFloat = 240
    static let cornerRadius: CGFloat = 18
    static let rowHeight: CGFloat = 58
    static let accent = Color(red: 0.19, green: 0.49, blue: 0.98)

    static func header(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.14, green: 0.15, blue: 0.16).opacity(0.70)
            : Color.white.opacity(0.35)
    }

    static func list(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.25, green: 0.28, blue: 0.31).opacity(0.50)
            : Color.white.opacity(0.28)
    }
}

/// Native backdrop blur samples the windows behind Klip rather than drawing a gradient.
struct RoundedGlassBackground: NSViewRepresentable {
    var cornerRadius: CGFloat = HistoryStyle.cornerRadius
    var material: NSVisualEffectView.Material = .popover

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        // The backdrop is composited by AppKit, so it needs its own shape mask.
        let radius = cornerRadius
        let mask = NSImage(size: NSSize(width: radius * 2 + 2, height: radius * 2 + 2), flipped: false) { rect in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        mask.resizingMode = .stretch
        view.maskImage = mask
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = material }
}

/// Explicit native drag targets in the unused parts of the header. Restricting their
/// bounds keeps the gear, collection menu, search, rows, and sharing interactive.
struct HistoryWindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
