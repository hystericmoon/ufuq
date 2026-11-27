import Foundation

/// Hook event -> session state, exactly the table in `docs/agent-status.md`.
public enum AgentStateMachine {
    public static func apply(_ event: AgentHookEvent, to existing: AgentSession?, now: Date,
                             appBundleID: String?) -> AgentSessionUpdate {
        func write(_ state: AgentSessionState, runningSince: Date?, finishedAt: Date?) -> AgentSessionUpdate {
            .write(AgentSession(
                id: event.sessionID, title: title(for: event, existing: existing), cwd: event.cwd ?? existing?.cwd ?? "",
                state: state, updatedAt: now, runningSince: runningSince, finishedAt: finishedAt,
                appBundleID: appBundleID ?? existing?.appBundleID))
        }

        switch event.hookEventName {
        case "SessionStart":
            return write(.idle, runningSince: nil, finishedAt: nil)
        case "UserPromptSubmit":
            return write(.running, runningSince: now, finishedAt: nil)
        case "PreToolUse", "PostToolUse", "PostToolUseFailure":
            // Only moves a known session: a tool event that arrives after SessionEnd must not
            // bring back a ghost "running" session for 6 h.
            guard existing != nil else { return .unchanged }
            return write(.running, runningSince: existing?.runningSince ?? now, finishedAt: nil)
        case "PermissionRequest":
            return write(.waiting, runningSince: existing?.runningSince, finishedAt: nil)
        case "Notification":
            guard event.notificationType == "permission_prompt" || event.notificationType == "elicitation_dialog" else {
                return .unchanged
            }
            return write(.waiting, runningSince: existing?.runningSince, finishedAt: nil)
        case "Stop", "StopFailure":
            return write(.done, runningSince: existing?.runningSince, finishedAt: now)
        case "SessionEnd":
            return .delete
        default:
            return .unchanged
        }
    }

    /// `session_title` if given, else the last path component of `cwd`. A later event without a
    /// title keeps the stored one while the cwd is unchanged.
    static func title(for event: AgentHookEvent, existing: AgentSession?) -> String {
        if let t = event.sessionTitle, !t.isEmpty { return t }
        if let existing, event.cwd == nil || event.cwd == existing.cwd { return existing.title }
        if let cwd = event.cwd {
            let last = cwd.split(separator: "/").last.map(String.init) ?? ""
            if !last.isEmpty { return last }
        }
        return existing?.title ?? "Claude"
    }
}
