//
//  HookEvent.swift
//  NotchwatchKit
//
//  One payload delivered by a Claude Code hook.
//

import Foundation

/// A hook payload, as Claude Code writes it to the hook's standard input.
///
/// Decoded field by field rather than through `Codable` on purpose. The hook
/// contract is public but it is Claude Code's to version, and every field except
/// the event name is treated as optional: a payload that gains a key we have
/// never seen, or loses one we expected, must still yield everything else. A
/// strict decoder would turn one added field into a dead status display.
public struct HookEvent {
    /// The hooks worth subscribing to. An unrecognised name decodes to `nil` and
    /// the event is ignored rather than rejected.
    public enum Kind: String, CaseIterable, Sendable {
        case sessionStart = "SessionStart"
        case userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case notification = "Notification"
        case stop = "Stop"
        case sessionEnd = "SessionEnd"

        /// Hooks that fire per tool and therefore accept a matcher.
        public var takesMatcher: Bool {
            self == .preToolUse || self == .postToolUse
        }
    }

    public let kind: Kind?
    public let sessionID: String
    public let transcriptPath: String?
    public let cwd: String?
    public let toolName: String?
    /// Present only on the Claude Code versions that report it; pre/post pairing
    /// falls back to the tool name when it is missing.
    public let toolUseID: String?
    public let toolInput: [String: Any]?
    public let message: String?

    public init?(json: [String: Any]) {
        guard let sessionID = json["session_id"] as? String, !sessionID.isEmpty else { return nil }
        self.sessionID = sessionID
        kind = (json["hook_event_name"] as? String).flatMap(Kind.init(rawValue:))
        transcriptPath = json["transcript_path"] as? String
        cwd = json["cwd"] as? String
        toolName = json["tool_name"] as? String
        toolUseID = json["tool_use_id"] as? String
        toolInput = json["tool_input"] as? [String: Any]
        message = json["message"] as? String
    }

    public init?(data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        self.init(json: json)
    }

    /// Whether this notification is a tool blocked on the user's approval.
    ///
    /// `Notification` fires for both "Claude needs your permission to use Bash"
    /// and "Claude is waiting for your input". Only the first is a blocked tool;
    /// treating the second as one would light the indicator on an idle session,
    /// which is the failure the timer-based guess was removed for.
    public var isPermissionRequest: Bool {
        guard kind == .notification, let message else { return false }
        return message.range(of: "permission", options: .caseInsensitive) != nil
    }
}
