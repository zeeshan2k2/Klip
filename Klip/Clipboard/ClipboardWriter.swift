import AppKit
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class ClipboardWriter {
    static let internalType = NSPasteboard.PasteboardType("com.klip.internal-write")
    private let pasteboard: NSPasteboard
    private(set) var lastWrittenChangeCount: Int?
    private(set) var lastError: String?

    init(pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }

    @discardableResult
    func write(_ snapshot: ClipboardSnapshot) -> Bool {
        lastError = nil
        if snapshot.items.isEmpty && [.image, .files, .document, .data].contains(snapshot.kind) {
            lastError = "This older clipping has no saved original data. Copy the original again; its preview label cannot be pasted as content."
            return false
        }
        if snapshot.kind == .image && !snapshot.items.contains(where: { $0.imageData != nil }) {
            lastError = "This clipping has no saved image data. Copy the original image again."
            return false
        }
        let access = ClipboardFileAccess(references: snapshot.fileReferences)
        defer { access.stop() }
        guard !access.missingFiles else {
            lastError = "A referenced file is missing or unavailable. The current clipboard was left unchanged."
            return false
        }
        var items: [NSPasteboardItem] = []
        var fileIndex = 0
        for payload in snapshot.items {
            let item = NSPasteboardItem()
            let representations: [ClipboardRepresentation]
            if snapshot.kind == .image && payload.files.isEmpty && payload.imageData != nil {
                guard let image = Self.imageRepresentations(payload) else {
                    lastError = "The saved image data is unavailable or unreadable. Copy the original image again."
                    return false
                }
                representations = image
            } else {
                representations = payload.representations
            }
            for representation in representations {
                // Modern item APIs reject the obsolete filename-list type. The
                // file references below provide its canonical file-URL equivalent.
                if representation.type == "NSFilenamesPboardType" && !payload.files.isEmpty { continue }
                guard item.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type)) else {
                    lastError = "macOS couldn’t restore one of this clipping’s formats. The current clipboard was left unchanged."
                    return false
                }
            }
            if !payload.files.isEmpty {
                let urls = Array(access.urls[fileIndex..<(fileIndex + payload.files.count)])
                fileIndex += payload.files.count
                let originals = payload.files.compactMap { URL(string: $0.originalURL) }
                let moved = zip(originals, urls).contains { $0.resolvingSymlinksInPath().path != $1.resolvingSymlinksInPath().path }
                if let first = urls.first, moved || payload.data(for: .fileURL) == nil {
                    item.setString(first.absoluteString, forType: .fileURL)
                }
                item.setString("Klip", forType: Self.internalType)
                items.append(item)
                for url in urls.dropFirst() {
                    let additional = NSPasteboardItem()
                    additional.setString(url.absoluteString, forType: .fileURL)
                    additional.setString("Klip", forType: Self.internalType)
                    items.append(additional)
                }
            } else if !payload.representations.isEmpty {
                item.setString("Klip", forType: Self.internalType)
                items.append(item)
            }
        }
        // Version-1 archives and programmatically created plain-text entries.
        if snapshot.items.isEmpty {
            let item = NSPasteboardItem()
            item.setString(snapshot.content, forType: .string)
            if snapshot.kind == .link { item.setString(snapshot.content, forType: .URL) }
            item.setString("Klip", forType: Self.internalType)
            items.append(item)
        }
        guard !items.isEmpty else { lastError = "No reusable clipboard data was saved for this item."; return false }
        pasteboard.clearContents()
        let succeeded = pasteboard.writeObjects(items)
        lastWrittenChangeCount = pasteboard.changeCount
        if !succeeded { lastError = "Couldn’t write this item to the clipboard. Please try again." }
        return succeeded
    }

    static func isImageTextFallback(_ representation: ClipboardRepresentation) -> Bool {
        let type = UTType(representation.type)
        if type?.conforms(to: .image) == true { return false }
        return type?.conforms(to: .text) == true || type?.conforms(to: .url) == true
            || [NSPasteboard.PasteboardType.string.rawValue, NSPasteboard.PasteboardType.html.rawValue,
                NSPasteboard.PasteboardType.rtf.rawValue, NSPasteboard.PasteboardType.rtfd.rawValue,
                NSPasteboard.PasteboardType.URL.rawValue, "Apple Web Archive pasteboard type", "com.apple.webarchive"].contains(representation.type)
    }

    private static func imageRepresentations(_ payload: ClipboardPayloadItem) -> [ClipboardRepresentation]? {
        let images = payload.representations.filter { UTType($0.type)?.conforms(to: .image) == true }
        guard let original = images.first else { return nil }
        // Formats such as SVG may be reusable by the destination even when
        // ImageIO cannot decode them. Preserve those originals too.
        let valid = images.first(where: {
            guard let source = CGImageSourceCreateWithData($0.data as CFData, nil) else { return false }
            return CGImageSourceGetCount(source) > 0
        }) ?? original
        // Keep every original image byte. HTML/URL/text accompanying browser image
        // copies can otherwise win format negotiation and paste a label or link.
        var output = images + payload.representations.filter {
            UTType($0.type)?.conforms(to: .image) != true && !isImageTextFallback($0)
        }
        // PNG-only browser copies need TIFF for native image consumers. Bound the
        // conversion by pixel count independently of compressed input size.
        let types = Set(output.map(\.type))
        if !types.contains(NSPasteboard.PasteboardType.tiff.rawValue) || !types.contains(NSPasteboard.PasteboardType.png.rawValue),
           let source = CGImageSourceCreateWithData(valid.data as CFData, nil),
           let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = info[kCGImagePropertyPixelWidth] as? NSNumber,
           let height = info[kCGImagePropertyPixelHeight] as? NSNumber,
           width.doubleValue > 0, height.doubleValue > 0,
           width.doubleValue * height.doubleValue <= 16_000_000,
           let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary) {
            let bitmap = NSBitmapImageRep(cgImage: image)
            for (type, format) in [(NSPasteboard.PasteboardType.tiff, NSBitmapImageRep.FileType.tiff), (.png, .png)] where !types.contains(type.rawValue) {
                if let data = bitmap.representation(using: format, properties: [:]), data.count <= ClipboardMonitor.maximumPayloadBytes {
                    output.append(ClipboardRepresentation(type: type.rawValue, data: data))
                }
            }
        }
        return output
    }
}

