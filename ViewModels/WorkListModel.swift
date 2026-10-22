import Foundation
import Observation
#if SWIFT_PACKAGE
import NullDevCore
#endif

enum WorkKind: String { case pull = "pr", issue = "issue" }

@MainActor @Observable
final class WorkListModel {
    let kind: WorkKind
    var search = ""
    var repository = ""
    var state = "open"
    var list = RemoteList<WorkItem>()
    init(kind: WorkKind) { self.kind = kind }

    func key(username: String, revision: Int) -> String { "\(username)|\(revision)|\(search)|\(repository)|\(state)" }

    func load(api: GitHubClient, username: String, more: Bool = false, force: Bool = false) async {
        do {
            let scope = repository.isEmpty ? "author:\(username)" : "repo:\(repository)"
            let status = state == "all" ? "" : "is:\(state)"
            let query = "is:\(kind.rawValue) \(scope) \(status) \(search)"
            let url = try more ? list.next : GitHubClient.endpoint("search/issues", query: [
                .init(name: "q", value: query), .init(name: "per_page", value: "30"),
                .init(name: "sort", value: "updated"), .init(name: "order", value: "desc")
            ])
            if let url { await list.load(api: api, url: url, type: SearchResults.self, force: force, append: more) { $0.items } }
        } catch { list.error = error.localizedDescription }
    }
}
