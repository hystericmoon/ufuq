import Foundation

public enum ClaudeHookInstallerError: Error, Equatable {
    /// settings.json is not a JSON object, or `hooks` has an unexpected shape. Nothing is changed.
    case invalidSettings
    /// The hook path must contain `ufuq-hook` so the entry can be found again.
    case invalidHookPath
}

/// Adds or removes Ufuq's hook entries in a Claude account's `settings.json`. Pure: the backup
/// file and the disk write are the app's job.
public enum ClaudeHookInstaller {
    public static let events = [
        "SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd",
    ]
    static let marker = "ufuq-hook"

    public static func command(forHookPath path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "' || true"
    }

    public static func install(into settings: Data?, hookPath: String) throws -> Data {
        guard hookPath.contains(marker) else { throw ClaudeHookInstallerError.invalidHookPath }
        var root = try parse(settings)
        var hooks = try hooksObject(root)
        let command = command(forHookPath: hookPath)
        for event in events {
            var groups = try groupArray(hooks[event])
            var replaced = false
            for (g, group) in groups.enumerated() {
                guard var group = group as? [String: Any], var entries = group["hooks"] as? [Any] else { continue }
                var changed = false
                for (e, entry) in entries.enumerated() {
                    guard var entry = entry as? [String: Any], isOurs(entry) else { continue }
                    entry["type"] = "command"
                    entry["command"] = command
                    entry["timeout"] = 5
                    entries[e] = entry
                    changed = true
                }
                if changed {
                    group["hooks"] = entries
                    groups[g] = group
                    replaced = true
                    break
                }
            }
            if !replaced {
                groups.append(["hooks": [["type": "command", "command": command, "timeout": 5] as [String: Any]]])
            }
            hooks[event] = groups
        }
        root["hooks"] = hooks
        return try serialize(root)
    }

    public static func uninstall(from settings: Data) throws -> Data {
        var root = try parse(settings)
        var hooks = try hooksObject(root)
        for event in events {
            guard hooks[event] != nil else { continue }
            let groups = try groupArray(hooks[event])
            var kept: [Any] = []
            var touched = false
            for group in groups {
                guard var group = group as? [String: Any], let entries = group["hooks"] as? [Any] else {
                    kept.append(group)
                    continue
                }
                let remaining = entries.filter { !(($0 as? [String: Any]).map(isOurs) ?? false) }
                if remaining.count == entries.count {
                    kept.append(group)
                    continue
                }
                touched = true
                if remaining.isEmpty { continue }
                group["hooks"] = remaining
                kept.append(group)
            }
            guard touched else { continue }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        if root["hooks"] != nil { root["hooks"] = hooks }
        return try serialize(root)
    }

    /// True when every event has one of our entries.
    public static func isInstalled(in settings: Data) -> Bool {
        guard let root = try? parse(settings), let hooks = try? hooksObject(root) else { return false }
        return events.allSatisfy { event in
            guard let groups = hooks[event] as? [Any] else { return false }
            return groups.contains { group in
                ((group as? [String: Any])?["hooks"] as? [Any])?.contains { ($0 as? [String: Any]).map(isOurs) ?? false } ?? false
            }
        }
    }

    // MARK: - Helpers

    private static func isOurs(_ entry: [String: Any]) -> Bool {
        (entry["command"] as? String)?.contains(marker) ?? false
    }

    private static func parse(_ data: Data?) throws -> [String: Any] {
        guard let data, !data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data), let dict = object as? [String: Any] else {
            throw ClaudeHookInstallerError.invalidSettings
        }
        return dict
    }

    private static func hooksObject(_ root: [String: Any]) throws -> [String: Any] {
        guard let value = root["hooks"] else { return [:] }
        guard let dict = value as? [String: Any] else { throw ClaudeHookInstallerError.invalidSettings }
        return dict
    }

    private static func groupArray(_ value: Any?) throws -> [Any] {
        guard let value else { return [] }
        guard let array = value as? [Any] else { throw ClaudeHookInstallerError.invalidSettings }
        return array
    }

    private static func serialize(_ root: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: root,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }
}
