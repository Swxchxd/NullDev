import SwiftUI
#if SWIFT_PACKAGE
import NullDevCore
#endif

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var username = ""
    @State private var token = ""
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").font(.largeTitle).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NullDev").font(.title2.bold())
                        Text("A native home for your GitHub work.").foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 8)
                if let error { ErrorNotice(message: error) }
                if let notice { Label(notice, systemImage: "checkmark.circle").foregroundStyle(.green).font(.callout) }
            }
            Section("GitHub workspace") {
                TextField("Username", text: $username).onSubmit { connect() }
                HStack {
                    Text("Public data works without signing in.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Load account") { connect() }.disabled(busy || username.isEmpty)
                }
            }
            Section("Authentication") {
                LabeledContent("Access", value: store.hasToken ? "Token stored in Keychain" : "Unauthenticated · public data")
                if let login = store.authenticatedLogin { LabeledContent("Authenticated as", value: "@\(login)") }
                SecureField("GitHub personal access token", text: $token)
                    .autocorrectionDisabled().accessibilityLabel("GitHub personal access token")
                HStack {
                    Button(busy ? "Working…" : "Validate and save token") {
                        busy = true; error = nil; notice = nil
                        Task {
                            defer { busy = false; token = "" }
                            do { try await store.saveToken(token); notice = "Token validated and stored in Keychain." }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(busy || token.isEmpty)
                    if store.hasToken {
                        Button("Remove token", role: .destructive) {
                            busy = true; error = nil; notice = nil
                            Task {
                                defer { busy = false; token = "" }
                                do { try await store.removeToken(); notice = "Token removed. Public mode is active." }
                                catch { self.error = error.localizedDescription }
                            }
                        }.disabled(busy)
                    }
                    Spacer()
                    Link("Create token", destination: URL(string: "https://github.com/settings/personal-access-tokens")!)
                }
                Text("Use a fine-grained token for selected repositories: Metadata, Contents, Issues, Pull requests, Actions, Checks and Commit statuses with read access. Organization approval may be required. Saving a token opens its account. Credentials never go to preferences or disk caches.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Preferences") {
                Picker("Appearance", selection: $store.appearance) {
                    ForEach(Appearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Automatic refresh", selection: $store.refreshMinutes) {
                    Text("Manual only").tag(0); Text("Every 5 minutes").tag(5)
                    Text("Every 15 minutes").tag(15); Text("Every 30 minutes").tag(30)
                }
                Text("Automatic refresh runs while the workspace window is active. GitHub’s rate and polling limits are respected.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Clear response and avatar caches", systemImage: "trash") {
                    error = nil; notice = nil
                    Task {
                        do { try await store.clearCache(); notice = "Caches cleared. Loaded views remain until refreshed." }
                        catch { self.error = error.localizedDescription }
                    }
                }
            }
            Section("GitHub API budget") {
                if store.rateLimits.isEmpty { Text("Rate limits will appear after a GitHub request.").foregroundStyle(.secondary) }
                ForEach(store.rateLimits, id: \.resource) { rate in
                    LabeledContent(rate.resource.capitalized) {
                        Text("\(rate.remaining)\(rate.limit.map { " / \($0)" } ?? "") remaining")
                    }
                    if let reset = rate.reset { Text("Resets \(reset.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary) }
                }
                Button("Update budget display") { Task { store.rateLimits = await store.api.rateLimits() } }
            }
            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                Text("Free, open source, and built with SwiftUI. MIT License. macOS 15 or later. Intel and Apple Silicon.").font(.caption).foregroundStyle(.secondary)
                if let source = AppLinks.source { Link("Source code", destination: source) }
                if let issues = AppLinks.issues { Link("Report an issue", destination: issues) }
                if AppLinks.source == nil { Text("Source and issue links appear when the release maintainer configures their URLs.").font(.caption).foregroundStyle(.secondary) }
                Link("GitHub API documentation", destination: URL(string: "https://docs.github.com/en/rest")!)
            }
        }.formStyle(.grouped)
        .onAppear { username = store.username }
        .onChange(of: store.username) { _, value in username = value }
        .onDisappear { token = "" }
        .task { store.rateLimits = await store.api.rateLimits() }
    }
    private func connect() {
        guard GitHubValidation.username(username.trimmingCharacters(in: .whitespacesAndNewlines)) else { error = GitHubError.invalidUsername.localizedDescription; return }
        error = nil; notice = nil
        store.connect(username: username)
    }
}
