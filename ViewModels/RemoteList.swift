import Foundation
import Observation
#if SWIFT_PACKAGE
import NullDevCore
#endif

@MainActor @Observable
final class RemoteList<Item: Identifiable & Sendable> where Item.ID: Sendable {
    var items: [Item] = []
    var next: URL?
    var loading = false
    var error: String?
    var total: Int?
    var incomplete = false
    @ObservationIgnored private var request = UUID()
    @ObservationIgnored private var firstURL: URL?

    func load<Response: Decodable & Sendable>(api: GitHubClient, url: URL, type: Response.Type,
               force: Bool = false, append: Bool = false,
               extract: @Sendable (Response) -> [Item]) async {
        let id = UUID(); request = id
        loading = true; error = nil
        if !append {
            if firstURL != url { items = []; next = nil; total = nil; incomplete = false }
            firstURL = url
        }
        defer { if request == id { loading = false } }
        do {
            let page = try await api.get(type, url: url, force: force)
            try Task.checkCancellation()
            guard request == id else { return }
            let incoming = extract(page.value)
            if append {
                let existing = Set(items.map(\.id))
                items += incoming.filter { !existing.contains($0.id) }
            } else { items = incoming }
            next = page.next
            if let search = page.value as? SearchResults { total = search.totalCount; incomplete = search.incompleteResults }
            if let runs = page.value as? WorkflowRuns { total = runs.totalCount }
        } catch is CancellationError { }
        catch { if request == id { self.error = error.localizedDescription } }
    }

    func loadArray(api: GitHubClient, url: URL, force: Bool = false, append: Bool = false) async where Item: Decodable {
        await load(api: api, url: url, type: [Item].self, force: force, append: append) { $0 }
    }
}
