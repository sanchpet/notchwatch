//
//  SessionStanding.swift
//  NotchwatchKit
//
//  What a session's row is telling the reader, and which row goes first.
//

import Foundation

/// What one row of the session list says about its session.
///
/// Four states, and the two that want the user were once indistinguishable from
/// the two that do not: a session awaiting a reply shared the idle grey, and one
/// awaiting permission was within a shade of the working orange. Reading the list
/// to find "which of these is calling me" was therefore guesswork — which is the
/// only question the list is opened to answer once the notch has gone green.
///
/// This is deliberately the plain fact, not the notch's notification: the border
/// clears once the user looks, because it is an alarm. A session that is waiting
/// is still waiting after it has been seen, so the row keeps saying so until it
/// is answered.
///
/// The classification and the ordering live here rather than in the view because
/// they are the whole content of the row — a wrong priority shows the wrong
/// session at the top of a list read at a glance, and no colour or layout test
/// would catch it. What stays in the view is the palette: a `Color` would drag
/// SwiftUI into the kit, and choosing a hue is not a rule that can be wrong in
/// the way an order can.
public enum SessionStanding: CaseIterable, Equatable {
    /// A tool is waiting to be allowed to run.
    case needsPermission
    /// The agent has handed the turn back and is waiting on an answer.
    case awaitingReply
    /// Thinking, or running a tool.
    case working
    /// Attached, and doing nothing in particular.
    case idle

    /// Which of the three facts a session state carries decides the row.
    ///
    /// The order is the point. Permission outranks a finished turn: a session
    /// that has both is blocked on the prompt, and telling the user their turn
    /// has come sends them to a session that cannot take input. A finished turn
    /// outranks activity for the same reason it exists — the agent that is still
    /// working needs nothing, the one that stopped does.
    public init(needsPermission: Bool, isAwaitingReply: Bool, isActive: Bool) {
        if needsPermission {
            self = .needsPermission
        } else if isAwaitingReply {
            self = .awaitingReply
        } else if isActive {
            self = .working
        } else {
            self = .idle
        }
    }

    /// Spelled out for the two that are asking for something. Colour alone is a
    /// poor carrier — four hues in a small row are hard to hold apart, and
    /// impossible for a reader who does not separate red from green. The two
    /// that ask for nothing stay unlabelled: a badge on every row is a badge on
    /// none.
    public var label: String? {
        switch self {
        case .needsPermission: "needs you"
        case .awaitingReply: "your turn"
        case .working, .idle: nil
        }
    }

    /// Rows sort by this: the ones asking for something first.
    public var rank: Int {
        switch self {
        case .needsPermission: 0
        case .awaitingReply: 1
        case .working: 2
        case .idle: 3
        }
    }

    /// Whether `lhs` is listed above `rhs`.
    ///
    /// Standing first — whatever is asking for the user comes to the top, which
    /// is the question the list is opened to answer. Recency only orders
    /// sessions of equal standing, newest first, and a session that has never
    /// been heard from sorts last within its own standing rather than jumping
    /// the queue on a missing date.
    public static func precedes(
        _ lhs: (standing: SessionStanding, lastUpdate: Date?),
        _ rhs: (standing: SessionStanding, lastUpdate: Date?)
    ) -> Bool {
        if lhs.standing.rank != rhs.standing.rank {
            return lhs.standing.rank < rhs.standing.rank
        }
        return (lhs.lastUpdate ?? .distantPast) > (rhs.lastUpdate ?? .distantPast)
    }
}
