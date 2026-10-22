import Foundation

public actor AvatarCache {
    public static let shared = AvatarCache()
    private var memory: [URL: Data] = [:]
    private let session: URLSession
    private let urlCache: URLCache
    public init() {
        let cache = URLCache(memoryCapacity: 8 * 1024 * 1024, diskCapacity: 0)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = cache
        configuration.timeoutIntervalForRequest = 20
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        urlCache = cache
        session = URLSession(configuration: configuration)
    }
    public func data(for url: URL) async throws -> Data {
        if let data = memory[url] { return data }
        guard url.scheme == "https", url.host == "avatars.githubusercontent.com" else { throw URLError(.badURL) }
        let (data, response) = try await session.data(from: url)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.mimeType?.hasPrefix("image/") == true, data.count < 5 * 1024 * 1024 else { throw URLError(.badServerResponse) }
        if memory.count >= 80 { memory.removeAll(keepingCapacity: true) }
        memory[url] = data
        return data
    }
    public func clear() { memory.removeAll(); urlCache.removeAllCachedResponses() }
}
