import SwiftUI
#if SWIFT_PACKAGE
import NullDevCore
#endif

struct ContentView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").font(.title2.weight(.bold)).foregroundStyle(Theme.accent)
                    Text("NullDev").font(.title2.bold())
                    Spacer()
                }.padding(.horizontal, 20).padding(.vertical, 24)
                List(selection: $store.section) {
                    Section("Workspace") {
                        ForEach(AppSection.allCases.filter { $0 != .settings }) { section in
                            Label(section.rawValue, systemImage: section.symbol).tag(section).padding(.vertical, 4)
                        }
                    }
                    Section {
                        Label("Settings", systemImage: "gearshape").tag(AppSection.settings).padding(.vertical, 4)
                    }
                }.listStyle(.sidebar)
                Divider()
                HStack(spacing: 10) {
                    Avatar(url: store.profile?.avatarUrl, size: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(store.profile?.login ?? "Welcome to NullDev").font(.callout.weight(.medium)).lineLimit(1)
                        Text(store.hasToken ? "Token access" : "Public access").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }.padding(16)
            }.navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 290)
        } detail: {
            NavigationStack {
                VStack(spacing: 0) {
                    if let error = store.error { ErrorNotice(message: error).padding([.horizontal, .top], 16) }
                    if store.loading { ProgressView().progressViewStyle(.linear).padding(.top, 4).accessibilityLabel("Loading GitHub data") }
                    if store.section == .settings {
                        SettingsView()
                    } else if store.username.isEmpty {
                        WelcomeView()
                    } else {
                        sectionView
                    }
                }
                .navigationTitle(store.section.rawValue)
                .navigationDestination(for: Repository.self) { RepositoryDetailView(repository: $0) }
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        if let date = store.lastUpdated {
                            Text("Loaded \(date.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ToolbarItem {
                        Button("Refresh", systemImage: "arrow.clockwise") { store.reload(force: true) }
                            .disabled(store.loading || store.username.isEmpty).help("Refresh GitHub data (⌘R)")
                            .keyboardShortcut("r")
                    }
                }
            }.id("\(store.section.rawValue)-\(store.accountRevision)")
        }
        .background(Theme.canvas)
        .tint(Theme.accent)
        .frame(minWidth: 900, minHeight: 620)
        .preferredColorScheme(store.appearance.scheme)
        .task { await store.start() }
        .task(id: "\(store.refreshMinutes)-\(scenePhase == .active)") {
            guard store.refreshMinutes > 0, scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(store.refreshMinutes * 60)) } catch { return }
                if !store.loading { store.reload(force: true) }
            }
        }
    }

    @ViewBuilder private var sectionView: some View {
        switch store.section {
        case .dashboard: DashboardView()
        case .repositories: RepositoriesView()
        case .pulls: WorkItemsView(kind: .pull)
        case .issues: WorkItemsView(kind: .issue)
        case .actions: ActionsView()
        case .activity: ActivityView()
        case .settings: SettingsView()
        }
    }
}

struct WelcomeView: View {
    @Environment(AppStore.self) private var store
    @State private var username = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "chevron.left.forwardslash.chevron.right")
                .font(.system(size: 42, weight: .medium)).foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 10) {
                Text("A little closer to your code.").font(.system(size: 32, weight: .bold))
                Text("Your repositories, pull requests and workflows.\nOne quiet, native workspace for GitHub.")
                    .font(.title3).foregroundStyle(.secondary).lineSpacing(4)
            }
            HStack {
                TextField("GitHub username", text: $username).textFieldStyle(.roundedBorder)
                    .onSubmit { store.connect(username: username) }
                Button("Open workspace") { store.connect(username: username) }
                    .buttonStyle(.borderedProminent).disabled(username.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("Start with public data. Add a token in Settings for private repositories and higher API limits.")
                .font(.callout).foregroundStyle(.secondary)
        }.padding(40).frame(maxWidth: 600).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
