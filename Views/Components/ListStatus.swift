import SwiftUI

struct ListStatus<Item: Identifiable & Sendable>: View where Item.ID: Sendable {
    let model: RemoteList<Item>
    var emptyTitle = "Nothing here yet"
    var emptyDetail = "GitHub returned no matching results."
    var more: (() async -> Void)? = nil
    var body: some View {
        VStack(spacing: 12) {
            if let error = model.error { ErrorNotice(message: error) }
            if model.loading { ProgressView("Loading from GitHub…").padding() }
            if model.items.isEmpty && !model.loading && model.error == nil {
                EmptyState(title: emptyTitle, symbol: "tray", detail: emptyDetail)
            }
            if model.next != nil, let more {
                Button("Load more") { Task { await more() } }.disabled(model.loading)
            }
        }.frame(maxWidth: .infinity)
    }
}
