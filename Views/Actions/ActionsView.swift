import SwiftUI
#if SWIFT_PACKAGE
import NullDevCore
#endif

struct ActionsView: View {
    @Environment(AppStore.self) private var store
    @State private var selected: WorkflowRun?
    @State private var refresh = 0
    private var model: ActionsModel { store.actions }
    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Actions", subtitle: "Keep an eye on your builds. Workflow runs from the selected repository.")
                HStack {
                    Picker("Repository", selection: $model.repository) {
                        Text("Choose a repository").tag("")
                        ForEach(store.repositories) { Text($0.fullName).tag($0.fullName) }
                    }.frame(maxWidth: 370)
                    Picker("Result", selection: $model.result) {
                        Text("All results").tag("all"); Text("Success").tag("success"); Text("Failure").tag("failure")
                        Text("Running").tag("in_progress"); Text("Pending").tag("pending"); Text("Cancelled").tag("cancelled")
                    }.frame(width: 170)
                    Spacer()
                    Button("Refresh runs", systemImage: "arrow.clockwise") { refresh += 1 }
                        .disabled(model.runs.loading || model.repository.isEmpty)
                }
                Text("Search and result filters apply to loaded runs. Load more for older workflows.").font(.caption).foregroundStyle(.secondary)
            }.padding(24)
            Divider()
            List {
                ForEach(model.filtered) { run in
                    Button { selected = run } label: { WorkflowRow(run: run) }
                        .buttonStyle(.plain).contextMenu { Link("Open on GitHub", destination: run.htmlUrl) }
                }
                if model.filtered.isEmpty && !model.runs.items.isEmpty && !model.runs.loading {
                    Text("No loaded runs match these filters.").foregroundStyle(.secondary).padding()
                }
                ListStatus(model: model.runs, emptyTitle: "No workflow runs", emptyDetail: "Select a repository. Repositories without workflows or Actions access have no visible runs.") {
                    await model.load(api: store.api, more: true)
                }
            }.listStyle(.inset)
        }
        .searchable(text: $model.search, prompt: "Search loaded workflows or branches")
        .onChange(of: store.repositories, initial: true) { _, repositories in
            if !repositories.contains(where: { $0.fullName == model.repository }) { model.repository = repositories.first?.fullName ?? "" }
        }
        .task(id: "\(model.repository)-\(refresh)-\(store.revision)") {
            await model.load(api: store.api, force: refresh > 0)
        }
        .sheet(item: $selected) { WorkflowDetailView(run: $0).environment(store) }
    }
}

struct RunStatus: View {
    let result: String
    private var color: Color {
        switch result {
        case "success": .green
        case "failure", "timed_out", "action_required", "startup_failure": .red
        case "in_progress", "queued", "waiting", "requested", "pending": .orange
        default: .secondary
        }
    }
    private var symbol: String {
        switch result {
        case "success": "checkmark.circle.fill"
        case "failure", "timed_out", "startup_failure": "xmark.circle.fill"
        case "in_progress": "circle.dotted"
        case "queued", "waiting", "requested", "pending": "clock"
        case "cancelled": "minus.circle"
        default: "circle"
        }
    }
    var body: some View {
        Label(result.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: symbol)
            .font(.caption.weight(.medium)).foregroundStyle(color)
    }
}

struct WorkflowRow: View {
    let run: WorkflowRun
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "play.rectangle").font(.title3).foregroundStyle(Theme.accent).padding(.top, 2)
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(run.displayTitle ?? run.name ?? "Workflow run").font(.headline).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer()
                    RunStatus(result: run.result)
                }
                Text("\(run.name ?? "Workflow") #\(run.runNumber) · \(run.repository.fullName)").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    MetaLabel(value: run.headBranch ?? "No branch", symbol: "arrow.triangle.branch")
                    Text(run.event).font(.caption).foregroundStyle(.secondary)
                    if let date = run.createdAt { Text(date, style: .relative).font(.caption).foregroundStyle(.secondary) }
                    if let seconds = run.duration { MetaLabel(value: Self.duration(seconds), symbol: "timer") }
                }
            }
        }.padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
    static func duration(_ seconds: TimeInterval) -> String {
        let seconds = Int(seconds)
        return seconds >= 60 ? "\(seconds / 60)m \(seconds % 60)s" : "\(seconds)s"
    }
}
