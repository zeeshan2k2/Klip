
import SwiftUI

struct ContentView: View {
    @Bindable var model: HistoryViewModel
    var onDismiss: () -> Void = {}

    var body: some View {
        HistoryView(model: model, onDismiss: onDismiss)
    }
}

#Preview("Dark") {
    ContentView(model: HistoryViewModel(store: ClipboardHistoryStore(items: HistoryItem.examples)))
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    ContentView(model: HistoryViewModel(store: ClipboardHistoryStore(items: HistoryItem.examples)))
        .preferredColorScheme(.light)
}
