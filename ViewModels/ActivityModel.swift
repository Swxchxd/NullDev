import Foundation
import Observation
#if SWIFT_PACKAGE
import NullDevCore
#endif

struct LanguageAmount: Identifiable {
    let name: String
    let bytes: Int
    var id: String { name }
}

@MainActor @Observable
final class ActivityModel {
    var repository = ""
    var commits = RemoteList<GitCommit>()
    var languages: [LanguageAmount] = []
    var languageError: String?
    var loadingLanguages = false
    @ObservationIgnored private var request = UUID()
    func load(api: GitHubClient) async {
        let id = UUID(); request = id
        languages = []; languageError = nil
        guard !repository.isEmpty else { return }
        loadingLanguages = true
        defer { if request == id { loadingLanguages = false } }
        let name = repository
        do {
            let result = try await api.get([String: Int].self, url: GitHubClient.endpoint("repos/\(name)/languages"))
            try Task.checkCancellation()
            guard request == id else { return }
            languages = result.value.map { LanguageAmount(name: $0.key, bytes: $0.value) }.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
        } catch is CancellationError { return }
        catch { if request == id { languageError = error.localizedDescription } }
        if let url = try? GitHubClient.endpoint("repos/\(name)/commits", query: [.init(name: "per_page", value: "20")]) {
            await commits.loadArray(api: api, url: url)
        }
    }
}