/// Sends Paste only after the destination has focus and the invoking keys are released.
/// Dependencies are injectable so checks never post real keyboard events.
@MainActor
final class ClipboardPaster {
    struct Destination {
        let isRunning: () -> Bool
        let isActive: () -> Bool
        let activate: () -> Void
    }

    private let permission: (_ prompt: Bool) -> Bool
    private let frontmost: () -> Destination?
    private let modifiersReleased: () -> Bool
    private let postPaste: () -> Bool
    private let clipboardUnchanged: (_ expectedCount: Int) -> Bool
    private var destination: Destination?
    private var pending: Task<Void, Never>?

    init(permission: @escaping (Bool) -> Bool = { prompt in
             CGPreflightPostEventAccess() || (prompt && CGRequestPostEventAccess())
         },
         frontmost: @escaping () -> Destination? = {
             guard let app = NSWorkspace.shared.frontmostApplication,
                   app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
             return Destination(isRunning: { !app.isTerminated }, isActive: { NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier },
                                activate: { app.activate(options: []) })
         },
         modifiersReleased: @escaping () -> Bool = {
             NSEvent.modifierFlags.intersection([.command, .shift, .control, .option]).isEmpty
         },
         clipboardUnchanged: @escaping (Int) -> Bool = { NSPasteboard.general.changeCount == $0 },
         postPaste: @escaping () -> Bool = {
             guard let source = CGEventSource(stateID: .privateState),
                   let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                   let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return false }
             down.flags = .maskCommand
             up.flags = .maskCommand
             down.post(tap: .cgSessionEventTap)
             up.post(tap: .cgSessionEventTap)
             return true
         }) {
        self.permission = permission
        self.frontmost = frontmost
        self.modifiersReleased = modifiersReleased
        self.clipboardUnchanged = clipboardUnchanged
        self.postPaste = postPaste
    }

    func captureDestination() {
        cancel()
        destination = frontmost()
    }

    func preparationError() -> String? {
        guard destination?.isRunning() == true else {
            return "Copied. Open history from the app you want to paste into, or press ⌘V there."
        }
        guard permission(true) else {
            return "Copied. Allow Klip in System Settings → Privacy & Security → Accessibility, then press Return again. You can also paste manually with ⌘V."
        }
        return nil
    }

    func paste(changeCount: Int, onFailure: @escaping (String) -> Void) {
        cancel()
        guard let destination else { return }
        // The history panel is nonactivating. Usually the original app still owns
        // activation; activating it again can dismiss its Spotlight/search overlay.
        if !destination.isActive() { destination.activate() }
        pending = Task { @MainActor [weak self] in
            // Let AppKit finish dismissing the panel and restoring the text field.
            try? await Task.sleep(for: .milliseconds(60))
            guard let self, !Task.isCancelled else { return }
            for _ in 0..<100 {
                guard !Task.isCancelled else { return }
                guard destination.isRunning(), self.clipboardUnchanged(changeCount) else {
                    onFailure("Paste cancelled because the app closed or the clipboard changed. Select the item again.")
                    return
                }
                if destination.isActive() && self.modifiersReleased() {
                    guard self.permission(false), self.postPaste() else {
                        onFailure("Copied, but macOS could not send Paste. Check Klip’s Accessibility permission, or paste with ⌘V.")
                        return
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
            onFailure("Copied, but the destination did not become ready. Switch to it and press ⌘V.")
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
    }
}
