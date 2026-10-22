import Foundation

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public final class URLSessionTransport: HTTPTransport, Sendable {
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration, delegate: APIOriginDelegate(), delegateQueue: nil)
    }
    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw GitHubError.invalidResponse }
        return (data, response)
    }
}

private final class APIOriginDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(GitHubClient.isTrusted(request.url) ? request : nil)
    }
}

public enum GitHubError: LocalizedError, Sendable, Equatable {
    case invalidURL, invalidResponse, invalidUsername, unauthorized, forbidden, notFound
    case rateLimited(Date?), server(Int), decoding, offline, timedOut, emptyRepository
    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "The GitHub request URL is invalid."
        case .invalidResponse: return "GitHub returned an unexpected response."
        case .invalidUsername: return "Enter a valid GitHub username (1–39 letters, numbers or single hyphens)."
        case .unauthorized: return "GitHub rejected the token. Update or remove it in Settings."
        case .forbidden: return "GitHub denied access. Check the token’s repository permissions or organization approval."
        case .notFound: return "GitHub could not find this account or resource. It may be private or unavailable to this token."
        case .rateLimited(let reset): return reset.map { "GitHub’s rate limit was reached. Try again after \($0.formatted(date: .omitted, time: .shortened))." } ?? "GitHub’s rate limit was reached. Wait a few minutes before refreshing."
        case .server(let status): return "GitHub returned HTTP \(status). Please try again later."
        case .decoding: return "This response from GitHub could not be read. Refresh to try again."
        case .offline: return "Cannot connect to GitHub. Check your internet connection and try again."
        case .timedOut: return "GitHub took too long to respond. Try again when the connection improves."
        case .emptyRepository: return "This repository is empty and has no commits yet."
        }
    }
}

public struct RateLimit: Sendable {
    public let remaining: Int
    public let limit: Int?
    public let reset: Date?
    public let resource: String
}

public struct APIPage<Value: Sendable>: Sendable {
    public let value: Value
    public let next: URL?
    public let cached: Bool
}

