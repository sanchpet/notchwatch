//
//  WorkspaceRef.swift
//  NotchwatchKit
//
//  The "<path>#<session id>" string every discovered session is keyed by.
//

import Foundation

/// A session's workspace reference: where it runs, and which of that project's
/// sessions it is.
///
/// The fragment is what makes the key a *session* rather than a *project*. An
/// editor lock carries a bare path, and resolving one to a single transcript hid
/// every other session of the same project; appending the transcript id gives
/// each one an identity that survives a rescan. Both forms have to be readable
/// here because both are in circulation — locks arrive bare, terminal and hook
/// sessions arrive with a fragment.
public struct WorkspaceRef: Equatable {
    /// The working directory, with any fragment removed.
    public let path: String
    /// The transcript id, when the reference names one session rather than a
    /// whole project.
    public let sessionID: String?

    /// Splits `raw` at the first `#`. Everything after it is the id: a transcript
    /// id is a UUID and contains no `#`, so a second one belongs to the path and
    /// putting it back is what keeps `raw` a round trip.
    public init(_ raw: String) {
        guard let hash = raw.firstIndex(of: "#") else {
            path = raw
            sessionID = nil
            return
        }
        path = String(raw[raw.startIndex ..< hash])
        sessionID = String(raw[raw.index(after: hash)...])
    }

    public init(path: String, sessionID: String?) {
        self.path = path
        self.sessionID = sessionID
    }

    /// The form stored in `ClaudeSession.workspaceFolders`.
    public var raw: String {
        guard let sessionID else { return path }
        return "\(path)#\(sessionID)"
    }

    /// What the UI calls this session: the last component of the working
    /// directory, never the fragment.
    ///
    /// A path decoded from a directory name can hold empty components — a dot in
    /// the real path decodes to `//` — so the last *non-empty* one is taken.
    /// Anything else would label a whole column of sessions with a blank.
    public var displayName: String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        return components.last.map(String.init) ?? path
    }

    /// The transcript directory this workspace's sessions are written to.
    public var projectKey: String {
        ProjectKey.encode(path)
    }
}
