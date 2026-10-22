import Foundation
import CryptoKit

public struct CachedResponse: Codable, Sendable {
    public let data: Data
    public let date: Date
    public let link: String?
    public let etag: String?
    public let pollInterval: TimeInterval?
    public init(data: Data, date: Date = .now, link: String? = nil, etag: String? = nil, pollInterval: TimeInterval? = nil) {
        self.data = data; self.date = date; self.link = link; self.etag = etag; self.pollInterval = pollInterval
    }
}

/// Public responses may be persisted. Authenticated responses live in memory only.
public actor ResponseCache {
    private var memory: [String: CachedResponse] = [:]
    private let directory: URL?
    private let maximumEntries = 250

    public init(directory: URL? = nil) { self.directory = directory }

    public func entry(for key: String, disk: Bool) -> CachedResponse? {
        if let value = memory[key] { return value }
        guard disk, let file = file(for: key), let data = try? Data(contentsOf: file),
              let entry = try? JSONDecoder().decode(CachedResponse.self, from: data) else { return nil }
        remember(entry, key: key)
        return entry
    }

    public func insert(_ entry: CachedResponse, for key: String, disk: Bool) {
        remember(entry, key: key)
        guard disk, let directory, let file = file(for: key) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
            if files.count >= maximumEntries {
                let oldest = files.sorted {
                    ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                    < ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast)
                }
                for old in oldest.prefix(max(1, files.count - maximumEntries + 1)) { try? FileManager.default.removeItem(at: old) }
            }
            try JSONEncoder().encode(entry).write(to: file, options: .atomic)
        } catch { /* Caching is best effort; networking remains usable. */ }
    }

    public func clear() throws {
        memory.removeAll()
        if let directory, FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    public func clearMemory() { memory.removeAll() }

    private func remember(_ entry: CachedResponse, key: String) {
        if memory.count >= maximumEntries, let oldest = memory.min(by: { $0.value.date < $1.value.date })?.key { memory.removeValue(forKey: oldest) }
        memory[key] = entry
    }

    private func file(for key: String) -> URL? {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory?.appendingPathComponent(hash).appendingPathExtension("json")
    }
}
