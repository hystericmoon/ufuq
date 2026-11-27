import Foundation

/// Finds the GitHub repo (`owner/repo`) a working directory belongs to, from `.git/config`.
public enum GitRemote {
    /// `owner/repo` of the remote `origin` if it is a `github.com` remote, else nil.
    /// Accepts `git@github.com:o/r(.git)`, `https://github.com/o/r(.git)`, `ssh://git@github.com/o/r(.git)`.
    public static func parseGitHubRepo(fromConfig config: String) -> String? {
        var inOrigin = false
        for rawLine in config.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                let header = line.lowercased().filter { !$0.isWhitespace }
                inOrigin = header.hasPrefix("[remote\"origin\"]")
                continue
            }
            guard inOrigin, let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            guard key == "url" else { continue }
            return parseGitHubURL(line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    static func parseGitHubURL(_ url: String) -> String? {
        var path: Substring
        if let range = url.range(of: "git@github.com:"), range.lowerBound == url.startIndex {
            path = url[range.upperBound...]
        } else if let schemeEnd = url.range(of: "://"), ["https", "http", "ssh"].contains(url[..<schemeEnd.lowerBound].lowercased()) {
            let rest = url[schemeEnd.upperBound...]
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            var host = rest[..<slash].lowercased()
            if let at = host.lastIndex(of: "@") { host = String(host[host.index(after: at)...]) }
            if let colon = host.firstIndex(of: ":") { host = String(host[..<colon]) }
            guard host == "github.com" else { return nil }
            path = rest[rest.index(after: slash)...]
        } else {
            return nil
        }
        while path.hasSuffix("/") { path = path.dropLast() }
        if path.hasSuffix(".git") { path = path.dropLast(4) }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }) else { return nil }
        return "\(parts[0])/\(parts[1])"
    }

    /// Walks up from `directory` to the first `.git` (a directory, or a worktree/submodule file
    /// with `gitdir: <path>`) and returns its GitHub repo.
    public static func repo(forDirectory directory: String, fileSource: FileSource) -> String? {
        var dir = normalize(directory)
        while true {
            let dotGit = join(dir, ".git")
            if let config = readString(join(dotGit, "config"), fileSource) {
                return parseGitHubRepo(fromConfig: config)
            }
            if let pointer = readString(dotGit, fileSource), let gitDir = gitDirPath(pointer, base: dir) {
                return commonConfig(gitDir: gitDir, fileSource).flatMap(parseGitHubRepo(fromConfig:))
            }
            if dir == "/" || dir.isEmpty || dir == "." { return nil }
            dir = parent(of: dir)
        }
    }

    private static func gitDirPath(_ pointer: String, base: String) -> String? {
        guard let line = pointer.split(whereSeparator: \.isNewline).first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
        let path = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { return nil }
        return normalize(path.hasPrefix("/") ? path : join(base, path))
    }

    /// The config of the main repository for a worktree gitdir.
    private static func commonConfig(gitDir: String, _ fileSource: FileSource) -> String? {
        if let common = readString(join(gitDir, "commondir"), fileSource)?.trimmingCharacters(in: .whitespacesAndNewlines), !common.isEmpty {
            let root = common.hasPrefix("/") ? normalize(common) : normalize(join(gitDir, common))
            if let config = readString(join(root, "config"), fileSource) { return config }
        }
        // `<repo>/.git/worktrees/<name>`: the config is two levels up.
        let up = parent(of: gitDir)
        if (up as NSString).lastPathComponent == "worktrees",
           let config = readString(join(parent(of: up), "config"), fileSource) {
            return config
        }
        return readString(join(gitDir, "config"), fileSource)
    }

    private static func readString(_ path: String, _ fileSource: FileSource) -> String? {
        (try? fileSource.read(path)).flatMap { String(data: $0, encoding: .utf8) }
    }

    private static func join(_ a: String, _ b: String) -> String { a.hasSuffix("/") ? a + b : a + "/" + b }

    private static func parent(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "." }
        return slash == path.startIndex ? "/" : String(path[..<slash])
    }

    /// Collapses `.`, `..` and duplicate slashes (pure string work; no disk access).
    private static func normalize(_ path: String) -> String {
        var out: [Substring] = []
        for part in path.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { if !out.isEmpty { out.removeLast() }; continue }
            out.append(part)
        }
        return (path.hasPrefix("/") ? "/" : "") + out.joined(separator: "/")
    }
}
