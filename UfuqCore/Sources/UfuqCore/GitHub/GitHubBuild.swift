import Foundation

/// One push or pull-request event of a repo: all workflow runs with the same `head_sha` and `event`.
public struct GitHubBuild: Equatable, Sendable, Identifiable {
    public enum State: String, Equatable, Sendable {
        case running, failed, passed
    }

    /// Only runs updated within this window count.
    public static let window: TimeInterval = 24 * 3600

    static let runningStatuses: Set<String> = ["queued", "in_progress", "waiting", "pending", "requested"]
    static let failedConclusions: Set<String> = ["failure", "timed_out", "startup_failure", "action_required"]
    static let passedConclusions: Set<String> = ["success", "skipped", "neutral"]

    /// `<repo>@<sha>:<event>`.
    public var id: String
    /// `owner/repo`.
    public var repo: String
    /// `repo` without the owner.
    public var repoName: String
    public var sha: String
    public var event: String
    public var state: State
    public var branch: String?
    public var prNumber: Int?
    public var workflowCount: Int
    /// Names of the failed workflows (empty unless `state == .failed`), oldest first.
    public var failedWorkflows: [String]
    public var startedAt: Date?
    /// Latest `updated_at`; only for finished builds.
    public var finishedAt: Date?
    /// Latest `updated_at` of any run (the 24 h window and the sort use it).
    public var updatedAt: Date
    public var url: String
    public var isMine: Bool

    /// Groups runs of one repo into builds, newest first. Runs older than 24 h are dropped, as are
    /// builds that were only cancelled (or have no usable result).
    public static func group(_ runs: [GitHubRun], repo: String, login: String?, now: Date) -> [GitHubBuild] {
        let recent = runs.filter { now.timeIntervalSince($0.updatedAt) < window }
        var order: [String] = []
        var groups: [String: [GitHubRun]] = [:]
        for run in recent {
            let key = "\(run.headSha):\(run.event)"
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(run)
        }
        let repoName = repo.split(separator: "/", maxSplits: 1).last.map(String.init) ?? repo
        let wanted = login?.lowercased()

        var builds: [GitHubBuild] = []
        for key in order {
            // Newest first, so "newest run" and "first pull request" are well defined.
            let group = groups[key]!.sorted { $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.id > $1.id }
            let isRunning = group.contains { GitHubBuild.runningStatuses.contains($0.status ?? "") }
            let failing = group.filter { GitHubBuild.failedConclusions.contains($0.conclusion ?? "") }
            let state: State
            if isRunning {
                state = .running
            } else if !failing.isEmpty {
                state = .failed
            } else if group.contains(where: { GitHubBuild.passedConclusions.contains($0.conclusion ?? "") }) {
                state = .passed
            } else {
                continue  // cancelled-only (or unknown): hidden
            }
            let newest = group[0]
            let updatedAt = newest.updatedAt
            let sha = newest.headSha
            builds.append(GitHubBuild(
                id: "\(repo)@\(key)",
                repo: repo, repoName: repoName, sha: sha, event: newest.event, state: state,
                branch: group.compactMap(\.headBranch).first,
                prNumber: group.lazy.compactMap { $0.pullRequests.first?.number }.first,
                workflowCount: group.count,
                failedWorkflows: state == .failed ? failing.reversed().compactMap(\.name) : [],
                startedAt: group.compactMap(\.runStartedAt).min(),
                finishedAt: state == .running ? nil : updatedAt,
                updatedAt: updatedAt,
                url: (state == .failed ? failing[0] : newest).htmlURL,
                isMine: wanted.map { login in
                    group.contains { $0.triggeringActor?.login.lowercased() == login || $0.actor?.login.lowercased() == login }
                } ?? false))
        }
        return builds.sorted { $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.id < $1.id }
    }
}
