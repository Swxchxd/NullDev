import Foundation

public enum RepositorySort: String, CaseIterable, Sendable {
    case updated = "Last updated", name = "Name", stars = "Stars"
}

public struct RepositoryQuery: Sendable {
    public var search: String
    public var language: String
    public var sort: RepositorySort
    public var favoritesOnly: Bool

    public init(search: String = "", language: String = "All languages", sort: RepositorySort = .updated, favoritesOnly: Bool = false) {
        self.search = search; self.language = language; self.sort = sort; self.favoritesOnly = favoritesOnly
    }

    public func apply(to repositories: [Repository], favorites: Set<Int> = []) -> [Repository] {
        repositories.filter {
            (search.isEmpty || $0.fullName.localizedCaseInsensitiveContains(search)
                || ($0.description?.localizedCaseInsensitiveContains(search) ?? false))
            && (language == "All languages" || $0.language == language)
            && (!favoritesOnly || favorites.contains($0.id))
        }.sorted {
            switch sort {
            case .updated:
                if $0.updatedAt != $1.updatedAt { return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            case .stars:
                if $0.stargazersCount != $1.stargazersCount { return $0.stargazersCount > $1.stargazersCount }
            case .name: break
            }
            return $0.fullName.localizedStandardCompare($1.fullName) == .orderedAscending
        }
    }
}

public enum GitHubValidation {
    public static func username(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?$", options: .regularExpression) != nil
            && !value.contains("--")
    }
}

public struct ActivityDay: Identifiable, Sendable {
    public let date: Date
    public let count: Int
    public var id: Date { date }
}

public enum ActivitySummary {
    /// Counts returned public events only, never inferred contributions.
    public static func days(events: [GitHubEvent], calendar: Calendar = .current) -> [ActivityDay] {
        let groups = Dictionary(grouping: events.compactMap(\.createdAt)) { calendar.startOfDay(for: $0) }
        return groups.map { ActivityDay(date: $0.key, count: $0.value.count) }.sorted { $0.date < $1.date }
    }
}
