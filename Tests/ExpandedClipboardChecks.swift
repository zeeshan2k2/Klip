import AppKit
import Darwin
import ImageIO
import SwiftUI

@main
struct ExpandedClipboardChecks {
    @MainActor
    static func main() throws {
        setbuf(stdout, nil)
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Klip.Expanded.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let writer = ClipboardWriter(pasteboard: board)
        let privacy = PrivacyPolicy()
        var captures: [ClipboardSnapshot] = []
        let monitor = ClipboardMonitor(pasteboard: board, writer: writer, privacy: privacy, sourceApplication: { "test.native.source" }) { captures.append($0) }
        func capture(_ items: [NSPasteboardWriting]) -> ClipboardSnapshot {
            let before = captures.count
            board.clearContents()
            assert(board.writeObjects(items))
            monitor.poll()
            assert(captures.count == before + 1, "An ordinary native clipboard item should be captured")
            return captures.last!
        }
        func native(_ values: [(NSPasteboard.PasteboardType, Data)]) -> NSPasteboardItem {
            let item = NSPasteboardItem()
            for (type, data) in values { item.setData(data, forType: type) }
            return item
        }
        func bytes(_ text: String) -> Data { Data(text.utf8) }
        func roundTrip(_ snapshot: ClipboardSnapshot) {
            assert(writer.write(snapshot), writer.lastError ?? "write failed")
            let restored = board.pasteboardItems!
            assert(restored.count == snapshot.items.count)
            for (original, output) in zip(snapshot.items, restored) {
                for representation in original.representations {
                    if representation.type == "NSFilenamesPboardType" { continue }
                    assert(output.data(forType: NSPasteboard.PasteboardType(representation.type)) == representation.data,
                           "Native representations must survive copy-back exactly")
                }
            }
            let count = captures.count
            monitor.poll()
            assert(captures.count == count, "Copy-back must not recursively capture any of its items")
        }

        let original = "\tlet café = \"مرحبا 👋\"\n  return café\n"
        let styled = NSAttributedString(string: original, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.red])
        let rtf = styled.rtf(from: NSRange(location: 0, length: styled.length), documentAttributes: [:])!
        let xcodeType = NSPasteboard.PasteboardType("com.apple.dt.Xcode.sourceCode")
        let privateType = NSPasteboard.PasteboardType("com.example.editor.private-clipping")
        let opaque = Data([0, 1, 2, 0xff, 0x80, 0, 0x42])
        let code = capture([native([(.string, bytes(original)), (.rtf, rtf), (xcodeType, opaque)])])
        assert(code.kind == .code && code.content == original && Set(code.items[0].representations.map(\.type)).isSuperset(of: [NSPasteboard.PasteboardType.string.rawValue, NSPasteboard.PasteboardType.rtf.rawValue, xcodeType.rawValue]))
        roundTrip(code)
        let destinationText = (board.readObjects(forClasses: [NSAttributedString.self], options: nil) as? [NSAttributedString])?.first
        assert(destinationText?.string == original)
        assert(destinationText?.attribute(.foregroundColor, at: 0, effectiveRange: nil) != nil)
        let rich = capture([native([(.rtf, rtf)])])
        assert(rich.kind == .richText && rich.content == original)
        roundTrip(rich)
        let htmlData = bytes("<p>Hello <b>world</b><img src='https://example.invalid/never-load'></p>")
        let html = capture([native([(.html, htmlData)])])
        assert(html.kind == .richText && html.content.contains("Hello"))
        roundTrip(html)
        let rtfd = styled.rtfd(from: NSRange(location: 0, length: styled.length), documentAttributes: [:])!
        let richPackage = capture([native([(.rtfd, rtfd)])])
        assert(richPackage.kind == .richText && richPackage.content == original)
        roundTrip(richPackage)
        print("PASS: exact text, syntax-formatted RTF, HTML, RTFD, Xcode metadata, and attributed destination reading")

