//
//  SessionListView.swift
//  Notchwatch
//
//  One row per live session, for the expanded panel.
//

import SwiftUI

/// Every watched session, one row each.
///
/// The panel's single-valued readouts — context, branch, model — describe the
/// *focused* session, chosen by "active first, then most recently heard from".
/// With more than one session live that focus moves on its own, so a context bar
/// read twice can silently be reporting two different sessions. Naming the
/// sessions and giving each its own bar is what makes the reading mean something.
///
/// This belongs to the expanded panel only. The closed tray stays a single
/// glanceable signal: a notch is a surface for one look, not a dashboard.
struct SessionListView: View {
    @ObservedObject var manager: ClaudeCodeManager
    @ObservedObject var settings: AppSettings

    var body: some View {
        VStack(spacing: 4) {
            // Busy first, then whichever spoke most recently — the same order the
            // focus itself uses, so the top row is the one the pinned readouts
            // would have described.
            let rows = manager.availableSessions.compactMap { session -> (ClaudeSession, ClaudeCodeState)? in
                manager.sessionStates[session.id].map { (session, $0) }
            }
            .sorted { lhs, rhs in
                // Whatever is asking for the user comes first — that is the
                // question the list is opened to answer. Recency only orders
                // sessions of equal standing.
                let left = Standing(lhs.1), right = Standing(rhs.1)
                if left.rank != right.rank {
                    return left.rank < right.rank
                }
                return (lhs.1.lastUpdateTime ?? .distantPast) > (rhs.1.lastUpdateTime ?? .distantPast)
            }

            ForEach(rows, id: \.0.id) { session, state in
                SessionRow(state: state, limit: settings.effectiveContextLimit(for: state))
                    .onTapGesture {
                        manager.focusIDE(for: session)
                    }
            }
        }
    }
}

private struct SessionRow: View {
    let state: ClaudeCodeState
    let limit: Int

    /// The working directory's last component. The full path is too long for the
    /// panel and its tail is what distinguishes one session from another anyway —
    /// two sessions of the same project are told apart by their branch below.
    private var projectName: String {
        let name = (state.cwd as NSString).lastPathComponent
        return name.isEmpty ? "unknown" : name
    }

    /// Head of the session id. Several sessions of one project on one branch are
    /// otherwise indistinguishable — three rows reading `hypomnemata main` tell
    /// you there are three and nothing else. This is the same id Claude Code
    /// names its transcript files by, so it is the handle that leads somewhere.
    private var shortID: String {
        String(state.sessionId.prefix(6))
    }

    /// How long since this session last did anything. The bar answers how full
    /// it is; this answers whether anyone is home.
    private var idleFor: String? {
        guard let last = state.lastUpdateTime else { return nil }
        let seconds = Int(Date().timeIntervalSince(last))
        if seconds < 10 {
            return nil
        }
        if seconds < 60 {
            return "\(seconds)s"
        }
        if seconds < 3600 {
            return "\(seconds / 60)m"
        }
        return "\(seconds / 3600)h"
    }

    private var fraction: Double {
        state.tokenUsage.contextFraction(window: limit)
    }

    private var barColor: Color {
        if fraction > 0.9 {
            return .red
        }
        if fraction > 0.7 {
            return .orange
        }
        if fraction > 0.5 {
            return .yellow
        }
        return .green
    }

    private var standing: Standing {
        Standing(state)
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(standing.color)
                    .frame(width: 6, height: 6)

                if let label = standing.label {
                    Text(label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(standing.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(standing.color.opacity(0.15), in: Capsule())
                }

                Text(projectName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if !state.gitBranch.isEmpty {
                    Text(state.gitBranch)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.purple.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if !shortID.isEmpty {
                    Text(shortID)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                }

                Spacer(minLength: 4)

                if let idleFor {
                    Text(idleFor)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }

                Text("\(formatTokens(state.tokenUsage.promptTokens)) / \(formatTokens(limit))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(barColor.opacity(0.75))
                        .frame(width: geo.size.width * min(max(fraction, 0), 1))
                }
            }
            .frame(height: 3)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Token counts, short enough for a notch: `326.6k` rather than `326571`.
///
/// Shared rather than repeated — three views inside the panel each carried a
/// private copy of this, which is three chances for the readouts to disagree.
func formatTokens(_ count: Int) -> String {
    if count >= 1000 {
        return String(format: "%.1fk", Double(count) / 1000.0)
    }
    return "\(count)"
}

/// What the row is telling the reader.
///
/// Four states, and the two that want the user were previously
/// indistinguishable from the two that do not: a session awaiting a reply
/// shared the idle grey, and one awaiting permission was within a shade of
/// the working orange. Reading the list to find "which of these is calling
/// me" was therefore guesswork — which is the only question the list is
/// opened to answer when the notch has gone green.
///
/// This is deliberately the plain fact, not the notch's notification: the
/// border clears once the user looks, because it is an alarm. A session that
/// is waiting is still waiting after it has been seen, so the row keeps
/// saying so until it is answered.
private enum Standing {
    case needsPermission
    case awaitingReply
    case working
    case idle

    var color: Color {
        switch self {
        case .needsPermission: Color(red: 1.0, green: 0.72, blue: 0.2)
        case .awaitingReply: Color(red: 0.3, green: 0.85, blue: 0.55)
        case .working: Color(red: 0.9, green: 0.4, blue: 0.1)
        case .idle: Color.white.opacity(0.25)
        }
    }

    /// Spelled out for the two that are asking for something. Colour alone
    /// is a poor carrier — four hues in a small row are hard to hold apart,
    /// and impossible for a reader who does not separate red from green.
    var label: String? {
        switch self {
        case .needsPermission: "needs you"
        case .awaitingReply: "your turn"
        case .working, .idle: nil
        }
    }

    /// Rows sort by this: the ones asking for something first.
    var rank: Int {
        switch self {
        case .needsPermission: 0
        case .awaitingReply: 1
        case .working: 2
        case .idle: 3
        }
    }

    init(_ state: ClaudeCodeState) {
        if state.needsPermission {
            self = .needsPermission
        } else if state.isSessionComplete {
            self = .awaitingReply
        } else if state.isActive {
            self = .working
        } else {
            self = .idle
        }
    }
}
