import AppKit
import SwiftUI

/// Give macOS the actual file/image/attributed content, rather than sharing its row caption.
struct HistoryShareButton: NSViewRepresentable {
    let item: HistoryItem
    let isSelected: Bool

    func makeCoordinator() -> Coordinator { Coordinator(item: item) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share clipboard item")!,
                              target: context.coordinator, action: #selector(Coordinator.share(_:)))
        // AppKit's picker must be presented on mouse-down.
        button.sendAction(on: .leftMouseDown)
        button.isBordered = false
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Share"
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.item = item
        button.contentTintColor = isSelected ? .white : .labelColor
    }

    @MainActor
    final class Coordinator: NSObject, NSSharingServicePickerDelegate, NSSharingServiceDelegate {
        private static var active: [ObjectIdentifier: Coordinator] = [:]
        var item: HistoryItem
        private var access: ClipboardFileAccess?
        private var picker: NSSharingServicePicker?
        init(item: HistoryItem) { self.item = item }

        @objc func share(_ sender: NSButton) {
            guard picker == nil else { return }
            var objects: [Any] = []
            if !item.snapshot.fileReferences.isEmpty {
                let access = ClipboardFileAccess(references: item.snapshot.fileReferences)
                guard !access.missingFiles else {
                    access.stop()
                    let alert = NSAlert()
                    alert.messageText = "File unavailable"
                    alert.informativeText = "A referenced file is missing or cannot be accessed."
                    if let window = sender.window { alert.beginSheetModal(for: window) }
                    return
                }
                self.access = access
                objects = access.urls
            } else {
                for payload in item.snapshot.items {
                    if let data = payload.imageData, let image = NSImage(data: data) { objects.append(image) }
                    else if let text = payload.attributedText { objects.append(text) }
                    else if let text = payload.text { objects.append(text) }
                    else {
                        let native = NSPasteboardItem()
                        payload.representations.forEach { native.setData($0.data, forType: NSPasteboard.PasteboardType($0.type)) }
                        objects.append(native)
                    }
                }
                if objects.isEmpty { objects = [item.content] }
            }
            let picker = NSSharingServicePicker(items: objects)
            picker.delegate = self
            self.picker = picker
            picker.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }

        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, delegateFor service: NSSharingService) -> (any NSSharingServiceDelegate)? {
            Self.active[ObjectIdentifier(self)] = self
            return self
        }

        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            if let service {
                Self.active[ObjectIdentifier(self)] = self
                service.delegate = self
            } else { finish() }
        }
        func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) { finish() }
        func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) { finish() }
        private func finish() {
            access?.stop()
            access = nil
            picker = nil
            Self.active.removeValue(forKey: ObjectIdentifier(self))
        }
    }
}
