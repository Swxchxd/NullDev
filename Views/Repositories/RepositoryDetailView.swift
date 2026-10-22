import SwiftUI
#if SWIFT_PACKAGE
import NullDevCore
#endif

private enum RepositoryTab: String, CaseIterable {
    case readme = "README", commits = "Commits", branches = "Branches", pulls = "Pull Requests", issues = "Issues", actions = "Actions"
}

struct RepositoryDetailView: View {
    let repository: Repository
    @Environment(AppStore.self) private var store
    @State private var tab: RepositoryTab = .readme
    @State private var readme: Readme?
    @State private var readmeError: String?
    @State private var readmeLoading = false
    @State private var commits = RemoteList<GitCommit>()
    @State private var branches = RemoteList<Branch>()
    @State private var work = RemoteList<WorkItem>()
    @State private var runs = RemoteList<WorkflowRun>()
    @State private var selectedWork: WorkItem?
    @State private var selectedRun: WorkflowRun?
    @State private var refresh = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                Picker("Repository content", selection: $tab) {
                    ForEach(RepositoryTab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Panel {
                    tabContent
                }
            }.padding(24)
        }
        .navigationTitle(repository.name)
        .toolbar {
            Button("Refresh repository", systemImage: "arrow.clockwise.circle") { refresh += 1 }
            Link(destination: repository.htmlUrl) { Label("Open on GitHub", systemImage: "arrow.up.right.square") }
        }
        .task(id: "\(tab.rawValue)-\(refresh)-\(store.revision)") { await load(force: refresh > 0) }
        .sheet(item: $selectedWork) { WorkItemDetailView(item: $0).environment(store) }
        .sheet(item: $selectedRun) { WorkflowDetailView(run: $0).environment(store) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Avatar(url: repository.owner.avatarUrl, size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(repository.owner.login).font(.callout).foregroundStyle(.secondary)
                    Text(repository.name).font(.largeTitle.bold()).textSelection(.enabled)
                }
                Spacer()
                Tag(text: repository.isPrivate ? "Private" : "Public")
                Button { store.toggleFavorite(repository) } label: {
                    Label(store.favorites.contains(repository.id) ? "Favorited" : "Favorite", systemImage: store.favorites.contains(repository.id) ? "star.fill" : "star")
                }
            }
            if let description = repository.description { Text(description).font(.title3).foregroundStyle(.secondary).textSelection(.enabled) }
            HStack(spacing: 20) {
                if let language = repository.language { MetaLabel(value: language, symbol: "circle.fill") }
                MetaLabel(value: "\(repository.stargazersCount) stars", symbol: "star")
                MetaLabel(value: "\(repository.forksCount) forks", symbol: "tuningfork")
                if let branch = repository.defaultBranch { MetaLabel(value: branch, symbol: "arrow.triangle.branch") }
            }
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .readme:
            if readmeLoading { ProgressView("Loading README…") }
            if let error = readmeError { ErrorNotice(message: error) }
            if let markdown = readme?.markdown {
                MarkdownDocument(source: markdown, baseURL: repository.htmlUrl.appendingPathComponent("blob/\(repository.defaultBranch ?? "HEAD")/"))
                Text("Native Markdown preview. Some GitHub formatting and embedded content require the browser.").font(.caption).foregroundStyle(.secondary)
            }
        case .commits:
            ForEach(commits.items) { CommitRow(commit: $0) }
            ListStatus(model: commits, emptyTitle: "No commits", emptyDetail: "This repository may be empty.") { await load(next: true) }
        case .branches:
            ForEach(branches.items) { branch in
                HStack {
                    Label(branch.name, systemImage: "arrow.triangle.branch")
                    Spacer()
                    if branch.name == repository.defaultBranch { Tag(text: "Default", color: Theme.accent) }
                    if branch.protected { Tag(text: "Protected", color: .green) }
                }
            }
            ListStatus(model: branches, emptyTitle: "No branches") { await load(next: true) }
        case .pulls, .issues:
            ForEach(work.items) { item in
                Button { selectedWork = item } label: { WorkItemRow(item: item, isPull: tab == .pulls) }.buttonStyle(.plain)
            }
            ListStatus(model: work, emptyTitle: "No open \(tab.rawValue.lowercased())") { await load(next: true) }
        case .actions:
            ForEach(runs.items) { run in
                Button { selectedRun = run } label: { WorkflowRow(run: run) }.buttonStyle(.plain)
            }
            ListStatus(model: runs, emptyTitle: "No workflow runs", emptyDetail: "This repository has no visible Actions runs.") { await load(next: true) }
        }
    }

    private func load(force: Bool = false, next: Bool = false) async {
        do {
            let base = "repos/\(repository.fullName)"
            let query = [URLQueryItem(name: "per_page", value: "30")]
            switch tab {
            case .readme:
                readmeLoading = true; readmeError = nil
                defer { readmeLoading = false }
                do {
                    readme = try await store.api.get(Readme.self, url: GitHubClient.endpoint("\(base)/readme"), force: force).value
                    if readme?.markdown == nil { readmeError = "GitHub did not return a readable README. Open the repository on GitHub to view it." }
                }
                catch is CancellationError { }
                catch GitHubError.notFound { readmeError = "No README is available for this repository." }
                catch { readmeError = error.localizedDescription }
            case .commits:
                let url = try next ? commits.next : GitHubClient.endpoint("\(base)/commits", query: query)
                if let url { await commits.loadArray(api: store.api, url: url, force: force, append: next) }
            case .branches:
                let url = try next ? branches.next : GitHubClient.endpoint("\(base)/branches", query: query)
                if let url { await branches.loadArray(api: store.api, url: url, force: force, append: next) }
            case .pulls, .issues:
                let kind = tab == .pulls ? "pr" : "issue"
                let url = try next ? work.next : GitHubClient.endpoint("search/issues", query: query + [.init(name: "q", value: "repo:\(repository.fullName) is:\(kind) is:open"), .init(name: "sort", value: "updated")])
                if let url { await work.load(api: store.api, url: url, type: SearchResults.self, force: force, append: next) { $0.items } }
            case .actions:
                let url = try next ? runs.next : GitHubClient.endpoint("\(base)/actions/runs", query: query)
                if let url { await runs.load(api: store.api, url: url, type: WorkflowRuns.self, force: force, append: next) { $0.workflowRuns } }
            }
        } catch { readmeError = error.localizedDescription }
    }
}

struct CommitRow: View {
    let commit: GitCommit
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Link(commit.title, destination: commit.htmlUrl).font(.callout.weight(.medium)).lineLimit(2)
            HStack(spacing: 10) {
                Text(String(commit.sha.prefix(7))).font(.system(.caption, design: .monospaced))
                Text(commit.author?.login ?? commit.commit.author?.name ?? "Unknown author")
                if let date = commit.commit.author?.date { Text(date, style: .relative) }
            }.font(.caption).foregroundStyle(.secondary)
            Divider().padding(.top, 6)
        }
    }
}
