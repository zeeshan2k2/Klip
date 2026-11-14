import Foundation

struct ClipboardSnapshot: Equatable {
    enum Kind: String, Codable {
        case text = "Text"
        case link = "Link"
        case richText = "Rich text"
        case code = "Code"
        case image = "Image"
        case files = "Files"
        case document = "Document"
        case data = "Clipping"

        var symbol: String {
            switch self {
            case .text: "text.alignleft"
            case .link: "link"
            case .richText: "textformat"
            case .code: "chevron.left.forwardslash.chevron.right"
            case .image: "photo"
            case .files: "doc.on.doc"
            case .document: "doc.richtext"
            case .data: "square.on.square"
            }
        }
    }

    let content: String
    let kind: Kind
    let changeCount: Int
    let capturedAt: Date
    let sourceApplicationID: String?
    var items: [ClipboardPayloadItem] = []
    var unavailableTypes: [String] = []

    var byteCount: Int {
        content.utf8.count + items.reduce(0) { $0 + $1.byteCount }
            + unavailableTypes.reduce(0) { $0 + $1.utf8.count }
    }
    var fileReferences: [ClipboardFileReference] { items.flatMap(\.files) }
    func hasSamePayload(as other: ClipboardSnapshot) -> Bool {
        if items.isEmpty && other.items.isEmpty { return content == other.content && kind == other.kind }
        guard items.count == other.items.count else { return false }
        return zip(items, other.items).allSatisfy { left, right in
            left.representations == right.representations && left.files.map(\.originalURL) == right.files.map(\.originalURL)
        }
    }
}
