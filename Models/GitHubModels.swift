import Foundation

public struct GitHubUser: Codable, Identifiable, Sendable, Equatable {
    public let id: Int
    public let login: String
    public let avatarUrl: URL?
    public let htmlUrl: URL?
    public let name: String?
    public let bio: String?
    public let publicRepos: Int?
    public let followers: Int?
    public let following: Int?
    public let type: String?
}

public struct Repository: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let fullName: String
    public let owner: GitHubUser
    public let description: String?
    public let htmlUrl: URL
    public let language: String?
    public let stargazersCount: Int
    public let forksCount: Int
    public let openIssuesCount: Int
    public let defaultBranch: String?
    public let updatedAt: Date?
    public let pushedAt: Date?
    public let archived: Bool?
    public let fork: Bool?
    public let isPrivate: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, fullName, owner, description, htmlUrl, language
        case stargazersCount, forksCount, openIssuesCount, defaultBranch, updatedAt, pushedAt, archived, fork
        case isPrivate = "private"
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

public struct IssueLabel: Codable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let color: String?
}

public struct WorkItem: Codable, Identifiable, Sendable {
    public struct PullReference: Codable, Sendable { public let url: URL? }
    public let id: Int
    public let number: Int
    public let title: String
    public let state: String
    public let htmlUrl: URL
    public let repositoryUrl: URL?
    public let user: GitHubUser?
    public let labels: [IssueLabel]
    public let createdAt: Date?
    public let updatedAt: Date?
    public let closedAt: Date?
    public let draft: Bool?
    public let pullRequest: PullReference?
    public let body: String?

    public var repositoryName: String {
        repositoryUrl?.pathComponents.suffix(2).joined(separator: "/")
            ?? htmlUrl.pathComponents.dropFirst().prefix(2).joined(separator: "/")
    }
}

public struct SearchResults: Codable, Sendable {
    public let totalCount: Int
    public let incompleteResults: Bool
    public let items: [WorkItem]
}

public struct GitCommit: Codable, Identifiable, Sendable {
    public struct Details: Codable, Sendable {
        public struct Author: Codable, Sendable {
            public let name: String?
            public let date: Date?
        }
        public let message: String
        public let author: Author?
    }
    public let sha: String
    public let htmlUrl: URL
    public let commit: Details
    public let author: GitHubUser?
    public var id: String { sha }
    public var title: String { commit.message.split(separator: "\n").first.map(String.init) ?? "No commit message" }
}

public struct Branch: Codable, Identifiable, Sendable {
    public let name: String
    public let protected: Bool
    public var id: String { name }
}

public struct Readme: Codable, Sendable {
    public let content: String?
    public let encoding: String?
    public let htmlUrl: URL?
    public var markdown: String? {
        guard encoding == "base64", let content,
              let data = Data(base64Encoded: content, options: .ignoreUnknownCharacters) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Actions embeds a repository reference, which omits the repository-list counters.
public struct RepositoryReference: Codable, Sendable {
    public let id: Int
    public let name: String
    public let fullName: String
    public let htmlUrl: URL?
}

public struct WorkflowRun: Codable, Identifiable, Sendable {
    public let id: Int
    public let name: String?
    public let displayTitle: String?
    public let runNumber: Int
    public let event: String
    public let status: String
    public let conclusion: String?
    public let headBranch: String?
    public let headSha: String
    public let htmlUrl: URL
    public let createdAt: Date?
    public let updatedAt: Date?
    public let runStartedAt: Date?
    public let repository: RepositoryReference
    public var duration: TimeInterval? {
        guard status == "completed", let start = runStartedAt, let end = updatedAt else { return nil }
        return max(0, end.timeIntervalSince(start))
    }
    public var result: String { conclusion ?? status }
}

public struct WorkflowRuns: Codable, Sendable {
    public let totalCount: Int
    public let workflowRuns: [WorkflowRun]
}

public struct WorkflowJob: Codable, Identifiable, Sendable {
    public struct Step: Codable, Identifiable, Sendable {
        public let number: Int
        public let name: String
        public let status: String
        public let conclusion: String?
        public var id: Int { number }
    }
    public let id: Int
    public let name: String
    public let status: String
    public let conclusion: String?
    public let htmlUrl: URL?
    public let steps: [Step]?
}

public struct WorkflowJobs: Codable, Sendable { public let jobs: [WorkflowJob] }

public struct GitHubEvent: Codable, Identifiable, Sendable {
    public struct EventRepo: Codable, Sendable { public let name: String }
    public struct Payload: Codable, Sendable {
        public let action: String?
        public let ref: String?
        public let refType: String?
    }
    public let id: String
    public let type: String
    public let actor: GitHubUser
    public let repo: EventRepo
    public let createdAt: Date?
    public let payload: Payload?
    public var summary: String {
        switch type {
        case "PushEvent": return "Pushed to \(payload?.ref?.replacingOccurrences(of: "refs/heads/", with: "") ?? "a branch")"
        case "PullRequestEvent": return "\(payload?.action?.capitalized ?? "Updated") a pull request"
        case "IssuesEvent": return "\(payload?.action?.capitalized ?? "Updated") an issue"
        case "IssueCommentEvent": return "Commented on a discussion"
        case "CreateEvent": return "Created \(payload?.refType ?? "a reference")"
        case "WatchEvent": return "Starred a repository"
        case "ForkEvent": return "Forked a repository"
        case "ReleaseEvent": return "Published a release"
        case "DeleteEvent": return "Deleted \(payload?.refType ?? "a reference")"
        default: return type.replacingOccurrences(of: "Event", with: "")
        }
    }
}

public struct PullDetails: Codable, Sendable {
    public struct Head: Codable, Sendable { public let sha: String }
    public let head: Head
    public let merged: Bool
    public let mergeable: Bool?
    public let mergeableState: String?
}
public struct PullReview: Codable, Identifiable, Sendable {
    public let id: Int
    public let state: String
    public let user: GitHubUser?
}
public struct CheckRun: Codable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let status: String
    public let conclusion: String?
}
public struct CheckRuns: Codable, Sendable { public let checkRuns: [CheckRun] }
public struct CommitStatus: Codable, Sendable { public let state: String; public let totalCount: Int }
