import Foundation
import Observation
import SwiftUI

enum FeedbackMode: String, CaseIterable, Identifiable {
    case visual, sound, both, off

    var id: Self { self }
    var label: String {
        switch self {
        case .visual: "Visual only"
        case .sound: "Sound only"
        case .both: "Visual and sound"
        case .off: "Off"
        }
    }
    var showsPopup: Bool { self == .visual || self == .both }
    var playsSound: Bool { self == .sound || self == .both }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: Self { self }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum HistoryShortcut: String, CaseIterable, Identifiable {
    case commandShiftV, controlOptionV, controlShiftSpace, off
    var id: Self { self }
    var label: String {
        switch self {
        case .commandShiftV: "⌘⇧V"
        case .controlOptionV: "⌃⌥V"
        case .controlShiftSpace: "⌃⇧Space"
        case .off: "Off"
        }
    }
}

@MainActor
@Observable
final class PreferencesStore {
    private let defaults: UserDefaults
    @ObservationIgnored var onFeedbackModeChanged: ((FeedbackMode) -> Void)?
    @ObservationIgnored var onSettingsChanged: (() -> Void)?
    var feedbackMode: FeedbackMode {
        didSet {
            defaults.set(feedbackMode.rawValue, forKey: "Klip.feedbackMode")
            onFeedbackModeChanged?(feedbackMode)
        }
    }
    var copySoundVolume: Double {
        didSet {
            if !copySoundVolume.isFinite || !(0...1).contains(copySoundVolume) {
                copySoundVolume = copySoundVolume.isFinite ? min(1, max(0, copySoundVolume)) : 0.50
            }
            defaults.set(copySoundVolume, forKey: "Klip.copySoundVolume")
            onSettingsChanged?()
        }
    }
    var deletionSoundEnabled: Bool {
        didSet {
            defaults.set(deletionSoundEnabled, forKey: "Klip.deletionSoundEnabled")
            onSettingsChanged?()
        }
    }
    var autoExpandCopyPreview: Bool {
        didSet {
            defaults.set(autoExpandCopyPreview, forKey: "Klip.autoExpandCopyPreview")
            onSettingsChanged?()
        }
    }
    var saveHistory: Bool {
        didSet {
            defaults.set(saveHistory, forKey: "Klip.saveHistory")
            onSettingsChanged?()
        }
    }
    var historyLimit: Int {
        didSet {
            if !(1...1000).contains(historyLimit) { historyLimit = min(1000, max(1, historyLimit)) }
            defaults.set(historyLimit, forKey: "Klip.historyLimit")
            onSettingsChanged?()
        }
    }
    var retentionDays: Int {
        didSet {
            if !(0...365).contains(retentionDays) { retentionDays = min(365, max(0, retentionDays)) }
            defaults.set(retentionDays, forKey: "Klip.retentionDays")
            onSettingsChanged?()
        }
    }
    var monitoringPaused: Bool {
        didSet {
            defaults.set(monitoringPaused, forKey: "Klip.monitoringPaused")
            onSettingsChanged?()
        }
    }
    var hidePreviews: Bool {
        didSet {
            defaults.set(hidePreviews, forKey: "Klip.hidePreviews")
            onSettingsChanged?()
        }
    }
    var expandedPreviewDuration: Double {
        didSet {
            if !expandedPreviewDuration.isFinite || !(1...30).contains(expandedPreviewDuration) {
                expandedPreviewDuration = expandedPreviewDuration.isFinite ? min(30, max(1, expandedPreviewDuration)) : 4
            }
            defaults.set(expandedPreviewDuration, forKey: "Klip.expandedPreviewDuration")
            onSettingsChanged?()
        }
    }
    var popupDuration: Double {
        didSet {
            if !popupDuration.isFinite || !(0.5...3).contains(popupDuration) {
                popupDuration = popupDuration.isFinite ? min(3, max(0.5, popupDuration)) : 1.15
            }
            defaults.set(popupDuration, forKey: "Klip.popupDuration")
            onSettingsChanged?()
        }
    }
    var excludedApplicationIDs: [String] {
        didSet {
            defaults.set(excludedApplicationIDs, forKey: "Klip.excludedApplicationIDs")
            onSettingsChanged?()
        }
    }
    var historyShortcut: HistoryShortcut {
        didSet {
            defaults.set(historyShortcut.rawValue, forKey: "Klip.historyShortcut")
            onSettingsChanged?()
        }
    }
    var appearance: AppAppearance {
        didSet {
            defaults.set(appearance.rawValue, forKey: "Klip.appearance")
            onSettingsChanged?()
        }
    }

    var maximumAge: TimeInterval? { retentionDays == 0 ? nil : Double(retentionDays) * 86_400 }

    init(defaults: UserDefaults? = nil) {
        let defaults = defaults ?? .standard
        self.defaults = defaults
        feedbackMode = defaults.string(forKey: "Klip.feedbackMode").flatMap(FeedbackMode.init(rawValue:)) ?? .visual
        let volume = defaults.object(forKey: "Klip.copySoundVolume") == nil ? 0.50 : defaults.double(forKey: "Klip.copySoundVolume")
        copySoundVolume = volume.isFinite ? min(1, max(0, volume)) : 0.50
        deletionSoundEnabled = defaults.object(forKey: "Klip.deletionSoundEnabled") == nil ? true : defaults.bool(forKey: "Klip.deletionSoundEnabled")
        autoExpandCopyPreview = defaults.bool(forKey: "Klip.autoExpandCopyPreview")
        saveHistory = defaults.object(forKey: "Klip.saveHistory") == nil ? true : defaults.bool(forKey: "Klip.saveHistory")
        let storedLimit = defaults.object(forKey: "Klip.historyLimit") as? Int
        let upgradeLimit = !defaults.bool(forKey: "Klip.historyLimit1000Applied")
            && (storedLimit == 100 || storedLimit == 500)
        let initialLimit = upgradeLimit ? 1000 : min(1000, max(1, storedLimit ?? 1000))
        historyLimit = initialLimit
        if upgradeLimit { defaults.set(initialLimit, forKey: "Klip.historyLimit") }
        defaults.set(true, forKey: "Klip.historyLimit1000Applied")
        retentionDays = defaults.object(forKey: "Klip.retentionDays") == nil ? 7 : min(365, max(0, defaults.integer(forKey: "Klip.retentionDays")))
        monitoringPaused = defaults.bool(forKey: "Klip.monitoringPaused")
        hidePreviews = defaults.bool(forKey: "Klip.hidePreviews")
        let previewDuration = defaults.object(forKey: "Klip.expandedPreviewDuration") == nil ? 4 : defaults.double(forKey: "Klip.expandedPreviewDuration")
        expandedPreviewDuration = previewDuration.isFinite ? min(30, max(1, previewDuration)) : 4
        let duration = defaults.object(forKey: "Klip.popupDuration") == nil ? 1.15 : defaults.double(forKey: "Klip.popupDuration")
        popupDuration = duration.isFinite ? min(3, max(0.5, duration)) : 1.15
        excludedApplicationIDs = defaults.stringArray(forKey: "Klip.excludedApplicationIDs") ?? [
            "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop", "com.apple.keychainaccess"
        ]
        historyShortcut = defaults.string(forKey: "Klip.historyShortcut").flatMap(HistoryShortcut.init(rawValue:)) ?? .commandShiftV
        appearance = defaults.string(forKey: "Klip.appearance").flatMap(AppAppearance.init(rawValue:)) ?? .system
    }
}
