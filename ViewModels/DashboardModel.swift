import Foundation
import Observation
#if SWIFT_PACKAGE
import NullDevCore
#endif

@MainActor @Observable
final class DashboardModel {
    var openPulls: Int?
    var openIssues: Int?
    var error: String?
    var loading = false
    var runs = RemoteList<WorkflowRun>()
    var runRepository: String?
    @ObservationIgnored private var context = ""

    func load(api: GitHubClient, username: String, repository: Repository?, revision: Int) async {
        let key = "\(username)-\(revision)"
        guard key != context else { return }
        context = key
        openPulls = nil; openIssues = nil; error = nil; loading = true
        defer { if context == key { loading = false } }
        for kind in ["pr", "issue"] {
            do {
                let url = try GitHubClient.endpoint("search/issues", query: [.init(name: "q", value: "is:\(kind) is:open author:\(username)"), .init(name: "per_page", value: "1")])
                let page = try await api.get(SearchResults.self, url: url)
                try Task.checkCancellation()
                guard context == key else { return }
                if page.value.incompleteResults { error = "GitHub returned an incomplete search count. Refresh later for an updated count." }
                if kind == "pr" { openPulls = page.value.totalCount } else { openIssues = page.value.totalCount }
            } catch is CancellationError { context = ""; return }
            catch { if context == key { self.error = error.localizedDescription } }
        }
        runRepository = repository?.fullName
        if let repository, let url = try? GitHubClient.endpoint("repos/\(repository.fullName)/actions/runs", query: [.init(name: "per_page", value: "5")]) {
            await runs.load(api: api, url: url, type: WorkflowRuns.self) { $0.workflowRuns }
        }
    }
}
