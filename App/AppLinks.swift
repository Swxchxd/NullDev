import Foundation

enum AppLinks {
    static var source: URL? { configured("NullDevSourceURL") }
    static var issues: URL? { configured("NullDevIssuesURL") }
    private static func configured(_ key: String) -> URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: raw), url.scheme == "https" else { return nil }
        return url
    }
}
