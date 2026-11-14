import AppKit

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
            for representation in payload.representations {
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
}
