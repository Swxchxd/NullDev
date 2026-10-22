import SwiftUI
import Charts
#if SWIFT_PACKAGE
import NullDevCore
#endif

struct ActivityView: View {
    @Environment(AppStore.self) private var store
    @State private var loadingEvents = false
    private var model: ActivityModel { store.activity }
    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "Activity", subtitle: "A window into recent public activity and repository code.")
                Panel(title: "Public events by day") {
                    EventChart(events: store.events)
                    Text("\(store.events.count) loaded public events. GitHub limits this feed’s history and size, and events can be delayed. This chart does not count all contributions or private activity.").font(.caption).foregroundStyle(.secondary)
                    if let error = store.eventError { ErrorNotice(message: error) }
                }
                Panel(title: "Repository insights") {
                    Picker("Repository", selection: $model.repository) {
                        Text("Choose a repository").tag("")
                        ForEach(store.repositories) { Text($0.fullName).tag($0.fullName) }
                    }.frame(maxWidth: 450)
                    if model.loadingLanguages { ProgressView("Loading languages…") }
                    if let error = model.languageError { ErrorNotice(message: error) }
                    if model.languages.isEmpty && !model.loadingLanguages {
                        Text("No language data available. Choose a repository containing source code.").foregroundStyle(.secondary)
                    } else if !model.languages.isEmpty {
                        Chart(model.languages.prefix(10)) { language in
                            BarMark(x: .value("Bytes", language.bytes), y: .value("Language", language.name))
                                .foregroundStyle(Theme.accent.gradient).cornerRadius(3)
                                .accessibilityLabel(language.name).accessibilityValue("\(language.bytes) bytes")
                        }.frame(height: CGFloat(max(1, min(model.languages.count, 10)) * 30 + 30))
                        Text("Language bytes reported by GitHub for the selected repository. Top ten shown; not a measure of developer effort.").font(.caption).foregroundStyle(.secondary)
                    }
                    if !model.repository.isEmpty {
                        Divider()
                        Text("Recent commits · default branch").font(.headline)
                        ForEach(model.commits.items) { CommitRow(commit: $0) }
                        ListStatus(model: model.commits, emptyTitle: "No commits") {
                            if let url = model.commits.next { await model.commits.loadArray(api: store.api, url: url, append: true) }
                        }
                    }
                }
                Panel(title: "Repository activity summary") {
                    Text("Counts of loaded public events grouped by repository.").font(.caption).foregroundStyle(.secondary)
                    ForEach(eventRepositories, id: \.name) { item in
                        HStack { Text(item.name); Spacer(); Text("\(item.count) events").foregroundStyle(.secondary) }
                    }
                    if eventRepositories.isEmpty { Text("No public event data available.").foregroundStyle(.secondary) }
                }
                Panel(title: "Recent public events") {
                    ForEach(store.events) { EventRow(event: $0) }
                    if store.events.isEmpty { Text("No recent public events returned.").foregroundStyle(.secondary) }
                    if store.eventNext != nil {
                        Button(loadingEvents ? "Loading…" : "Load more events") {
                            loadingEvents = true
                            Task { await store.moreEvents(); loadingEvents = false }
                        }.disabled(loadingEvents)
                    }
                }
            }.padding(24).frame(maxWidth: 1350)
        }
        .onChange(of: store.repositories, initial: true) { _, repositories in
            if !repositories.contains(where: { $0.fullName == model.repository }) { model.repository = repositories.first?.fullName ?? "" }
        }
        .task(id: "\(model.repository)-\(store.revision)") { await model.load(api: store.api) }
    }
    private var eventRepositories: [(name: String, count: Int)] {
        Dictionary(grouping: store.events, by: { $0.repo.name }).map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }
}
