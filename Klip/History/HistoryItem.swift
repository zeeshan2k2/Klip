import Foundation

struct HistoryItem: Identifiable, Equatable {
    let id: UUID
    let snapshot: ClipboardSnapshot

    init(id: UUID = UUID(), snapshot: ClipboardSnapshot) {
        self.id = id
        self.snapshot = snapshot
    }

    var content: String { snapshot.content }
    var kind: ClipboardSnapshot.Kind { snapshot.kind }
    var title: String { String(content.prefix(600)) }
    var searchText: String {
        content + " " + snapshot.fileReferences.compactMap { URL(string: $0.originalURL)?.path }.joined(separator: " ")
    }
    var hasMedia: Bool { kind == .image || kind == .document || kind == .files }

    /// Xcode previews only. The running app always starts with an empty store.
    static let examples: [HistoryItem] = [
        "A native Swift app using AppKit for system integration and SwiftUI for the interface.",
        "https://developer.apple.com/documentation/swiftui",
        "git config --local user.name \"Alex Morgan\"",
        "/Users/alex/Documents/Projects/Klip"
    ].map {
        HistoryItem(snapshot: ClipboardSnapshot(content: $0, kind: ContentClassifier().classify($0),
                                               changeCount: 0, capturedAt: Date(), sourceApplicationID: nil))
    }
}