        let context = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        let bitmap = NSBitmapImageRep(cgImage: context.makeImage()!)
        let png = bitmap.representation(using: .png, properties: [:])!
        let tiff = bitmap.representation(using: .tiff, properties: [:])!
        let image = capture([native([(.png, png), (.tiff, tiff)])])
        assert(image.kind == .image && image.content.contains("64 × 32"))
        assert(ClipboardMedia.image(for: image, maximumPixels: 88) != nil)
        let preview = ClipboardMedia.image(for: image, maximumPixels: 160)!
        let previewBitmap = NSBitmapImageRep(data: preview.tiffRepresentation!)!
        let pixel = previewBitmap.colorAt(x: previewBitmap.pixelsWide / 2, y: previewBitmap.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
        let originalPixel = NSBitmapImageRep(data: png)!.colorAt(x: 32, y: 16)!.usingColorSpace(.deviceRGB)!
        assert(abs(pixel.redComponent - originalPixel.redComponent) < 0.02
               && abs(pixel.greenComponent - originalPixel.greenComponent) < 0.02
               && abs(pixel.blueComponent - originalPixel.blueComponent) < 0.02,
               "The thumbnail must preserve the copied image's colors")
        var alternateImage = image
        alternateImage.items = [ClipboardPayloadItem(representations: [
            ClipboardRepresentation(type: NSPasteboard.PasteboardType.png.rawValue, data: Data([0, 1])),
            ClipboardRepresentation(type: NSPasteboard.PasteboardType.tiff.rawValue, data: tiff)])]
        assert(ClipboardMedia.image(for: alternateImage, maximumPixels: 160) != nil,
               "An unreadable first image format must fall back to the valid alternative")
        roundTrip(image)
        assert((board.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage])?.first != nil)
        let pdfBytes = NSMutableData()
        var pageRect = CGRect(x: 0, y: 0, width: 300, height: 200)
        let pdfContext = CGContext(consumer: CGDataConsumer(data: pdfBytes)!, mediaBox: &pageRect, nil)!
        pdfContext.beginPDFPage(nil)
        pdfContext.setFillColor(NSColor.blue.cgColor)
        pdfContext.fill(pageRect)
        pdfContext.endPDFPage()
        pdfContext.closePDF()
        let pdf = capture([native([(.pdf, pdfBytes as Data)])])
        assert(pdf.kind == .document && ClipboardMedia.image(for: pdf, maximumPixels: 88) != nil)
        roundTrip(pdf)
        print("PASS: PNG/TIFF original bytes, native image reading, image thumbnails, PDF data, and PDF page previews")

        let generic = capture([native([(privateType, opaque)])])
        assert(generic.kind == .data && generic.items[0].representations[0].data == opaque)
        roundTrip(generic)
        let multiple = capture([native([(.string, bytes("first item")), (privateType, Data([1]))]),
                                native([(.string, bytes("second item")), (privateType, Data([2]))])])
        assert(multiple.items.count == 2 && multiple.content == "first item\nsecond item")
        roundTrip(multiple)
        let binaryGroups = capture([native([(.png, png)]), native([(privateType, opaque)])])
        roundTrip(binaryGroups)
        let store = ClipboardHistoryStore()
        assert(store.record(generic))
        assert(!store.record(generic))
        let different = capture([native([(privateType, Data([9, 8, 7]))])])
        assert(store.record(different) && store.items.count == 2,
               "Two opaque clippings with the same caption must not be deduplicated")
        print("PASS: unknown binary app formats, multiple-item grouping, mixed payloads, and representation-based deduplication")

