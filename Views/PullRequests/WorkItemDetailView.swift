import SwiftUI
#if SWIFT_PACKAGE
import NullDevCore
#endif

struct WorkItemDetailView: View {
    let item: WorkItem
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var details: PullDetails?
    @State private var reviews: [PullReview] = []
    @State private var checks = RemoteList<CheckRun>()
    @State private var checksURL: URL?
    @State private var status: CommitStatus?
    @State private var errors: [String] = []
    @State private var loading = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(item.repositoryName) #\(item.number)").font(.headline)
                Spacer()
                Link("Open on GitHub", destination: item.htmlUrl)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(item.title).font(.title.bold()).textSelection(.enabled)
                    HStack {
                        Tag(text: details?.merged == true ? "Merged" : item.state.capitalized, color: .purple)
                        if item.draft == true { Tag(text: "Draft") }
                        Text("by \(item.user?.login ?? "unknown")").foregroundStyle(.secondary)
                        if let date = item.createdAt { Text(date, style: .date).foregroundStyle(.secondary) }
                    }
                    if loading { ProgressView("Loading pull request status…") }
                    ForEach(Array(errors.enumerated()), id: \.offset) { _, error in ErrorNotice(message: error) }
                    if item.pullRequest != nil {
                        Panel(title: "Review and check status") {
                            if let details {
                                Text("GitHub merge state: \(details.mergeableState ?? "not yet computed")").font(.callout)
                            }
                            if reviews.isEmpty { Text("No submitted reviews loaded.").foregroundStyle(.secondary) }
                            ForEach(latestReviews) { review in
                                HStack { Text(review.user?.login ?? "Unknown reviewer"); Spacer(); Tag(text: review.state.replacingOccurrences(of: "_", with: " ").capitalized) }
                            }
                            if let status, status.totalCount > 0 { Text("Commit statuses: \(status.state) (\(status.totalCount))").font(.callout) }
                            ForEach(checks.items) { check in
                                HStack { Text(check.name); Spacer(); RunStatus(result: check.conclusion ?? check.status) }
                            }
                            ListStatus(model: checks, emptyTitle: "No check runs returned", emptyDetail: "Checks may require additional token permissions. Commit statuses are shown separately when available.") {
                                if let url = checks.next { await checks.load(api: store.api, url: url, type: CheckRuns.self, append: true) { $0.checkRuns } }
                            }
                            Text("Submitted reviews and reported checks are shown directly. Branch rules and required review decisions may need GitHub.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Panel(title: "Description") {
                        if let body = item.body, !body.isEmpty { MarkdownDocument(source: body, baseURL: item.htmlUrl) }
                        else { Text("No description provided.").foregroundStyle(.secondary) }
                    }
                }.padding(24)
            }
        }.frame(minWidth: 680, idealWidth: 780, minHeight: 550, idealHeight: 700)
        .task { if item.pullRequest != nil { await loadStatus() } }
    }

    private var latestReviews: [PullReview] {
        var byUser: [String: PullReview] = [:]
        for review in reviews.sorted(by: { $0.id < $1.id }) where review.state != "COMMENTED" {
            byUser[review.user?.login ?? "\(review.id)"] = review
        }
        return byUser.values.sorted { ($0.user?.login ?? "") < ($1.user?.login ?? "") }
    }

    private func loadStatus() async {
        loading = true
        defer { loading = false }
        let base = "repos/\(item.repositoryName)"
        do {
            let pull = try await store.api.get(PullDetails.self, url: GitHubClient.endpoint("\(base)/pulls/\(item.number)"))
            details = pull.value
            checksURL = try GitHubClient.endpoint("\(base)/commits/\(pull.value.head.sha)/check-runs", query: [.init(name: "per_page", value: "100")])
            if let checksURL { await checks.load(api: store.api, url: checksURL, type: CheckRuns.self) { $0.checkRuns } }
            do { status = try await store.api.get(CommitStatus.self, url: GitHubClient.endpoint("\(base)/commits/\(pull.value.head.sha)/status")).value }
            catch is CancellationError { return }
            catch { errors.append("Commit status: \(error.localizedDescription)") }
        } catch is CancellationError { return }
        catch { errors.append(error.localizedDescription) }
        do {
            reviews = try await store.api.all(PullReview.self, url: GitHubClient.endpoint("\(base)/pulls/\(item.number)/reviews", query: [.init(name: "per_page", value: "100")]))
        } catch is CancellationError { return }
        catch { errors.append("Reviews: \(error.localizedDescription)") }
    }
}
