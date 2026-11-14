import AppKit
import ImageIO
import UniformTypeIdentifiers

struct ClipboardRepresentation: Codable, Equatable {
    let type: String
    let data: Data
}

struct ClipboardFileReference: Codable, Equatable {
    let originalURL: String
    let bookmark: Data?

    static func capture(_ url: URL) -> ClipboardFileReference {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let bookmark = (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData(options: [.minimalBookmark], includingResourceValuesForKeys: nil, relativeTo: nil))
        return ClipboardFileReference(originalURL: url.absoluteString, bookmark: bookmark)
    }

    func resolve() -> URL? {
        if let bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale), url.isFileURL { return url }
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale), url.isFileURL { return url }
        }
        guard let url = URL(string: originalURL), url.isFileURL else { return nil }
        return url
    }
}

struct ClipboardPayloadItem: Codable, Equatable {
    let representations: [ClipboardRepresentation]
    var files: [ClipboardFileReference] = []

    func data(for type: NSPasteboard.PasteboardType) -> Data? {
        representations.first { $0.type == type.rawValue }?.data
    }
    var byteCount: Int {
        representations.reduce(0) { $0 + $1.data.count + $1.type.utf8.count }
            + files.reduce(0) { $0 + $1.originalURL.utf8.count + ($1.bookmark?.count ?? 0) }
    }
    var text: String? {
        if let data = data(for: .string) { return ClipboardPayloadSummary.decodeText(data, type: NSPasteboard.PasteboardType.string.rawValue) }
        if let value = representations.first(where: { UTType($0.type)?.conforms(to: .plainText) == true }) {
            return ClipboardPayloadSummary.decodeText(value.data, type: value.type)
        }
        if let attributed = attributedText { return String(attributed.string.prefix(ClipboardMonitor.maximumTextBytes)) }
        if let data = data(for: .html), let html = String(data: data.prefix(ClipboardMonitor.maximumTextBytes), encoding: .utf8) {
            // Do not invoke an HTML/WebKit importer or load external resources.
            return html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        }
        if let data = data(for: .URL) { return ClipboardPayloadSummary.decodeText(data, type: NSPasteboard.PasteboardType.URL.rawValue) }
        return nil
    }
    var attributedText: NSAttributedString? {
        if let data = data(for: .rtf) { return NSAttributedString(rtf: data, documentAttributes: nil) }
        if let data = data(for: .rtfd) { return NSAttributedString(rtfd: data, documentAttributes: nil) }
        return nil
    }
    var imageData: Data? {
        representations.first { UTType($0.type)?.conforms(to: .image) == true }?.data
    }
    var pdfData: Data? { data(for: .pdf) }
}

enum ClipboardPayloadSummary {
    static func decodeText(_ data: Data, type: String) -> String? {
        let limited = data.prefix(ClipboardMonitor.maximumTextBytes)
        if type.contains("utf16") { return String(data: limited, encoding: .utf16) ?? String(data: limited, encoding: .utf16LittleEndian) }
        return String(decoding: limited, as: UTF8.self)
    }

    static func describe(_ items: [ClipboardPayloadItem]) -> (String, ClipboardSnapshot.Kind) {
        let files = items.flatMap(\.files)
        if !files.isEmpty {
            let names = files.compactMap { URL(string: $0.originalURL)?.lastPathComponent }
            let first = names.first ?? "File"
            return (names.count == 1 ? first : "\(first) + \(names.count - 1) other files", .files)
        }
        if let data = items.compactMap(\.imageData).first {
            var description = "Image"
            if let source = CGImageSourceCreateWithData(data as CFData, nil),
               let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
               let height = properties[kCGImagePropertyPixelHeight] as? NSNumber {
                description += " · \(width.intValue) × \(height.intValue)"
            }
            if items.count > 1 { description += " · \(items.count) items" }
            return (description, .image)
        }
        if items.contains(where: { $0.pdfData != nil }) { return ("PDF document", .document) }
        let types = items.flatMap(\.representations).map { $0.type.lowercased() }
        let isCode = types.contains { $0.contains("xcode") || UTType($0)?.conforms(to: .sourceCode) == true }
        let isRich = items.contains { $0.data(for: .rtf) != nil || $0.data(for: .rtfd) != nil || $0.data(for: .html) != nil }
        let text = items.compactMap(\.text).joined(separator: "\n")
        if !text.isEmpty {
            return (String(text.prefix(ClipboardMonitor.maximumTextBytes)), isCode ? .code : isRich ? .richText : ContentClassifier().classify(text))
        }
        return (isCode ? "Xcode clipping" : "Application clipping", isCode ? .code : .data)
    }
}

/// Security-scoped access lasts for the explicit copy/share/reveal operation only.
@MainActor
final class ClipboardFileAccess {
    let urls: [URL]
    let missingFiles: Bool
    private var accessed: [URL]

    init(references: [ClipboardFileReference]) {
        let resolved = references.compactMap { $0.resolve() }
        urls = resolved
        accessed = resolved.filter { $0.startAccessingSecurityScopedResource() }
        missingFiles = resolved.count != references.count || resolved.contains { !FileManager.default.fileExists(atPath: $0.path) }
    }

    func stop() {
        let active = accessed
        accessed = []
        active.forEach { $0.stopAccessingSecurityScopedResource() }
    }
}
