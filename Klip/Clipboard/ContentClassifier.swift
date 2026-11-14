import Foundation

struct ContentClassifier {
    func classify(_ content: String) -> ClipboardSnapshot.Kind {
        guard !content.contains(where: \.isWhitespace),
              let components = URLComponents(string: content),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.url != nil else { return .text }
        return .link
    }
}