        let file = directory.appendingPathComponent("Example.swift")
        let project = directory.appendingPathComponent("Example.xcodeproj", isDirectory: true)
        try bytes("fixture file contents").write(to: file)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let files = capture([file as NSURL, project as NSURL])
        assert(files.kind == .files && files.items.count == 2 && files.fileReferences.count == 2)
        assert(files.content.contains("+ 1 other files"))
        let folderIcon = ClipboardMedia.fileIcon(for: files.fileReferences[1])!
        assert(folderIcon.tiffRepresentation == NSWorkspace.shared.icon(forFile: project.path).tiffRepresentation,
               "Project folders must use the actual macOS item icon")
        let copiedImageFile = directory.appendingPathComponent("Screenshot.png")
        try png.write(to: copiedImageFile)
        let finderImage = capture([native([
            (.fileURL, bytes(copiedImageFile.absoluteString)),
            (.tiff, NSWorkspace.shared.icon(forFile: copiedImageFile.path).tiffRepresentation!)])])
        assert(finderImage.kind == .files && ClipboardMedia.isImageContent(finderImage))
        let finderThumbnail = ClipboardMedia.image(for: finderImage, maximumPixels: 160)!
        let finderBitmap = NSBitmapImageRep(data: finderThumbnail.tiffRepresentation!)!
        assert(finderBitmap.pixelsWide == 64 && finderBitmap.pixelsHigh == 32,
               "Finder image copies must preview the actual file, not the attached file-icon TIFF")
        let finderPixel = finderBitmap.colorAt(x: 32, y: 16)!.usingColorSpace(.deviceRGB)!
        assert(abs(finderPixel.redComponent - originalPixel.redComponent) < 0.02
               && abs(finderPixel.greenComponent - originalPixel.greenComponent) < 0.02)
        let notchDisplay = PopupDisplay(id: 99, frame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 950), topInset: 32, scale: 2, notchWidth: 185)
        let notch = PopupController(displays: { [notchDisplay] }, pointer: { .zero }, reduceMotion: { true })
        for (name, snapshot) in [("image", image), ("files", files), ("finder-image", finderImage)] {
            notch.setPreview(snapshot)
            notch.showCopied()
            notch.expandPreview()
            assert(notch.panel.frame.width <= notchDisplay.notchWidth && notch.state.previewImage != nil)
            assert(notch.panel.frame.height == 58 && abs(notch.panel.frame.midX - notchDisplay.frame.midX) <= 0.5)
            if ClipboardMedia.isImageContent(snapshot) {
                assert(notch.panel.frame.width == 38 * 2 + 20 + PopupLayout.shoulder * 2,
                       "Landscape image width must hug its actual content with ten-point horizontal body padding")
            }
            assert(notch.state.previewIsImage == ClipboardMedia.isImageContent(snapshot))
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            let host = notch.panel.contentView!
            host.layoutSubtreeIfNeeded()
            let output = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
            host.cacheDisplay(in: host.bounds, to: output)
            if ClipboardMedia.isImageContent(snapshot) {
                let middleY = output.pixelsHigh / 2
                let middleX = output.pixelsWide / 2
                func opaque(_ x: Int, _ y: Int) -> Bool { output.colorAt(x: x, y: y)!.alphaComponent > 0.9 }
                func red(_ x: Int, _ y: Int) -> Bool {
                    let color = output.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    return color.alphaComponent > 0.9 && color.redComponent > 0.6 && color.greenComponent < 0.4 && color.blueComponent < 0.4
                }
                let bodyX = (0..<output.pixelsWide).filter { opaque($0, middleY) }
                let photoX = (0..<output.pixelsWide).filter { red($0, middleY) }
                let bodyY = (0..<output.pixelsHigh).filter { opaque(middleX, $0) }
                let photoY = (0..<output.pixelsHigh).filter { red(middleX, $0) }
                let scale = CGFloat(output.pixelsWide) / notch.panel.frame.width
                let gaps = [photoX.first! - bodyX.first!, bodyX.last! - photoX.last!,
                            photoY.first! - bodyY.first!, bodyY.last! - photoY.last!]
                assert(gaps.allSatisfy { abs(CGFloat($0) / scale - 10) <= 1 },
                       "Rendered photo must have ten-point padding at every black body edge: \(gaps)")
            }
            try output.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/klip-narrow-\(name).png"))
        }
        notch.stop()
        print("PASS: Finder PNG preview uses file pixels instead of icon payload; preview width hugs content within measured 185-point notch maximum")
        assert(writer.write(files))
        let urls = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])!
        assert(Set(urls.map { $0.resolvingSymlinksInPath().path }) == Set([file, project].map { $0.resolvingSymlinksInPath().path }))
        let renamed = directory.appendingPathComponent("Renamed.swift")
        try FileManager.default.moveItem(at: file, to: renamed)
        if files.fileReferences[0].bookmark != nil {
            assert(writer.write(files), "A bookmark should follow a rename in the same folder")
            let movedURLs = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as! [URL]
            assert(Set(movedURLs.map { $0.resolvingSymlinksInPath().path }) == Set([renamed, project].map { $0.resolvingSymlinksInPath().path }))
        }
        try FileManager.default.removeItem(at: renamed)
        board.clearContents()
        board.setString("leave current clipboard intact", forType: .string)
        assert(!writer.write(files) && writer.lastError != nil)
        assert(board.string(forType: .string) == "leave current clipboard intact")
        let legacyPaths = try PropertyListSerialization.data(fromPropertyList: [project.path], format: .binary, options: 0)
        let legacyFiles = ClipboardSnapshot(content: project.lastPathComponent, kind: .files, changeCount: 0,
            capturedAt: Date(), sourceApplicationID: nil,
            items: [ClipboardPayloadItem(representations: [ClipboardRepresentation(type: "NSFilenamesPboardType", data: legacyPaths)],
                                         files: [ClipboardFileReference.capture(project)])])
        assert(legacyFiles.kind == .files && legacyFiles.fileReferences.count == 1)
        assert(writer.write(legacyFiles))
        assert((board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first?.resolvingSymlinksInPath().path == project.resolvingSymlinksInPath().path)
        print("PASS: native multi-file/folder copies, Xcode project references, bookmarks, moved/missing files, and legacy file lists")

        let archive = JSONHistoryPersistence(fileURL: directory.appendingPathComponent("saved/History.json"))
        let saved = [finderImage, image, legacyFiles, code, rich, html, richPackage, pdf, generic, multiple, binaryGroups].map { HistoryItem(snapshot: $0) }
        try archive.save(saved)
        let loaded = try archive.load()
        assert(loaded.map(\.id) == saved.map(\.id))
        for (before, after) in zip(saved, loaded) {
            assert(before.snapshot.items == after.snapshot.items && before.kind == after.kind && before.content == after.content)
            roundTrip(after.snapshot)
        }
        let migrationURL = directory.appendingPathComponent("version-one.json")
        let oldID = UUID()
        let oldArchive: [String: Any] = ["version": 1, "items": [["id": oldID.uuidString, "content": "old saved text",
                                                               "kind": "Text", "capturedAt": Date().timeIntervalSince1970 * 1000]]]
        try JSONSerialization.data(withJSONObject: oldArchive).write(to: migrationURL)
        let migration = JSONHistoryPersistence(fileURL: migrationURL)
        let old = try migration.load()
        assert(old.count == 1 && old[0].id == oldID && old[0].content == "old saved text")
        assert(writer.write(old[0].snapshot) && board.string(forType: .string) == "old saved text")
        try migration.save(old + saved)
        assert(tryCount(migration) == saved.count + 1)
        print("PASS: version-2 binary persistence, every format restored after reload, and non-destructive version-1 migration")

        let missingType = NSPasteboard.PasteboardType("com.example.promised-format")
        let partialWriter = ClipboardWriter(pasteboard: board)
        var partialSnapshot: ClipboardSnapshot?
        let partialMonitor = ClipboardMonitor(pasteboard: board, writer: partialWriter, privacy: PrivacyPolicy(),
            readData: { item, type in type == missingType ? nil : item.data(forType: type) }, onCapture: { partialSnapshot = $0 })
        board.clearContents()
        board.writeObjects([native([(.string, bytes("available text")), (missingType, opaque)])])
        partialMonitor.poll()
        assert(partialMonitor.status == .partial && partialSnapshot?.unavailableTypes == [missingType.rawValue])
        var oversizedCaptured = false
        let oversizedMonitor = ClipboardMonitor(pasteboard: board, writer: partialWriter, privacy: PrivacyPolicy(),
            readData: { _, _ in Data(count: ClipboardMonitor.maximumPayloadBytes + 1) }, onCapture: { _ in oversizedCaptured = true })
        board.clearContents()
        board.writeObjects([native([(privateType, Data([1]))])])
        oversizedMonitor.poll()
        assert(oversizedMonitor.status == .tooLarge && !oversizedCaptured)
        let sensitive = NSPasteboardItem()
        sensitive.setData(png, forType: .png)
        sensitive.setString("1", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        let count = captures.count
        board.clearContents()
        board.writeObjects([sensitive])
        monitor.poll()
        assert(captures.count == count)
        print("PASS: explicit partial-format status, payload bounds, and sensitive-image suppression")

        let model = HistoryViewModel(store: ClipboardHistoryStore(items: saved))
        let frameName = "Klip.Expanded.Preview.\(UUID().uuidString)"
        let panel = HistoryPanelController(model: model, frameAutosaveName: frameName)
        panel.showWindow(nil)
        panel.window!.setContentSize(NSSize(width: 420, height: 600))
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        let hosting = panel.window!.contentView!
        hosting.layoutSubtreeIfNeeded()
        let rendered = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
        hosting.cacheDisplay(in: hosting.bounds, to: rendered)
        try rendered.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/klip-expanded-history.png"))
        panel.dismiss()
        panel.window?.setFrameAutosaveName("")
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame \(frameName)")
        print("All expanded clipboard checks passed. No general clipboard, external sharing, or user files were used.")
    }

    @MainActor
    private static func tryCount(_ archive: JSONHistoryPersistence) -> Int { (try? archive.load())?.count ?? -1 }
}
