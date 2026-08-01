//
//  HookEvent.swift
//  Notchwatch
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
struct HookEvent {
    /// The hooks worth subscribing to. An unrecognised name decodes to `nil` and
    /// the event is ignored rather than rejected.
    enum Kind: String {
        case sessionStart = "SessionStart"
        case userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case notification = "Notification"
        case stop = "Stop"
        case sessionEnd = "SessionEnd"

        /// Hooks that fire per tool and therefore accept a matcher.
        var takesMatcher: Bool {
            self == .preToolUse || self == .postToolUse
        }
    }

    let kind: Kind?
    let sessionID: String
    let transcriptPath: String?
    let cwd: String?
    let toolName: String?
    /// Present only on the Claude Code versions that report it; pre/post pairing
    /// falls back to the tool name when it is missing.
    let toolUseID: String?
    let toolInput: [String: Any]?
    let message: String?

    init?(json: [String: Any]) {
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

    init?(data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        self.init(json: json)
    }
}
