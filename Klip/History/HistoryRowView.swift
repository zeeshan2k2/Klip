import AppKit
import SwiftUI

struct HistoryRowView: View {
    let item: HistoryItem
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onInspect: () -> Void
    let onRemove: () -> Void
    let onCopy: () -> Void
    var hidePreview = false

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            content
            if isSelected || isHovered { shareButton }
            Text(index < 9 ? "⌘\(index + 1)" : String(index + 1))
                .font(.system(size: 12).italic())
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(width: 33)
                .padding(.trailing, 2)
                .overlay(interactionSurface)
        }
        .frame(height: HistoryStyle.rowHeight)
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .background(isSelected ? HistoryStyle.accent : Color.primary.opacity(isHovered ? 0.04 : 0))
        .overlay(alignment: .bottom) {
            if !isSelected {
                Rectangle()
                    .fill(Color.primary.opacity(0.13))
                    .frame(height: 1)
                    .padding(.leading, 11)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Copy", systemImage: "doc.on.doc", action: onCopy)
            Button("View", systemImage: "eye", action: onInspect)
            Button("Delete", systemImage: "trash", role: .destructive, action: onRemove)
        }
        .accessibilityAction(named: "Copy", onCopy)
        .accessibilityAction(named: "View item", onInspect)
        .accessibilityAction(named: "Delete item", onRemove)
    }

    private var content: some View {
        HStack(spacing: 10) {
            if item.hasMedia && !hidePreview { HistoryThumbnail(item: item) }
            Text(hidePreview ? "\(item.kind.rawValue) item" : item.title)
                .font(.system(size: 15, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 11)
        .frame(maxHeight: .infinity)
        .overlay(interactionSurface)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hidePreview ? "\(item.kind.rawValue) item, preview hidden" : "\(item.kind.rawValue): \(item.title)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction { onSelect() }
    }

    private var interactionSurface: some View {
        HistoryRowInteraction(onSelect: onSelect, onInspect: onInspect, onRemove: onRemove, onCopy: onCopy)
            .accessibilityHidden(true)
    }

    private var shareButton: some View {
        HistoryShareButton(item: item, isSelected: isSelected)
            .frame(width: 36, height: 40)
            .accessibilityLabel("Share clipboard item")
    }

}

/// Native click counts keep selection immediate and distinguish double-click preview
/// without delaying a single click or intercepting the separate Share control.
private struct HistoryRowInteraction: NSViewRepresentable {
    let onSelect: () -> Void
    let onInspect: () -> Void
    let onRemove: () -> Void
    let onCopy: () -> Void

    func makeNSView(context: Context) -> ClickView { ClickView() }

    func updateNSView(_ view: ClickView, context: Context) {
        view.onSelect = onSelect
        view.onInspect = onInspect
        view.onRemove = onRemove
        view.onCopy = onCopy
    }

    final class ClickView: NSView {
        var onSelect: () -> Void = {}
        var onInspect: () -> Void = {}
        var onRemove: () -> Void = {}
        var onCopy: () -> Void = {}

        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            onSelect()
            if event.clickCount == 2 { onInspect() }
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let menu = NSMenu()
            let copy = menu.addItem(withTitle: "Copy", action: #selector(copyItem), keyEquivalent: "")
            copy.target = self
            let view = menu.addItem(withTitle: "View", action: #selector(inspect), keyEquivalent: "")
            view.target = self
            let delete = menu.addItem(withTitle: "Delete", action: #selector(remove), keyEquivalent: "")
            delete.target = self
            return menu
        }

        @objc private func copyItem() { onCopy() }
        @objc private func inspect() { onSelect(); onInspect() }
        @objc private func remove() { onRemove() }
    }
}
