import SwiftUI
#if SWIFT_PACKAGE
import NullDevCore
#endif

struct WorkflowDetailView: View {
    let run: WorkflowRun
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var current: WorkflowRun?
    @State private var jobs = RemoteList<WorkflowJob>()
    @State private var error: String?
    @State private var refresh = 0
    private var visible: WorkflowRun { current ?? run }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Workflow run #\(run.runNumber)").font(.headline)
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise") { refresh += 1 }.disabled(jobs.loading)
                Link("Open on GitHub", destination: visible.htmlUrl)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(visible.displayTitle ?? visible.name ?? "Workflow run").font(.title.bold())
                    HStack { RunStatus(result: visible.result); Spacer(); Text(visible.repository.fullName).foregroundStyle(.secondary) }
                    HStack(spacing: 20) {
                        MetaLabel(value: visible.headBranch ?? "No branch", symbol: "arrow.triangle.branch")
                        Text(String(visible.headSha.prefix(7))).font(.system(.caption, design: .monospaced))
                        if let seconds = visible.duration { MetaLabel(value: "~\(WorkflowRow.duration(seconds)) elapsed", symbol: "timer") }
                    }
                    if let date = visible.runStartedAt { Text("Started \(date.formatted())").font(.caption).foregroundStyle(.secondary) }
                    if let error { ErrorNotice(message: error) }
                    ForEach(jobs.items) { job in
                        Panel(title: job.name) {
                            RunStatus(result: job.conclusion ?? job.status)
                            ForEach(job.steps ?? []) { step in
                                HStack {
                                    Text("\(step.number). \(step.name)").font(.callout)
                                    Spacer()
                                    RunStatus(result: step.conclusion ?? step.status)
                                }
                            }
                            if let url = job.htmlUrl { Link("View job on GitHub", destination: url).font(.caption) }
                        }
                    }
                    ListStatus(model: jobs, emptyTitle: "No jobs available", emptyDetail: "Jobs may still be queued or require Actions read permission.") {
                        if let url = jobs.next { await jobs.load(api: store.api, url: url, type: WorkflowJobs.self, append: true) { $0.jobs } }
                    }
                }.padding(24)
            }
        }.frame(minWidth: 680, idealWidth: 780, minHeight: 550, idealHeight: 700)
        .task(id: refresh) { await load() }
    }
    private func load() async {
        let base = "repos/\(run.repository.fullName)/actions/runs/\(run.id)"
        error = nil
        do {
            current = try await store.api.get(WorkflowRun.self, url: GitHubClient.endpoint(base), force: refresh > 0).value
        } catch is CancellationError { return }
        catch { self.error = error.localizedDescription }
        if let url = try? GitHubClient.endpoint("\(base)/jobs", query: [.init(name: "per_page", value: "30")]) {
            await jobs.load(api: store.api, url: url, type: WorkflowJobs.self, force: refresh > 0) { $0.jobs }
        }
    }
}
