import SwiftUI
import Charts
#if SWIFT_PACKAGE
import NullDevCore
#endif

struct DashboardView: View {
    @Environment(AppStore.self) private var store
    @State private var selectedRun: WorkflowRun?
    private var model: DashboardModel { store.dashboard }
    private var quickRepositories: [Repository] {
        let favorites = store.repositories.filter { store.favorites.contains($0.id) }
        return Array((favorites.isEmpty ? store.repositories : favorites).prefix(5))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                accountHeader
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 165), spacing: 14)], spacing: 14) {
                    MetricCard(title: "Public repositories", value: store.profile?.publicRepos, symbol: "globe", note: "GitHub profile")
                    Button { store.section = .repositories } label: {
                        MetricCard(title: "Accessible repositories", value: store.lastUpdated == nil ? nil : store.repositories.count, symbol: "books.vertical", note: "Loaded repository list")
                    }.buttonStyle(.plain)
                    MetricCard(title: "Repository stars", value: store.lastUpdated == nil ? nil : store.repositories.reduce(0) { $0 + $1.stargazersCount }, symbol: "star", note: "Sum of loaded repositories")
                    Button { store.section = .pulls } label: {
                        MetricCard(title: "Open pull requests", value: model.openPulls, symbol: "arrow.triangle.pull", note: "Authored by this account")
                    }.buttonStyle(.plain)
                    Button { store.section = .issues } label: {
                        MetricCard(title: "Open issues", value: model.openIssues, symbol: "circle.dotted.circle", note: "Authored by this account")
                    }.buttonStyle(.plain)
                }
                if let error = model.error { ErrorNotice(message: error) }
                Panel(title: "Public activity") {
                    EventChart(events: store.events)
                    Text("Counts of loaded public events by day. This is a limited activity feed, not a complete contribution history.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 18) {
                        quickAccess.frame(minWidth: 360)
                        recentActivity.frame(minWidth: 300)
                    }
                    VStack(spacing: 18) { quickAccess; recentActivity }
                }
                Panel(title: "Recent workflow runs") {
                    if let name = model.runRepository { Text("From \(name), the most recently updated repository.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(model.runs.items) { run in
                        Button { selectedRun = run } label: { WorkflowRow(run: run) }.buttonStyle(.plain)
                    }
                    if model.runRepository != nil {
                        ListStatus(model: model.runs, emptyTitle: "No workflow runs", emptyDetail: "Choose another repository in Actions to explore its workflows.")
                    } else { Text("Load a repository to see its workflow runs.").foregroundStyle(.secondary) }
                    Button("Explore Actions", systemImage: "play.rectangle") { store.section = .actions }
                }
            }.padding(24).frame(maxWidth: 1350)
        }
        .task(id: "\(store.username)-\(store.revision)") {
            guard store.revision > 0 else { return }
            await model.load(api: store.api, username: store.username, repository: store.repositories.first, revision: store.revision)
        }
        .sheet(item: $selectedRun) { WorkflowDetailView(run: $0).environment(store) }
    }

    private var accountHeader: some View {
        HStack(spacing: 16) {
            Avatar(url: store.profile?.avatarUrl, size: 58)
            VStack(alignment: .leading, spacing: 5) {
                Text(store.profile?.name ?? store.username).font(.largeTitle.bold())
                Text("@\(store.profile?.login ?? store.username) · Your developer overview").foregroundStyle(.secondary)
                if let bio = store.profile?.bio { Text(bio).font(.callout).foregroundStyle(.secondary).lineLimit(2) }
            }
            Spacer()
            if let url = store.profile?.htmlUrl { Link(destination: url) { Image(systemName: "arrow.up.right.square") }.help("Open GitHub profile") }
        }
    }

    private var quickAccess: some View {
        Panel(title: store.repositories.contains(where: { store.favorites.contains($0.id) }) ? "Your favorites" : "Recently updated repositories") {
            if quickRepositories.isEmpty { Text("Your repositories will appear here.").foregroundStyle(.secondary) }
            ForEach(quickRepositories) { repository in
                NavigationLink(value: repository) {
                    HStack {
                        Image(systemName: repository.isPrivate ? "lock" : "book.closed").foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(repository.name).font(.callout.weight(.medium)).lineLimit(1)
                            Text(repository.language ?? "No primary language").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        MetaLabel(value: repository.stargazersCount.formatted(), symbol: "star")
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }.padding(.vertical, 5).contentShape(Rectangle())
                }.buttonStyle(.plain).modifier(RepositoryContext(repository: repository))
            }
            Button("All repositories", systemImage: "books.vertical") { store.section = .repositories }
        }
    }

    private var recentActivity: some View {
        Panel(title: "Recent public events") {
            if let error = store.eventError { ErrorNotice(message: error) }
            if store.events.isEmpty { Text("No recent public events returned by GitHub.").foregroundStyle(.secondary) }
            ForEach(store.events.prefix(5)) { EventRow(event: $0) }
            Button("View activity", systemImage: "waveform.path.ecg") { store.section = .activity }
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: Int?
    let symbol: String
    let note: String
    var body: some View {
        Panel {
            HStack { Image(systemName: symbol).foregroundStyle(Theme.accent); Spacer() }
            Text(value?.formatted() ?? "—").font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.callout.weight(.medium))
                Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }.accessibilityElement(children: .combine)
    }
}

struct EventChart: View {
    let events: [GitHubEvent]
    var body: some View {
        let days = ActivitySummary.days(events: events)
        if days.isEmpty {
            EmptyState(title: "No public activity to chart", symbol: "chart.bar", detail: "Recent public events will appear when GitHub makes them available.")
        } else {
            Chart(days) { day in
                BarMark(x: .value("Day", day.date, unit: .day), y: .value("Public events", day.count))
                    .foregroundStyle(Theme.accent.gradient).cornerRadius(3)
                    .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue("\(day.count) public events")
            }.chartYAxis { AxisMarks(position: .leading) }.frame(height: 145)
        }
    }
}

struct EventRow: View {
    let event: GitHubEvent
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.summary).font(.callout.weight(.medium))
            HStack {
                if let url = URL(string: "https://github.com/\(event.repo.name)") {
                    Link(event.repo.name, destination: url).lineLimit(1)
                }
                Spacer()
                if let date = event.createdAt { Text(date, style: .relative).lineLimit(1) }
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 5).accessibilityElement(children: .combine)
    }
}
