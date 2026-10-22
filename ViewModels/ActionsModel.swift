import Foundation
import Observation
#if SWIFT_PACKAGE
import NullDevCore
#endif

@MainActor @Observable
final class ActionsModel {
    var repository = ""
    var search = ""
    var result = "all"
    var runs = RemoteList<WorkflowRun>()
    var filtered: [WorkflowRun] {
        runs.items.filter {
            (result == "all" || $0.result == result || (result == "pending" && ["queued", "waiting", "requested", "pending"].contains($0.status)))
                && (search.isEmpty || ($0.name ?? "").localizedCaseInsensitiveContains(search)
                    || ($0.displayTitle ?? "").localizedCaseInsensitiveContains(search)
                    || ($0.headBranch ?? "").localizedCaseInsensitiveContains(search))
        }
    }
    func load(api: GitHubClient, force: Bool = false, more: Bool = false) async {
        guard !repository.isEmpty else { return }
        do {
            let url = try more ? runs.next : GitHubClient.endpoint("repos/\(repository)/actions/runs", query: [.init(name: "per_page", value: "30")])
            if let url { await runs.load(api: api, url: url, type: WorkflowRuns.self, force: force, append: more) { $0.workflowRuns } }
        } catch { runs.error = error.localizedDescription }
    }
}
