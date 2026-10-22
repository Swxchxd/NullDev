import SwiftUI
#if SWIFT_PACKAGE
import NullDevCore
#endif

struct WorkItemsView: View {
    let kind: WorkKind
    @Environment(AppStore.self) private var store
    @State private var selected: WorkItem?
    @State private var refresh = 0
    private var model: WorkListModel { kind == .pull ? store.pulls : store.issues }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: kind == .pull ? "Pull Requests" : "Issues", subtitle: model.repository.isEmpty ? "Authored by @\(store.username), across GitHub." : "All authors in \(model.repository).")
                HStack {
                    Picker("Repository", selection: $model.repository) {
                        Text("Authored by @\(store.username)").tag("")
                        ForEach(store.repositories) { Text($0.fullName).tag($0.fullName) }
                    }.frame(maxWidth: 360)
                    Picker("State", selection: $model.state) {
                        Text("Open").tag("open"); Text("Closed").tag("closed"); Text("All").tag("all")
                    }.frame(width: 150)
                    Spacer()
                    Button("Refresh list", systemImage: "arrow.clockwise") { refresh += 1 }.disabled(model.list.loading)
                }
                if let total = model.list.total {
                    Text("\(model.list.items.count) loaded · \(total.formatted()) matches\(total > 1000 ? " · GitHub search exposes the first 1,000; narrow your search." : "")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.list.incomplete { ErrorNotice(message: "GitHub reported incomplete search results. Try a narrower search or refresh later.") }
            }.padding(24)
            Divider()
            List {
                ForEach(model.list.items) { item in
                    Button { selected = item } label: { WorkItemRow(item: item, isPull: kind == .pull) }
                        .buttonStyle(.plain).contextMenu { Link("Open on GitHub", destination: item.htmlUrl) }
                }
                ListStatus(model: model.list, emptyTitle: "No matching \(kind == .pull ? "pull requests" : "issues")", emptyDetail: "Try another repository, state or search.") {
                    await model.load(api: store.api, username: store.username, more: true)
                }
            }.listStyle(.inset)
        }
        .searchable(text: $model.search, prompt: "Search GitHub \(kind == .pull ? "pull requests" : "issues")")
        .task(id: model.key(username: store.username, revision: store.revision) + "|\(refresh)") {
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            await model.load(api: store.api, username: store.username, force: refresh > 0)
        }
        .sheet(item: $selected) { WorkItemDetailView(item: $0).environment(store) }
    }
}

struct WorkItemRow: View {
    let item: WorkItem
    let isPull: Bool
    private var color: Color { item.state == "closed" ? .purple : (item.draft == true ? .secondary : .green) }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isPull ? "arrow.triangle.pull" : "circle.dotted.circle")
                .font(.title3).foregroundStyle(color).frame(width: 25).padding(.top, 3)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(item.title).font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    if item.draft == true { Tag(text: "Draft") }
                    Tag(text: item.state.capitalized, color: color)
                }
                HStack(spacing: 8) {
                    Text("\(item.repositoryName) #\(item.number)").lineLimit(1)
                    Text("by \(item.user?.login ?? "unknown")").lineLimit(1)
                    if let date = item.updatedAt { Text(date, style: .relative) }
                }.font(.caption).foregroundStyle(.secondary)
                if !item.labels.isEmpty {
                    HStack {
                        ForEach(item.labels.prefix(4)) { Tag(text: $0.name, color: Color(hex: $0.color) ?? Theme.accent, textColor: .primary) }
                        if item.labels.count > 4 { Text("+\(item.labels.count - 4)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
}

extension Color {
    init?(hex: String?) {
        guard let hex, hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}
