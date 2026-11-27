import Foundation

/// Finds the Claude Code config directories (one per account) and names them.
public enum ClaudeAccounts {
    /// `CLAUDE_CONFIG_DIR` (if set and it exists), plus every `.claude`, `.claude-*`, `.claude_*`
    /// or `.claude.*` directory in `home` that holds a `projects` folder. `~/.claude` comes first,
    /// the rest are sorted by path.
    public static func configDirs(
        home: String,
        environment: [String: String],
        listDirectory: (String) -> [String],
        directoryExists: (String) -> Bool
    ) -> [String] {
        var found: [String] = []
        if let dir = environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            let expanded = (dir as NSString).expandingTildeInPath
            if directoryExists(expanded) { found.append(normalize(expanded)) }
        }
        for name in listDirectory(home) where isAccountName(name) {
            let path = (home as NSString).appendingPathComponent(name)
            // `.claude.json` and similar files fail this check.
            guard directoryExists(path), directoryExists((path as NSString).appendingPathComponent("projects")) else { continue }
            found.append(normalize(path))
        }
        var seen = Set<String>()
        let unique = found.filter { seen.insert($0).inserted }
        let primary = normalize((home as NSString).appendingPathComponent(".claude"))
        let rest = unique.filter { $0 != primary }.sorted()
        return (unique.contains(primary) ? [primary] : []) + rest
    }

    /// Uses the real file system, the real home folder and process environment.
    public static func configDirs(
        home: String = NSHomeDirectory(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String] {
        configDirs(
            home: home, environment: environment,
            listDirectory: { (try? FileManager.default.contentsOfDirectory(atPath: $0)) ?? [] },
            directoryExists: { path in
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
            })
    }

    /// ".claude" is "Claude", ".claude-work" is "Claude · Work", any other folder "Claude · <Name>".
    public static func label(forConfigDir dir: String) -> String {
        let name = (normalize(dir) as NSString).lastPathComponent
        let bare = name.hasPrefix(".") ? String(name.dropFirst()) : name
        let rest: String
        if bare.lowercased().hasPrefix("claude") {
            rest = String(bare.dropFirst("claude".count).drop { "-_.".contains($0) })
        } else {
            rest = bare
        }
        guard let first = rest.first else { return "Claude" }
        return "Claude · " + first.uppercased() + rest.dropFirst()
    }

    private static func isAccountName(_ name: String) -> Bool {
        name == ".claude" || [".claude-", ".claude_", ".claude."].contains { name.hasPrefix($0) }
    }

    private static func normalize(_ path: String) -> String {
        var p = path
        while p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }
}
