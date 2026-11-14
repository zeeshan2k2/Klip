import SwiftUI

struct HistoryView: View {
    @Bindable var model: HistoryViewModel
    var onDismiss: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @FocusState private var searchFocused: Bool
    @State private var revealedPreview = false
    @State private var showingClipboardMenu = false

    var body: some View {
        VStack(spacing: 0) {
            header
            search
            if let message = model.statusMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
            }

            ZStack {
                historyList
                if model.filteredItems.isEmpty { emptyState.transition(.opacity) }
            }
        }
        .frame(minWidth: HistoryStyle.minimumWidth, maxWidth: .infinity,
               minHeight: HistoryStyle.minimumHeight, maxHeight: .infinity)
        .background {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                RoundedGlassBackground()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: HistoryStyle.cornerRadius, style: .circular))
        .overlay {
            RoundedRectangle(cornerRadius: HistoryStyle.cornerRadius, style: .circular)
                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.45), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .tint(HistoryStyle.accent)
        .preferredColorScheme(model.appearance.colorScheme)
        .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }
        .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
        .onExitCommand(perform: onDismiss)
        .sheet(item: $model.inspectedItem) { item in
            itemPreview(item)
        }
        .onAppear { searchFocused = true }
        .onChange(of: model.items.map(\.id)) { _, _ in model.historyDidChange() }
        .onChange(of: model.inspectedItem?.id) { _, _ in revealedPreview = false }
        .onChange(of: model.preferences.hidePreviews) { _, _ in revealedPreview = false }
        .onChange(of: model.isPanelPresented) { _, isPresented in
            revealedPreview = false
            showingClipboardMenu = false
            searchFocused = isPresented
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            previewSettingsButton.frame(width: 44)
            HistoryWindowDragArea().accessibilityHidden(true)
            clipboardMenuButton
            HistoryWindowDragArea().accessibilityHidden(true)
            HistoryWindowDragArea().frame(width: 44).accessibilityHidden(true)
        }
        .frame(height: 52)
        .background(HistoryStyle.header(colorScheme))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
                .allowsHitTesting(false)
        }
    }

    private var clipboardMenuButton: some View {
        Button { showingClipboardMenu.toggle() } label: {
            HStack(spacing: 6) {
                Text("Clipboard")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clipboard menu")
        .popover(isPresented: $showingClipboardMenu, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 14) {
                Text("\(model.items.count) items · \(model.store.storageError != nil ? "storage needs attention" : model.preferences.saveHistory ? "saved locally" : "in memory")").foregroundStyle(.secondary)
                Divider()
                Button(model.privacy.isPaused ? "Resume Monitoring" : "Pause Monitoring") {
                    model.onTogglePause?()
                    showingClipboardMenu = false
                }
                Button("Clear History", role: .destructive) {
                    model.clearHistory()
                    showingClipboardMenu = false
                }
                .disabled(model.items.isEmpty)
            }
            .buttonStyle(.plain)
            .padding(16)
            .frame(width: 210)
        }
    }

    private var previewSettingsButton: some View {
        Button { model.onShowSettings?() } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 21))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 36)
        }
        .buttonStyle(.plain)
        .help("Settings · ⌘,")
        .accessibilityLabel("Klip settings")
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(.secondary)
            TextField("Type to Search…", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($searchFocused)
                .onSubmit { model.copySelection() }
                .accessibilityLabel("Search clipboard history")

            if !model.query.isEmpty {
                Button {
                    model.query = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 11)
        .frame(height: 54)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 1)
        }
    }

    private var historyList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(model.filteredItems.enumerated()), id: \.element.id) { index, item in
                        HistoryRowView(
                            item: item, index: index, isSelected: model.selectedID == item.id,
                            onSelect: { model.selectedID = item.id; searchFocused = true },
                            onInspect: { model.inspectedItem = item },
                            onRemove: { model.remove(item) },
                            onCopy: { model.copy(item) },
                            hidePreview: model.preferences.hidePreviews
                        )
                        .transition(.asymmetric(insertion: .identity,
                            removal: .scale(scale: 0.02, anchor: .center).combined(with: .opacity)))
                        .id(item.id)
                    }
                }
            }
            .background(HistoryStyle.list(colorScheme))
            .scrollIndicators(.hidden)
            .onChange(of: model.selectedID) { _, selectedID in
                if let selectedID { proxy.scrollTo(selectedID) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text(model.items.isEmpty ? "Clipboard is empty" : "No results")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            if model.items.isEmpty {
                Text(model.preferences.saveHistory ? "Copy something to start your history." : "Copy something. Enable saved history in Settings to keep items after quitting.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Button("Clear Search") { model.query = ""; searchFocused = true }
                    .buttonStyle(.link)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HistoryStyle.list(colorScheme))
    }

    private func itemPreview(_ item: HistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(item.kind.rawValue, systemImage: item.kind.symbol)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Done") { model.inspectedItem = nil }
            }
            ScrollView {
                if model.preferences.hidePreviews && !revealedPreview {
                    VStack(spacing: 12) {
                        Text("Preview hidden").foregroundStyle(.secondary)
                        Button("Reveal This Item") { revealedPreview = true }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    HistoryItemPreview(item: item)
                }
            }
            HStack {
                if let error = model.copyError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Delete", role: .destructive) {
                    model.remove(item)
                    model.inspectedItem = nil
                }
                Button("Copy") { model.copy(item) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420, height: 360)
        .preferredColorScheme(model.appearance.colorScheme)
        .onExitCommand { model.inspectedItem = nil; onDismiss() }
    }
}
