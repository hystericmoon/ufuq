import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum GitHubError: Error, Equatable, Sendable {
    /// 401: the token is rejected.
    case unauthorized
    /// 403/429 with `x-ratelimit-remaining: 0`; poll again after `until`.
    case rateLimited(until: Date)
    case http(Int)
    case invalidResponse
}

public enum GitHubRunsResult: Equatable, Sendable {
    case notModified
    case runs([GitHubRun], etag: String?)
}

/// GitHub REST client. The transport is injected (`URLSession` in the app, a fake in tests).
public struct GitHubClient: Sendable {
    public typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let token: String
    private let transport: Transport
    private let now: @Sendable () -> Date

    public init(token: String, transport: @escaping Transport, now: @escaping @Sendable () -> Date = { Date() }) {
        self.token = token
        self.transport = transport
        self.now = now
    }

    /// Recent runs of a repo. `etag` makes an unchanged answer a 304 (free of rate limit).
    public func runs(repo: String, etag: String? = nil) async throws -> GitHubRunsResult {
        var request = try makeRequest(path: "/repos/\(repo)/actions/runs", query: "per_page=20", repo: repo)
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await transport(request)
        if response.statusCode == 304 { return .notModified }
        try check(response)
        guard let parsed = try? GitHubRunsResponse.decode(data) else { throw GitHubError.invalidResponse }
        return .runs(parsed.workflowRuns, etag: response.value(forHTTPHeaderField: "ETag"))
    }

    /// `GET /user`: the login of the token's owner.
    public func user() async throws -> String {
        let request = try makeRequest(path: "/user", query: nil, repo: nil)
        let (data, response) = try await transport(request)
        try check(response)
        struct User: Decodable { var login: String }
        guard let user = try? JSONDecoder().decode(User.self, from: data), !user.login.isEmpty else {
            throw GitHubError.invalidResponse
        }
        return user.login
    }

    /// `GET /repos/{o}/{r}`: false on 404 ("not found or the token can't see it").
    public func repoExists(_ repo: String) async throws -> Bool {
        let request = try makeRequest(path: "/repos/\(repo)", query: nil, repo: repo)
        let (_, response) = try await transport(request)
        if response.statusCode == 404 { return false }
        try check(response)
        return true
    }

    // MARK: - Internals

    private func makeRequest(path: String, query: String?, repo: String?) throws -> URLRequest {
        if let repo, !Self.isValidRepo(repo) { throw GitHubError.invalidResponse }
        var string = "https://api.github.com" + path
        if let query { string += "?" + query }
        guard let url = URL(string: string) else { throw GitHubError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        return request
    }

    static func isValidRepo(_ repo: String) -> Bool {
        let parts = repo.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return parts.count == 2 && parts.allSatisfy { !$0.isEmpty && $0.unicodeScalars.allSatisfy(allowed.contains) }
    }

    private func check(_ response: HTTPURLResponse) throws {
        let code = response.statusCode
        if (200..<300).contains(code) { return }
        if code == 401 { throw GitHubError.unauthorized }
        if code == 403 || code == 429,
           response.value(forHTTPHeaderField: "x-ratelimit-remaining")?.trimmingCharacters(in: .whitespaces) == "0" {
            let reset = response.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(Double.init)
            throw GitHubError.rateLimited(until: reset.map { Date(timeIntervalSince1970: $0) } ?? now().addingTimeInterval(60))
        }
        throw GitHubError.http(code)
    }
}