public actor GitHubClient {
    private let transport: any HTTPTransport
    public let cache: ResponseCache
    private var token: String?
    private var generation = UUID()
    private var limits: [String: RateLimit] = [:]
    private var cooldown: Date?
    public init(transport: any HTTPTransport = URLSessionTransport(), cache: ResponseCache = ResponseCache()) {
        self.transport = transport; self.cache = cache
    }

    public func configure(token: String?) async {
        self.token = token
        generation = UUID()
        limits = [:]; cooldown = nil
        await cache.clearMemory()
    }

    public func rateLimits() -> [RateLimit] { limits.values.sorted { $0.resource < $1.resource } }

    public nonisolated static func isTrusted(_ url: URL?) -> Bool {
        guard let url else { return false }
        return url.scheme == "https" && url.host == "api.github.com" && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }

    public nonisolated static func endpoint(_ path: String, query: [URLQueryItem] = []) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"; components.host = "api.github.com"; components.path = "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw GitHubError.invalidURL }
        return url
    }

    public nonisolated static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let value = formatter.date(from: string) { return value }
            formatter.formatOptions = [.withInternetDateTime]
            guard let value = formatter.date(from: string) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid ISO 8601 date"))
            }
            return value
        }
        return decoder
    }

    public nonisolated static func nextLink(_ header: String?) -> URL? {
        for part in (header ?? "").components(separatedBy: ",") {
            let segments = part.components(separatedBy: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard segments.dropFirst().contains(where: { $0 == "rel=\"next\"" }),
                  let raw = segments.first, raw.hasPrefix("<"), raw.hasSuffix(">"),
                  let url = URL(string: String(raw.dropFirst().dropLast())), isTrusted(url) else { continue }
            return url
        }
        return nil
    }

    public func get<T: Decodable & Sendable>(_ type: T.Type, url: URL, force: Bool = false) async throws -> APIPage<T> {
        guard Self.isTrusted(url) else { throw GitHubError.invalidURL }
        try Task.checkCancellation()
        let requestGeneration = generation
        let requestToken = token
        let disk = requestToken == nil
        let key = (disk ? "public:" : "authenticated:\(requestGeneration):") + url.absoluteString
        let cached = await cache.entry(for: key, disk: disk)
        guard generation == requestGeneration else { throw CancellationError() }
        let age = cached.map { Date.now.timeIntervalSince($0.date) } ?? .infinity
        if let cached, age < (force ? (cached.pollInterval ?? 0) : max(180, cached.pollInterval ?? 0)) {
            return try decode(type, entry: cached, cached: true)
        }
        if let cooldown, cooldown > .now { throw GitHubError.rateLimited(cooldown) }
        let resource = url.path.hasPrefix("/search/") ? "search" : "core"
        if let limit = limits[resource], limit.remaining == 0, let reset = limit.reset, reset > .now { throw GitHubError.rateLimited(reset) }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("NullDev/1.0", forHTTPHeaderField: "User-Agent")
        if let requestToken { request.setValue("Bearer \(requestToken)", forHTTPHeaderField: "Authorization") }
        if let etag = cached?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        for attempt in 0...1 {
            let data: Data
            let response: HTTPURLResponse
            do { (data, response) = try await transport.data(for: request) }
            catch is CancellationError { throw CancellationError() }
            catch let error as URLError {
                if error.code == .cancelled { throw CancellationError() }
                throw error.code == .timedOut ? GitHubError.timedOut : GitHubError.offline
            }
            try Task.checkCancellation()
            guard generation == requestGeneration else { throw CancellationError() }
            let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
            if let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init) {
                let name = response.value(forHTTPHeaderField: "X-RateLimit-Resource") ?? resource
                limits[name] = RateLimit(remaining: remaining, limit: response.value(forHTTPHeaderField: "X-RateLimit-Limit").flatMap(Int.init), reset: reset, resource: name)
            }
            let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            if response.statusCode == 429 || (response.statusCode == 403 && (retry != nil || limits[resource]?.remaining == 0 || String(data: data, encoding: .utf8)?.localizedCaseInsensitiveContains("rate limit") == true)) {
                let until = retry.map { Date.now.addingTimeInterval($0) } ?? reset ?? Date.now.addingTimeInterval(60)
                // A primary search quota must not unnecessarily block core endpoints.
                if limits[resource]?.remaining != 0 || retry != nil || response.statusCode == 429 { cooldown = until }
                throw GitHubError.rateLimited(until)
            }
            if [502, 503, 504].contains(response.statusCode), attempt == 0, retry == nil {
                try await Task.sleep(for: .milliseconds(500))
                continue
            }
            switch response.statusCode {
            case 304:
                guard let cached else { throw GitHubError.invalidResponse }
                let refreshed = CachedResponse(data: cached.data, link: cached.link, etag: cached.etag, pollInterval: cached.pollInterval)
                await cache.insert(refreshed, for: key, disk: disk)
                guard generation == requestGeneration else { throw CancellationError() }
                return try decode(type, entry: refreshed, cached: true)
            case 200..<300:
                let entry = CachedResponse(data: data, link: response.value(forHTTPHeaderField: "Link"), etag: response.value(forHTTPHeaderField: "ETag"), pollInterval: response.value(forHTTPHeaderField: "X-Poll-Interval").flatMap(Double.init))
                let page = try decode(type, entry: entry, cached: false)
                await cache.insert(entry, for: key, disk: disk)
                guard generation == requestGeneration else { throw CancellationError() }
                return page
            case 401: throw GitHubError.unauthorized
            case 403: throw GitHubError.forbidden
            case 404: throw GitHubError.notFound
            case 409 where url.path.hasSuffix("/commits"): throw GitHubError.emptyRepository
            default: throw GitHubError.server(response.statusCode)
            }
        }
        throw GitHubError.invalidResponse
    }

    private func decode<T: Decodable & Sendable>(_ type: T.Type, entry: CachedResponse, cached: Bool) throws -> APIPage<T> {
        do { return APIPage(value: try Self.decoder().decode(type, from: entry.data), next: Self.nextLink(entry.link), cached: cached) }
        catch { throw GitHubError.decoding }
    }

    public func all<T: Decodable & Identifiable & Sendable>(_ type: T.Type, url: URL, force: Bool = false) async throws -> [T] {
        var result: [T] = []
        var seen = Set<T.ID>()
        var next: URL? = url
        var visited = Set<URL>()
        while let url = next {
            try Task.checkCancellation()
            guard visited.insert(url).inserted else { throw GitHubError.invalidResponse }
            let page = try await get([T].self, url: url, force: force)
            result.append(contentsOf: page.value.filter { seen.insert($0.id).inserted })
            next = page.next
        }
        return result
    }
}
