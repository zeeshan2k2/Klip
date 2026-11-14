import AppKit
import SwiftUI
import ServiceManagement

enum SettingsTab: String, CaseIterable, Identifiable {
    case history = "History", privacy = "Privacy", feedback = "Feedback", general = "General"
    var id: Self { self }
}

struct SettingsView: View {
    @Bindable var preferences: PreferencesStore
    @Bindable var model: HistoryViewModel
    @Bindable var login: LaunchAtLoginController
    let onAddExclusion: () -> Void
    @State private var confirmingClear = false
    @State var selectedTab: SettingsTab = .history

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases) { tab in
                    Button { selectedTab = tab } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .contentShape(Rectangle())
                            .overlay(alignment: .bottom) {
                                if selectedTab == tab {
                                    Rectangle().fill(HistoryStyle.accent).frame(height: 2).padding(.horizontal, 18)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(tab.rawValue) settings")
                    .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12)
            Divider()
            switch selectedTab {
            case .history: history
            case .privacy: privacy
            case .feedback: feedback
            case .general: general
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 520, minHeight: 480)
        .preferredColorScheme(preferences.appearance.colorScheme)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in login.refresh() }
        .confirmationDialog("Clear all clipboard history?", isPresented: $confirmingClear) {
            Button("Clear History", role: .destructive) { model.clearHistory() }
        } message: {
            Text("This removes the current list and the saved history on this Mac.")
        }
    }

    private var history: some View {
        Form {
            Section("Storage") {
                Toggle("Save history between launches", isOn: $preferences.saveHistory)
                Text("Enabling saves the items currently in history and future copies locally on this Mac. Turning it off deletes saved history; current items stay in memory until you quit.")
                    .font(.callout).foregroundStyle(.secondary)
                if let error = model.store.storageError {
                    Text(error).foregroundStyle(.red)
                    if !model.store.loadBlocked || model.store.needsDeletion {
                        Button(model.store.needsDeletion ? "Retry Deleting Saved History" : "Retry Saving") { model.store.retryStorage() }
                    }
                } else {
                    Text(preferences.saveHistory ? "History is saved locally in Klip’s Application Support folder." : "Saved history is off. Current items will be cleared when you quit.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section {
                Text("Files are kept as references, not duplicated. Their originals must remain available.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Retention") {
                Picker("Maximum items", selection: $preferences.historyLimit) {
                    ForEach([20, 50, 100, 250, 500, 1000], id: \.self) { Text(String($0)).tag($0) }
                }
                Picker("Keep items for", selection: $preferences.retentionDays) {
                    Text("1 day").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("Until deleted").tag(0)
                }
                Text("Changes apply immediately to current and saved items. Older items are also removed when the memory limit is reached.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Items in history", value: String(model.items.count))
                Button("Clear History…", role: .destructive) { confirmingClear = true }
            }
        }.formStyle(.grouped)
    }

    private var privacy: some View {
        Form {
            Section {
                Toggle("Pause monitoring", isOn: $preferences.monitoringPaused)
                Toggle("Hide clipboard previews", isOn: $preferences.hidePreviews)
                Text("Hidden previews still capture and save content according to your storage settings. Open an item and choose Reveal to view it deliberately.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Excluded applications") {
                ForEach(preferences.excludedApplicationIDs, id: \.self) { identifier in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(applicationName(identifier))
                            Text(identifier).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            preferences.excludedApplicationIDs.removeAll { $0 == identifier }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove exclusion for \(applicationName(identifier))")
                    }
                }
                Button("Add Application…", action: onAddExclusion)
                Text("Excluded apps are checked before reading content. Detection uses the frontmost app and is best effort; sensitive clipboard markers are also suppressed.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Clipboard access") {
                Text(model.monitor?.status == .accessDenied ? "Clipboard access is blocked. Allow Klip in System Settings, then copy again." : "macOS may ask before allowing background clipboard access. If capture stops, check Klip’s clipboard access in System Settings, then copy again.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Open System Settings") { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app")) }
            }
        }.formStyle(.grouped)
    }

    private var feedback: some View {
        Form {
            Section("Copy confirmation") {
                Picker("Feedback", selection: $preferences.feedbackMode) {
                    ForEach(FeedbackMode.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Show preview automatically after copying", isOn: $preferences.autoExpandCopyPreview)
                    .disabled(!preferences.feedbackMode.showsPopup)
                LabeledContent("Copy icon duration") {
                    HStack {
                        Slider(value: $preferences.popupDuration, in: 0.5...3, step: 0.1).frame(width: 160)
                        Text("\(preferences.popupDuration, specifier: "%.1f") s").monospacedDigit().frame(width: 42)
                    }
                }
                .disabled(!preferences.feedbackMode.showsPopup)
                LabeledContent("Preview duration") {
                    HStack {
                        Slider(value: $preferences.expandedPreviewDuration, in: 1...30)
                            .frame(width: 160)
                            .accessibilityLabel("Expanded preview duration")
                        Text("\(preferences.expandedPreviewDuration, specifier: "%.1f") s")
                            .monospacedDigit().frame(width: 42)
                    }
                }
                .disabled(!preferences.feedbackMode.showsPopup)
                LabeledContent("Copy sound volume") {
                    HStack(spacing: 8) {
                        Slider(value: $preferences.copySoundVolume, in: 0...1)
                            .frame(width: 135)
                            .accessibilityLabel("Copy sound volume")
                            .accessibilityValue("\(Int((preferences.copySoundVolume * 100).rounded())) percent")
                        Text("\(Int((preferences.copySoundVolume * 100).rounded()))%")
                            .monospacedDigit().frame(width: 38)
                        Button("Preview") { model.onPreviewCopySound?() }
                            .disabled(preferences.copySoundVolume == 0)
                    }
                }
                Text("Click the notch copy icon for a brief preview. Duration changes apply to new copies. Sound follows your Mac’s output and mute settings.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Deletion") {
                Toggle("Play sound when deleting items", isOn: $preferences.deletionSoundEnabled)
                Text("A single soft tap accompanies deletion. Copy volume applies when copy feedback includes sound; Preview plays just the sample.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var general: some View {
        Form {
            Section("Opening Klip") {
                Picker("Global shortcut", selection: $preferences.historyShortcut) {
                    ForEach(HistoryShortcut.allCases) { Text($0.label).tag($0) }
                }
                if let issue = model.shortcutIssue { Text(issue).foregroundStyle(.red) }
                Text("If another app reserves the shortcut, Klip reports it here. You can always open history from the menu bar.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Appearance") {
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Section("Launch at login") {
                Toggle("Open Klip when I log in", isOn: Binding(get: { login.isEnabled }, set: { login.setEnabled($0) }))
                Text(login.statusText).font(.callout).foregroundStyle(.secondary)
                if let error = login.errorMessage { Text(error).foregroundStyle(.red) }
                if login.status == .requiresApproval { Button("Open Login Items Settings") { login.openSystemSettings() } }
            }
        }.formStyle(.grouped)
    }

    private func applicationName(_ identifier: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return identifier }
        return FileManager.default.displayName(atPath: url.path)
    }
}
