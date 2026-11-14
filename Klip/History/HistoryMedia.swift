import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

@MainActor
enum ClipboardMedia {
    static func isImageContent(_ snapshot: ClipboardSnapshot) -> Bool {
        if snapshot.kind == .image || snapshot.kind == .document { return true }
        guard snapshot.kind == .files, let file = snapshot.fileReferences.first,
              let url = file.resolve() else { return false }
        return UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
    }

    private static func thumbnail(from source: CGImageSource, maximumPixels: Int) -> NSImage? {
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixels,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false
        ] as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: .zero)
    }

    static func image(for snapshot: ClipboardSnapshot, maximumPixels: Int) -> NSImage? {
        if snapshot.kind == .files, let file = snapshot.fileReferences.first {
            if isImageContent(snapshot), let url = file.resolve() {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                if let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                   let image = thumbnail(from: source, maximumPixels: maximumPixels) {
                    return image
                }
            }
            return fileIcon(for: file)
        }
        for representation in snapshot.items.flatMap(\.representations) where UTType(representation.type)?.conforms(to: .image) == true {
            guard let source = CGImageSourceCreateWithData(representation.data as CFData, nil),
                  let image = thumbnail(from: source, maximumPixels: maximumPixels) else { continue }
            return image
        }
        if let data = snapshot.items.compactMap(\.pdfData).first,
           let provider = CGDataProvider(data: data as CFData), let pdf = CGPDFDocument(provider),
           let page = pdf.page(at: 1) {
            let rect = page.getBoxRect(.mediaBox)
            guard rect.width > 0, rect.height > 0 else { return nil }
            let scale = min(CGFloat(maximumPixels) / rect.width, CGFloat(maximumPixels) / rect.height, 1)
            let width = max(1, Int(rect.width * scale)), height = max(1, Int(rect.height * scale))
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.setFillColor(NSColor.white.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -rect.minX, y: -rect.minY)
            context.drawPDFPage(page)
            if let image = context.makeImage() { return NSImage(cgImage: image, size: .zero) }
        }
        return nil
    }

    static func fileIcon(for file: ClipboardFileReference) -> NSImage? {
        guard let url = file.resolve(), url.isFileURL else { return nil }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        // Ask Finder's icon provider for the actual item: folders, app bundles,
        // projects, custom icons, and document associations retain their identity.
        if FileManager.default.fileExists(atPath: url.path) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: url.pathExtension) ?? .data)
    }
}

struct HistoryThumbnail: View {
    let item: HistoryItem
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().renderingMode(.original).interpolation(.high).scaledToFit() }
            else { Image(systemName: item.kind.symbol).font(.system(size: 24)).foregroundStyle(.secondary) }
        }
        .frame(width: ClipboardMedia.isImageContent(item.snapshot) ? 68 : 40, height: 44)
        .accessibilityHidden(true)
        .task(id: item.id) { image = ClipboardMedia.image(for: item.snapshot, maximumPixels: 160) }
    }
}

struct HistoryItemPreview: View {
    let item: HistoryItem
    @State private var image: NSImage?
    @State private var fileMessage: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if item.kind == .files {
                if ClipboardMedia.isImageContent(item.snapshot), let image {
                    Image(nsImage: image).resizable().renderingMode(.original).scaledToFit().frame(maxHeight: 320)
                }
                ForEach(Array(item.snapshot.fileReferences.enumerated()), id: \.offset) { _, file in
                    if let url = URL(string: file.originalURL) {
                        HStack(spacing: 10) {
                            NativeFileIcon(file: file)
                            VStack(alignment: .leading, spacing: 4) {
                            Text(url.lastPathComponent).font(.system(size: 13, weight: .medium))
                            Text(url.path).font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                }
                Button("Reveal in Finder") {
                    let access = ClipboardFileAccess(references: item.snapshot.fileReferences)
                    defer { access.stop() }
                    if access.missingFiles { fileMessage = "A file has been deleted or is currently unavailable." }
                    else { NSWorkspace.shared.activateFileViewerSelecting(access.urls); fileMessage = nil }
                }
                if let fileMessage { Text(fileMessage).font(.callout).foregroundStyle(.secondary) }
            } else if item.kind == .image || item.kind == .document {
                if let image { Image(nsImage: image).resizable().renderingMode(.original).interpolation(.high).scaledToFit().frame(maxHeight: 320) }
                else { Text("Preview unavailable. The original clipboard formats are still saved.").foregroundStyle(.secondary) }
                Text(item.title).font(.caption).foregroundStyle(.secondary)
            } else if item.kind == .data {
                Text("This app-specific clipping has no visual preview. Use Copy to paste its saved data into a compatible app.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                Text(item.content)
                    .font(item.kind == .code ? .system(size: 12, design: .monospaced) : .system(size: 13))
                    .textSelection(.enabled)
            }
            if !item.snapshot.unavailableTypes.isEmpty {
                Text("Some source formats couldn’t be captured. Those formats may require the original application.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: item.id) {
            if ClipboardMedia.isImageContent(item.snapshot) { image = ClipboardMedia.image(for: item.snapshot, maximumPixels: 1000) }
        }
    }
}

private struct NativeFileIcon: View {
    let file: ClipboardFileReference
    @State private var image: NSImage?
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().renderingMode(.original).scaledToFit() }
            else { Image(systemName: "doc") }
        }
        .frame(width: 36, height: 40)
        .accessibilityHidden(true)
        .task(id: file.originalURL) { image = ClipboardMedia.fileIcon(for: file) }
    }
}
