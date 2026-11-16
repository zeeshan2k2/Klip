import AppKit
import Observation

@MainActor
@Observable
final class PopupState {
    var isVisible = false
    var reduceMotion = false
    var presentationCount = 0
    var isExpanded: Bool
    var showsPreview = false
    var previewText = "Preview hidden"
    var previewSymbol = "doc.on.doc"
    var previewImage: NSImage?
    var previewIsImage = false
    var canvasWidth: CGFloat = PopupLayout.size.width
    var canvasHeight: CGFloat = PopupLayout.size.height
    var width: CGFloat

    init(isExpanded: Bool = false, width: CGFloat? = nil) {
        self.isExpanded = isExpanded
        self.width = width ?? PopupLayout.size.width
    }
}

enum PopupLayout {
    static let size = NSSize(width: 80, height: 30)
    static let previewSize = NSSize(width: 120, height: 58)
    static let previewPadding: CGFloat = 5
    static let previewHorizontalPadding: CGFloat = 10

    @MainActor
    static func previewWidth(for state: PopupState, maximum: CGFloat) -> CGFloat {
        let contentWidth: CGFloat
        if state.previewIsImage, let image = state.previewImage, image.size.height > 0 {
            let contentHeight = previewSize.height - previewHorizontalPadding * 2
            contentWidth = contentHeight * image.size.width / image.size.height
        } else {
            let text = NSAttributedString(string: state.previewText, attributes: [.font: NSFont.systemFont(ofSize: 12)])
            let iconWidth: CGFloat = state.previewImage == nil ? 20 : 32
            contentWidth = iconWidth + 5 + ceil(text.size().width)
        }
        // Attachment insets sit outside the straight body. Body padding remains
        // ten points horizontally; the existing notch width caps the complete surface.
        return min(maximum, ceil(contentWidth + previewHorizontalPadding * 2 + shoulder * 2))
    }

    static let bottomRadius: CGFloat = 12
    static let shoulder: CGFloat = 8
    static let topCurveDepth: CGFloat = 2
    static let notchOverlap: CGFloat = 3
    static let fallbackNotchWidth: CGFloat = 180
    static let retractionDuration: TimeInterval = 0.24
}

/// Geometry is in desktop points, including negative origins on external displays.
struct PopupDisplay: Equatable {
    let id: UInt32
    let frame: NSRect
    let visibleFrame: NSRect
    let topInset: CGFloat
    let scale: CGFloat
    var notchWidth: CGFloat = 0

    @MainActor
    static func current() -> [PopupDisplay] {
        NSScreen.screens.compactMap { screen -> PopupDisplay? in
            guard let identifier = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let notchWidth: CGFloat
            if screen.safeAreaInsets.top > 0,
               let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
                notchWidth = max(0, screen.frame.width - left.width - right.width)
            } else {
                notchWidth = 0
            }
            return PopupDisplay(id: identifier.uint32Value, frame: screen.frame,
                                visibleFrame: screen.visibleFrame, topInset: screen.safeAreaInsets.top,
                                scale: screen.backingScaleFactor,
                                notchWidth: notchWidth)
        }
    }
}

enum PopupPlacement {
    static func target(pointer: NSPoint, displays: [PopupDisplay]) -> PopupDisplay? {
        displays.first { NSMouseInRect(pointer, $0.frame, false) } ?? displays.first
    }

    static func previewFrame(on display: PopupDisplay, height: CGFloat = PopupLayout.previewSize.height, preferredWidth: CGFloat? = nil) -> NSRect {
        let attachment = frame(on: display)
        let measuredWidth = display.topInset > 0 && display.notchWidth > 0
            ? display.notchWidth : PopupLayout.previewSize.width
        let maximum = min(measuredWidth, display.frame.width - 16)
        let width = min(maximum, max(1, preferredWidth ?? maximum))
        return NSRect(x: display.frame.midX - width / 2,
                      y: attachment.maxY - height,
                      width: width, height: height)
    }

    static func frame(on display: PopupDisplay) -> NSRect {
        let hasNotch = display.topInset > 0
        let notchWidth = display.notchWidth > 0 ? display.notchWidth : PopupLayout.fallbackNotchWidth
        let width = hasNotch
            ? min(PopupLayout.size.width, min(notchWidth + PopupLayout.shoulder * 2, display.frame.width - 16))
            : PopupLayout.size.width
        // A small overlap covers the antialiased seam at the hardware edge.
        // Displays without a notch attach directly to the top screen edge.
        let top = hasNotch
            ? display.frame.maxY - display.topInset + PopupLayout.notchOverlap
            : display.frame.maxY
        let x = display.frame.midX - width / 2
        let y = top - PopupLayout.size.height
        let scale = max(1, display.scale)
        return NSRect(x: (x * scale).rounded() / scale, y: (y * scale).rounded() / scale,
                      width: width, height: PopupLayout.size.height)
    }
}
