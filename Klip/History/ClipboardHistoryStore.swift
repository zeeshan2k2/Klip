import Foundation
import Observation

@MainActor
@Observable
final class ClipboardHistoryStore {
    private(set) var items: [HistoryItem]
    private(set) var capacity: Int
    let byteLimit: Int
    private(set) var persistenceEnabled: Bool
    private(set) var storageError: String?
    private(set) var loadBlocked = false
    private var maxAge: TimeInterval?
    private let persistence: HistoryPersisting?
    private let now: () -> Date
    private(set) var needsDeletion = false
    private var maintenanceTimer: Timer?

    init(items: [HistoryItem] = [], capacity: Int = 1000, byteLimit: Int = 128 * 1024 * 1024,
         persistence: HistoryPersisting? = nil, persistenceEnabled: Bool = false,
         maxAge: TimeInterval? = nil, now: @escaping () -> Date = { Date() }) {
        self.items = items
        self.capacity = max(1, capacity)
        self.byteLimit = max(1, byteLimit)
        self.persistence = persistence
        self.persistenceEnabled = persistenceEnabled
        self.maxAge = maxAge
        self.now = now
        if persistenceEnabled, let persistence {
            do { self.items = try persistence.load() }
            catch {
                loadBlocked = true
                storageError = "Saved history couldn’t be read. Clear History to start fresh; new copies remain in memory."
            }
        } else if persistence != nil {
            deleteSaved()
        }
        let before = self.items.map(\.id)
        trim()
        if before != self.items.map(\.id) { save() }
    }

    func configure(persistenceEnabled: Bool, capacity: Int, maxAge: TimeInterval?) {
        guard self.persistenceEnabled != persistenceEnabled || self.capacity != max(1, capacity) || self.maxAge != maxAge else { return }
        self.persistenceEnabled = persistenceEnabled
        self.capacity = max(1, capacity)
        self.maxAge = maxAge
        trim()
        if persistenceEnabled { save() } else { deleteSaved() }
    }

    @discardableResult
    func record(_ snapshot: ClipboardSnapshot) -> Bool {
        guard (!snapshot.content.isEmpty || !snapshot.items.isEmpty), snapshot.byteCount <= min(byteLimit, ClipboardMonitor.maximumPayloadBytes) else { return false }
        trim()
        if let first = items.first, snapshot.hasSamePayload(as: first.snapshot) {
            items[0] = HistoryItem(id: first.id, snapshot: snapshot)
            save()
            return false
        }
        items.insert(HistoryItem(snapshot: snapshot), at: 0)
        trim()
        save()
        return true
    }

    func remove(_ item: HistoryItem) {
        items.removeAll { $0.id == item.id }
        save()
    }

    func clear() {
        items.removeAll()
        deleteSaved()
    }

    func retryStorage() {
        if needsDeletion { deleteSaved() }
        guard !loadBlocked, !needsDeletion else { return }
        if persistenceEnabled { save() }
    }

    func maintenance() {
        let before = items.map(\.id)
        trim()
        if needsDeletion { deleteSaved() }
        if before != items.map(\.id) || (storageError != nil && !loadBlocked) { save() }
    }

    func startMaintenance(interval: TimeInterval = 30) {
        guard maintenanceTimer == nil else { return }
        let timer = Timer(timeInterval: max(0.01, interval), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.maintenance() }
        }
        timer.tolerance = min(5, interval / 5)
        RunLoop.main.add(timer, forMode: .common)
        maintenanceTimer = timer
    }

    func stopMaintenance() {
        maintenanceTimer?.invalidate()
        maintenanceTimer = nil
    }

    private func save() {
        guard persistenceEnabled, !loadBlocked, let persistence else { return }
        do {
            if items.isEmpty { try persistence.delete() } else { try persistence.save(items) }
            storageError = nil
            needsDeletion = false
        } catch {
            storageError = "History couldn’t be saved. Current items are available until you quit. Retry in Settings."
        }
    }

    private func deleteSaved() {
        guard let persistence else { return }
        do {
            try persistence.delete()
            needsDeletion = false
            loadBlocked = false
            storageError = nil
        } catch {
            needsDeletion = true
            storageError = "Saved history couldn’t be removed. Retry deleting it in Settings."
        }
    }

    private func trim() {
        if let maxAge {
            let cutoff = now().addingTimeInterval(-max(0, maxAge))
            items.removeAll { $0.snapshot.capturedAt <= cutoff }
        }
        if items.count > capacity { items.removeLast(items.count - capacity) }
        var total = 0
        let retained = items.prefix { item in
            total += item.snapshot.byteCount
            return total <= byteLimit
        }.count
        if retained < items.count { items.removeLast(items.count - retained) }
    }
}
