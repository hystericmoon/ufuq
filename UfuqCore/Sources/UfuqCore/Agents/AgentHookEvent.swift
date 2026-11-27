import Foundation

/// The fields of a Claude Code hook's stdin JSON that Ufuq uses. Unknown keys are ignored.
/// Prompts, tool input and assistant text (`prompt`, `tool_input`, `message`,
/// `last_assistant_message`) are never decoded, so they can never be stored.
public struct AgentHookEvent: Equatable, Sendable {
    public var sessionID: String
    public var hookEventName: String
    public var cwd: String?
    public var sessionTitle: String?
    public var notificationType: String?
    public var agentID: String?

    public init(sessionID: String, hookEventName: String, cwd: String? = nil, sessionTitle: String? = nil,
                notificationType: String? = nil, agentID: String? = nil) {
        self.sessionID = sessionID
        self.hookEventName = hookEventName
        self.cwd = cwd
        self.sessionTitle = sessionTitle
        self.notificationType = notificationType
        self.agentID = agentID
    }

    private struct Wire: Decodable {
        var session_id: String
        var hook_event_name: String
        var cwd: String?
        var session_title: String?
        var notification_type: String?
        var agent_id: String?
    }

    /// Parses stdin; nil for anything that is not a hook event with a session id and event name.
    public static func parse(_ data: Data) -> AgentHookEvent? {
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data),
              !wire.session_id.isEmpty, !wire.hook_event_name.isEmpty else { return nil }
        return AgentHookEvent(sessionID: wire.session_id, hookEventName: wire.hook_event_name, cwd: wire.cwd,
                              sessionTitle: wire.session_title, notificationType: wire.notification_type,
                              agentID: wire.agent_id)
    }
}
