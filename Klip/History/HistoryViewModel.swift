import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class HistoryViewModel {
    typealias Appearance = AppAppearance

    let store: ClipboardHistoryStore
    let privacy: PrivacyPolicy
    let preferences: PreferencesStore
    var monitor: ClipboardMonitor?
    @ObservationIgnored var onPaste: ((HistoryItem) -> Void)?
    @ObservationIgnored var onCopy: ((HistoryItem) -> Void)?
    @ObservationIgnored var onTogglePause: (() -> Void)?
    @ObservationIgnored var onShowSettings: (() -> Void)?
    @ObservationIgnored var onDeletion: (() -> Void)?
    @ObservationIgnored var onPreviewCopySound: (() -> Void)?
    private let reduceMotion: () -> Bool
    var query = "" { didSet { reconcileSelection() } }
    var selectedID: HistoryItem.ID?
    var isPanelPresented = false
    var presentationCount: UInt = 0
    var inspectedItem: HistoryItem?
    var appearance: Appearance {
        get { preferences.appearance }
        set { preferences.appearance = newValue }
    }
    var copyError: String?
    var shortcutIssue: String?

    init(store: ClipboardHistoryStore? = nil, privacy: PrivacyPolicy? = nil, preferences: PreferencesStore? = nil, reduceMotion: (() -> Bool)? = nil) {
        self.store = store ?? ClipboardHistoryStore()
        self.privacy = privacy ?? PrivacyPolicy()
        self.preferences = preferences ?? PreferencesStore()
        self.reduceMotion = reduceMotion ?? { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        selectedID = self.store.items.first?.id
    }

    var items: [HistoryItem] { store.items }
    var filteredItems: [HistoryItem] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty ? items : items.filter { $0.searchText.localizedStandardContains(term) }
    }
    var selectedItem: HistoryItem? { filteredItems.first { $0.id == selectedID } }
    var statusMessage: String? { copyError ?? store.storageError ?? monitor?.status.message }

    func historyDidChange() {
        reconcileSelection()
        if let item = inspectedItem, !items.contains(where: { $0.id == item.id }) { inspectedItem = nil }
    }

    func moveSelection(by offset: Int) {
        let visible = filteredItems
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.id == selectedID } ?? 0
        selectedID = visible[min(max(current + offset, 0), visible.count - 1)].id
    }

    func inspectSelection() { inspectedItem = selectedItem }
    func pasteSelection() { if let item = selectedItem { onPaste?(item) } }
    func pasteNumberedItem(_ index: Int) {
        guard filteredItems.indices.contains(index) else { return }
        onPaste?(filteredItems[index])
    }
    func copySelection() { if let item = selectedItem { copy(item) } }
    func copy(_ item: HistoryItem) { onCopy?(item) }
    func copyNumberedItem(_ index: Int) {
        guard filteredItems.indices.contains(index) else { return }
        copy(filteredItems[index])
    }

    var deletionAnimation: Animation? {
        reduceMotion() || !isPanelPresented ? nil : .easeInOut(duration: 0.24)
    }

    func remove(_ item: HistoryItem) {
        guard items.contains(where: { $0.id == item.id }) else { return }
        let previousIndex = filteredItems.firstIndex { $0.id == item.id } ?? 0
        let fromPreview = inspectedItem?.id == item.id
        // Close the preview first, then show the row shrinking behind it. Only
        // presentation is delayed; memory and disk deletion happen immediately.
        if fromPreview { inspectedItem = nil }
        let animation = fromPreview ? deletionAnimation?.delay(0.18) : deletionAnimation
        withAnimation(animation) {
            store.remove(item)
            if selectedID == item.id {
                let visible = filteredItems
                selectedID = visible.isEmpty ? nil : visible[min(previousIndex, visible.count - 1)].id
            }
        }
        onDeletion?()
    }

    func clearHistory() {
        let hadItems = !items.isEmpty
        withAnimation(deletionAnimation) {
            store.clear()
            selectedID = nil
            inspectedItem = nil
            query = ""
        }
        if hadItems { onDeletion?() }
    }

    private func reconcileSelection() {
        if !filteredItems.contains(where: { $0.id == selectedID }) { selectedID = filteredItems.first?.id }
    }
}
