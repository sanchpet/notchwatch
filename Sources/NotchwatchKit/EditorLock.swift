//
//  EditorLock.swift
//  NotchwatchKit
//
//  What an editor's lock file may, and may not, be taken to mean.
//

import Foundation

/// Resolution of an editor lock (`<config root>/ide/<pid>.lock`) into sessions.
///
/// A lock names a **project**, not a session: it carries a workspace path and the
/// editor's pid, and nothing that tells one Claude Code session in that project
/// from another. Two defects came out of reading it as more than that.
///
/// It was resolved to a single transcript — the most recently written — so every
/// other session of the project became invisible: not watched, not counted, not
/// selectable. And the editor's name was copied onto whatever session that
/// produced, so a session actually running in a terminal claimed to live in VS
/// Code and "go to this session" confidently raised the wrong application.
///
/// Both follow from the same missing rule, which is why it is stated once here:
/// **a lock may name the host only when the project has exactly one live
/// session.** With more than one it still proves the project is open, so the
/// sessions are real — but which of them the editor holds is not knowable, and
/// `unknownHost` is the honest answer.
public enum EditorLock {
    /// Host of a session that cannot be attributed to any application. The UI
    /// checks for it before offering to bring a host to the front.
    public static let unknownHost = "Unknown"

    /// One session resolved out of a lock.
    public struct Session: Equatable {
        /// `<path>#<transcript id>`, the key form the terminal scan also builds.
        public let workspace: String
        /// The editor's name, or `unknownHost`.
        public let host: String

        public init(workspace: String, host: String) {
            self.workspace = workspace
            self.host = host
        }
    }

    /// The sessions a lock stands for, given the project's live transcripts.
    ///
    /// - Parameter liveSessionIDs: transcript ids of that project written
    ///   recently enough to be running. Empty means the editor is open on a
    ///   project nobody is working in, which is **not** a session: answering with
    ///   the newest stale transcript is the defect this replaces.
    public static func expand(workspace: String, ideName: String, liveSessionIDs: [String]) -> [Session] {
        let reference = WorkspaceRef(workspace)
        // Already a session key — a hook or a scan resolved it, and it says which
        // session it is, so there is nothing to attribute or expand.
        guard reference.sessionID == nil else {
            return [Session(workspace: workspace, host: ideName)]
        }

        let host = host(ideName: ideName, liveSessionCount: liveSessionIDs.count)
        return liveSessionIDs.map {
            Session(workspace: WorkspaceRef(path: reference.path, sessionID: $0).raw, host: host)
        }
    }

    /// The host a lock may be credited with.
    public static func host(ideName: String, liveSessionCount: Int) -> String {
        liveSessionCount == 1 ? ideName : unknownHost
    }
}
