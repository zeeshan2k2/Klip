import Foundation

@MainActor
protocol HistoryPersisting {
    func load() throws -> [HistoryItem]
    func save(_ items: [HistoryItem]) throws
    func delete() throws
}

@MainActor
final class JSONHistoryPersistence: HistoryPersisting {
    let fileURL: URL
    private let files: FileManager
    private static let maximumFileBytes = 256 * 1024 * 1024

    init(fileURL: URL? = nil, files: FileManager = .default) {
        self.files = files
        self.fileURL = fileURL ?? files.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Klip", isDirectory: true).appendingPathComponent("History.json")
    }

    private struct Archive: Codable {
        var version = 2
        let items: [Record]
    }
    private struct Record: Codable {
        let id: UUID
        let content: String?
        let payload: [ClipboardPayloadItem]?
        let unavailableTypes: [String]?
        let kind: ClipboardSnapshot.Kind
        let capturedAt: Date
    }
    private enum InvalidArchive: Error { case unsupported, invalid }

    func load() throws -> [HistoryItem] {
        guard files.fileExists(atPath: fileURL.path) else { return [] }
        let bytes = try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard bytes <= Self.maximumFileBytes else { throw InvalidArchive.invalid }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let archive = try decoder.decode(Archive.self, from: Data(contentsOf: fileURL))
        guard [1, 2].contains(archive.version), archive.items.count <= 1000 else { throw InvalidArchive.unsupported }
        var identities = Set<UUID>()
        return try archive.items.map { record in
            let payload = record.payload ?? []
            let unavailable = record.unavailableTypes ?? []
            let payloadBytes = payload.reduce(0) { $0 + $1.byteCount }
            guard payloadBytes <= ClipboardMonitor.maximumPayloadBytes,
                  unavailable.count <= ClipboardMonitor.maximumItems * ClipboardMonitor.maximumTypesPerItem,
                  unavailable.allSatisfy({ $0.utf8.count <= 512 }),
                  identities.insert(record.id).inserted,
                  record.capturedAt.timeIntervalSince1970.isFinite,
                  payload.count <= ClipboardMonitor.maximumItems,
                  payload.allSatisfy({ item in
                      item.representations.count <= ClipboardMonitor.maximumTypesPerItem
                          && item.representations.allSatisfy { $0.type.utf8.count <= 512 }
                          && item.files.count <= ClipboardMonitor.maximumItems
                          && item.files.allSatisfy { URL(string: $0.originalURL)?.isFileURL == true }
                  }) else { throw InvalidArchive.invalid }
            let content = payload.isEmpty ? record.content ?? "" : ClipboardPayloadSummary.describe(payload).0
            let snapshot = ClipboardSnapshot(content: content, kind: record.kind,
                changeCount: 0, capturedAt: record.capturedAt, sourceApplicationID: nil,
                items: payload, unavailableTypes: unavailable)
            guard (!content.isEmpty || !payload.isEmpty), snapshot.byteCount <= ClipboardMonitor.maximumPayloadBytes else { throw InvalidArchive.invalid }
            return HistoryItem(id: record.id, snapshot: snapshot)
        }
    }

    func save(_ items: [HistoryItem]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try files.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        guard items.count <= 1000 else { throw InvalidArchive.invalid }
        let records = items.map { item in
            Record(id: item.id, content: item.snapshot.items.isEmpty ? item.content : nil,
                   payload: item.snapshot.items.isEmpty ? nil : item.snapshot.items,
                   unavailableTypes: item.snapshot.unavailableTypes.isEmpty ? nil : item.snapshot.unavailableTypes,
                   kind: item.kind, capturedAt: item.snapshot.capturedAt)
        }
        let data = try encoder.encode(Archive(items: records))
        guard data.count <= Self.maximumFileBytes else { throw InvalidArchive.invalid }
        try data.write(to: fileURL, options: .atomic)
        try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    func delete() throws {
        if files.fileExists(atPath: fileURL.path) { try files.removeItem(at: fileURL) }
    }
}
