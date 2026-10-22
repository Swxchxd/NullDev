import SwiftUI
import Observation
#if SWIFT_PACKAGE
import NullDevCore
#endif

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard", repositories = "Repositories", pulls = "Pull Requests", issues = "Issues"
    case actions = "Actions", activity = "Activity", settings = "Settings"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .dashboard: "square.grid.2x2"
        case .repositories: "books.vertical"
        case .pulls: "arrow.triangle.pull"
        case .issues: "circle.dotted.circle"
        case .actions: "play.rectangle"
        case .activity: "waveform.path.ecg"
        case .settings: "gearshape"
        }
    }
}

enum Appearance: String, CaseIterable {
    case system = "System", light = "Light", dark = "Dark"
    var scheme: ColorScheme? { switch self { case .system: nil; case .light: .light; case .dark: .dark } }
}

@MainActor @Observable
final class AppStore {
    var section: AppSection = .dashboard
    var username: String { didSet { defaults.set(username, forKey: "username") } }
    var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: "appearance") } }
    var refreshMinutes: Int { didSet { defaults.set(refreshMinutes, forKey: "refreshMinutes") } }
    var favorites: Set<Int> { didSet { defaults.set(Array(favorites), forKey: "favorites") } }
    var repositoryQuery = RepositoryQuery()
    var dashboard = DashboardModel()
    var pulls = WorkListModel(kind: .pull)
    var issues = WorkListModel(kind: .issue)
    var actions = ActionsModel()
    var activity = ActivityModel()
    var profile: GitHubUser?
    var repositories: [Repository] = []
    var events: [GitHubEvent] = []
    var eventNext: URL?
    var loading = false
    var error: String?
    var eventError: String?
    var lastUpdated: Date?
    var authenticatedLogin: String?
    var hasToken = false
    var ready = false
    var accountRevision = 0
    var revision = 0
    var rateLimits: [RateLimit] = []
    @ObservationIgnored let api: GitHubClient
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var starting = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        username = defaults.string(forKey: "username") ?? ""
        appearance = Appearance(rawValue: defaults.string(forKey: "appearance") ?? "System") ?? .system
        let interval = defaults.object(forKey: "refreshMinutes") as? Int ?? 0
        refreshMinutes = [0, 5, 15, 30].contains(interval) ? interval : 0
        favorites = Set(defaults.array(forKey: "favorites") as? [Int] ?? [])
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("org.nulldev.NullDev/PublicAPI", isDirectory: true)
        api = GitHubClient(cache: ResponseCache(directory: directory))
    }

    func start() async {
        #if DEBUG
        // Hosted unit tests must not read a developer's Keychain or contact GitHub.
        let environment = ProcessInfo.processInfo.environment
        if ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCInjectBundleInto"].contains(where: { environment[$0] != nil }) {
            ready = true
            return
        }
        #endif
        guard !ready, !starting else { return }
        starting = true
        defer { starting = false }
        do {
            if let token = try KeychainStore.read() {
                hasToken = true
                await api.configure(token: token)
                do {
                    let account = try await api.get(GitHubUser.self, url: GitHubClient.endpoint("user"))
                    authenticatedLogin = account.value.login
                    if username.isEmpty { username = account.value.login }
                } catch { self.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription }
        ready = true
        if !username.isEmpty { reload() }
    }

    func connect(username input: String) {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard GitHubValidation.username(clean) else { error = GitHubError.invalidUsername.localizedDescription; return }
        if username.lowercased() != clean.lowercased() { resetAccountData() }
        username = clean
        section = .dashboard
        reload(clear: true)
    }

    func reload(force: Bool = false, clear: Bool = false) {
        guard ready, !username.isEmpty else { return }
        loadTask?.cancel()
        let id = UUID(); requestID = id
        let username = username
        if clear { profile = nil; repositories = []; events = []; eventNext = nil; eventError = nil; lastUpdated = nil }
        loading = true; error = nil
        loadTask = Task {
            defer { if requestID == id { loading = false } }
            do {
                guard GitHubValidation.username(username) else { throw GitHubError.invalidUsername }
                let result = try await api.get(GitHubUser.self, url: GitHubClient.endpoint("users/\(username)"), force: force)
                try Task.checkCancellation()
                guard requestID == id else { return }
                profile = result.value
                let ownAccount = hasToken && authenticatedLogin?.lowercased() == username.lowercased()
                let path = ownAccount ? "user/repos" : "users/\(username)/repos"
                let query = [URLQueryItem(name: "per_page", value: "100"), URLQueryItem(name: "sort", value: "updated"), URLQueryItem(name: "type", value: ownAccount ? "all" : "owner")]
                let repos = try await api.all(Repository.self, url: GitHubClient.endpoint(path, query: query), force: force)
                try Task.checkCancellation()
                guard requestID == id else { return }
                repositories = repos
                lastUpdated = .now
                revision += 1
                await loadEvents(force: force, request: id)
            } catch is CancellationError { }
            catch { if requestID == id { self.error = error.localizedDescription } }
            rateLimits = await api.rateLimits()
        }
    }

    private func loadEvents(force: Bool, request: UUID) async {
        do {
            let page = try await api.get([GitHubEvent].self, url: GitHubClient.endpoint("users/\(username)/events/public", query: [.init(name: "per_page", value: "100")]), force: force)
            try Task.checkCancellation()
            guard requestID == request else { return }
            events = page.value; eventNext = page.next; eventError = nil
        } catch is CancellationError { }
        catch { if requestID == request { eventError = error.localizedDescription } }
    }

    func moreEvents() async {
        guard let next = eventNext else { return }
        let id = requestID
        do {
            let page = try await api.get([GitHubEvent].self, url: next)
            guard requestID == id else { return }
            let existing = Set(events.map(\.id))
            events += page.value.filter { !existing.contains($0.id) }
            eventNext = page.next; eventError = nil
        } catch is CancellationError { }
        catch { if requestID == id { eventError = error.localizedDescription } }
    }

    func toggleFavorite(_ repository: Repository) {
        if favorites.contains(repository.id) { favorites.remove(repository.id) } else { favorites.insert(repository.id) }
    }

    func saveToken(_ input: String) async throws {
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw GitHubError.unauthorized }
        // Validate independently so a failed token never replaces the active credential.
        let validator = GitHubClient()
        await validator.configure(token: token)
        let account = try await validator.get(GitHubUser.self, url: GitHubClient.endpoint("user"), force: true).value
        try Task.checkCancellation()
        try KeychainStore.save(token)
        resetAccountData()
        await api.configure(token: token)
        hasToken = true; authenticatedLogin = account.login; username = account.login; ready = true
        reload(clear: true)
    }

    func removeToken() async throws {
        try KeychainStore.delete()
        resetAccountData()
        await api.configure(token: nil)
        hasToken = false; authenticatedLogin = nil
        reload(clear: true)
    }

    func clearCache() async throws {
        try await api.cache.clear()
        await AvatarCache.shared.clear()
    }

    private func resetAccountData() {
        loadTask?.cancel(); requestID = UUID(); loading = false
        profile = nil; repositories = []; events = []; eventNext = nil; lastUpdated = nil
        error = nil; eventError = nil; rateLimits = []
        dashboard = DashboardModel(); pulls = WorkListModel(kind: .pull); issues = WorkListModel(kind: .issue)
        actions = ActionsModel(); activity = ActivityModel(); repositoryQuery = RepositoryQuery()
        revision += 1
        accountRevision += 1
    }

    var filteredRepositories: [Repository] { repositoryQuery.apply(to: repositories, favorites: favorites) }
    var languages: [String] { Array(Set(repositories.compactMap(\.language))).sorted() }
}
