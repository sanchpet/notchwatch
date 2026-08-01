//
//  TurnBoundary.swift
//  NotchwatchKit
//
//  Where one turn of the conversation ends and the next begins.
//

import Foundation

/// Reads turn boundaries out of transcript entries.
///
/// This is the whole of the app's answer to "is it my move?", and it lives here
/// — apart from the manager, the file watching and the UI — because it is pure:
/// a role and a stop reason in, a state out. That makes it the one piece of this
/// codebase that can be pinned down by tests rather than by looking at a notch.
///
/// It is extracted in response to a defect it would have caught. The rules were
/// once applied in the wrong order — `stop_reason` recorded, then the role
/// checked, with the role branch clearing the reason one line later. Since the
/// assistant message carrying `end_turn` *is* an assistant message, a finished
/// turn erased itself on arrival, and no transcript could ever mark a session
/// complete.
public enum TurnBoundary {
    /// The part of a session's state that turn boundaries decide.
    public struct State: Equatable {
        /// A turn is under way and the agent owes a reply.
        public var isThinking: Bool
        /// The `stop_reason` of the last assistant message, or nil once a new
        /// turn has opened.
        public var lastStopReason: String?

        public init(isThinking: Bool = false, lastStopReason: String? = nil) {
            self.isThinking = isThinking
            self.lastStopReason = lastStopReason
        }

        /// The agent has handed control back and is waiting on the user.
        public var isAwaitingUser: Bool {
            lastStopReason == "end_turn" && !isThinking
        }
    }

    /// `state` after an entry with this `role` and `stopReason`.
    ///
    /// - A `user` message opens a turn: whatever ended the previous one is spent.
    /// - An `assistant` message reports how its turn stands. `tool_use` means the
    ///   turn continues through a tool; only `end_turn` hands control back.
    /// - Anything else (`system`, `summary`, a compaction boundary) may carry a
    ///   reason worth recording but does not itself move the turn.
    public static func apply(role: String?, stopReason: String?, to state: State) -> State {
        switch role {
        case "user":
            return State(isThinking: true, lastStopReason: nil)
        case "assistant":
            return State(isThinking: stopReason != "end_turn", lastStopReason: stopReason)
        default:
            guard let stopReason else { return state }
            return State(isThinking: state.isThinking, lastStopReason: stopReason)
        }
    }
}
