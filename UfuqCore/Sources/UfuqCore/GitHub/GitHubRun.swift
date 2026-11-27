import Foundation

/// The subset of a GitHub workflow run (`GET /repos/{o}/{r}/actions/runs`) that Ufuq uses.
public struct GitHubRun: Decodable, Equatable, Sendable {
    public struct Actor: Decodable, Equatable, Sendable {
        public var login: String
        public init(login: String) { self.login = login }
    }

    public struct PullRequest: Decodable, Equatable, Sendable {
        public var number: Int
        public init(number: Int) { self.number = number }
    }

    public var id: Int
    public var name: String?
    public var headBranch: String?
    public var headSha: String
    public var event: String
    /// `queued`, `in_progress`, `completed`, `waiting`, `pending`, `requested`.
    public var status: String?
    /// Set once completed: `success`, `failure`, `cancelled`, `skipped`, ...
    public var conclusion: String?
    public var htmlURL: String
    public var runStartedAt: Date?
    public var updatedAt: Date
    public var actor: Actor?
    public var triggeringActor: Actor?
    public var pullRequests: [PullRequest]

    enum CodingKeys: String, CodingKey {
        case id, name, event, status, conclusion, actor
        case headBranch = "head_branch"
        case headSha = "head_sha"
        case htmlURL = "html_url"
        case runStartedAt = "run_started_at"
        case updatedAt = "updated_at"
        case triggeringActor = "triggering_actor"
        case pullRequests = "pull_requests"
    }

    public init(id: Int, name: String? = nil, headBranch: String? = nil, headSha: String, event: String,
                status: String? = "completed", conclusion: String? = nil, htmlURL: String = "",
                runStartedAt: Date? = nil, updatedAt: Date, actor: Actor? = nil,
                triggeringActor: Actor? = nil, pullRequests: [PullRequest] = []) {
        self.id = id
        self.name = name
        self.headBranch = headBranch
        self.headSha = headSha
        self.event = event
        self.status = status
        self.conclusion = conclusion
        self.htmlURL = htmlURL
        self.runStartedAt = runStartedAt
        self.updatedAt = updatedAt
        self.actor = actor
        self.triggeringActor = triggeringActor
        self.pullRequests = pullRequests
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        headBranch = try c.decodeIfPresent(String.self, forKey: .headBranch)
        headSha = try c.decode(String.self, forKey: .headSha)
        event = try c.decode(String.self, forKey: .event)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        conclusion = try c.decodeIfPresent(String.self, forKey: .conclusion)
        htmlURL = try c.decodeIfPresent(String.self, forKey: .htmlURL) ?? ""
        runStartedAt = try c.decodeIfPresent(Date.self, forKey: .runStartedAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        actor = try c.decodeIfPresent(Actor.self, forKey: .actor)
        triggeringActor = try c.decodeIfPresent(Actor.self, forKey: .triggeringActor)
        pullRequests = try c.decodeIfPresent([PullRequest].self, forKey: .pullRequests) ?? []
    }
}

public struct GitHubRunsResponse: Decodable, Equatable, Sendable {
    public var workflowRuns: [GitHubRun]

    enum CodingKeys: String, CodingKey { case workflowRuns = "workflow_runs" }

    public init(workflowRuns: [GitHubRun]) { self.workflowRuns = workflowRuns }

    public static func decode(_ data: Data) throws -> GitHubRunsResponse {
        try SyncCoding.decode(GitHubRunsResponse.self, from: data)
    }
}
