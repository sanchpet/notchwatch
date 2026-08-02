//
//  EditorLockTests.swift
//  NotchwatchKitTests
//
//  What a lock file is allowed to claim. Two shipped defects came from letting
//  it claim more: one project collapsed into one session, and a terminal session
//  wearing an editor's name.
//

@testable import NotchwatchKit
import Testing

@Suite("Editor locks")
struct EditorLockTests {
    private static let workspace = "/Users/dev/app"
    private static let editor = "Visual Studio Code"

    private static func expand(_ liveSessionIDs: [String], workspace: String = Self.workspace) -> [EditorLock.Session] {
        EditorLock.expand(workspace: workspace, ideName: editor, liveSessionIDs: liveSessionIDs)
    }

    /// The regression. A lock names a project, and a project can hold several
    /// live sessions; resolving it to the most recently written transcript left
    /// the others unwatched, uncounted and unselectable — invisible, with no
    /// symptom other than an app that seemed to know about one session.
    @Test("every live transcript of the project becomes a session")
    func everyLiveTranscriptBecomesASession() {
        let sessions = Self.expand(["aaa", "bbb", "ccc"])

        #expect(sessions.count == 3)
        #expect(sessions.map(\.workspace) == [
            "/Users/dev/app#aaa",
            "/Users/dev/app#bbb",
            "/Users/dev/app#ccc",
        ])
    }

    /// The second regression, and the reason the first fix is not enough on its
    /// own: with several sessions the lock says which editor is open, not which
    /// of them it hosts — most run in a terminal. Copying its name onto all of
    /// them makes "go to this session" raise the wrong application, confidently.
    @Test("with several sessions the host is unknown")
    func severalSessionsMakeTheHostUnknown() {
        let sessions = Self.expand(["aaa", "bbb"])

        #expect(sessions.allSatisfy { $0.host == EditorLock.unknownHost })
        #expect(sessions.contains { $0.host == Self.editor } == false)
    }

    /// The one case where the claim holds: one live session in the project, so
    /// the editor holding the lock can only be hosting that one.
    @Test("a single session may be credited to the editor")
    func singleSessionIsCreditedToTheEditor() {
        let sessions = Self.expand(["aaa"])

        #expect(sessions.count == 1)
        #expect(sessions.first?.host == Self.editor)
        #expect(sessions.first?.workspace == "/Users/dev/app#aaa")
    }

    /// An editor left open on a project nobody is working in is not a session.
    /// Answering with the newest stale transcript is exactly what put a finished
    /// session back on screen.
    @Test("a project with no live transcript expands to nothing")
    func noLiveTranscriptExpandsToNothing() {
        #expect(Self.expand([]).isEmpty)
    }

    /// A workspace that already carries a fragment was resolved by something that
    /// knew which session it meant — a hook, or a previous expansion. It is
    /// passed through whole, host included: re-attributing it would undo the
    /// answer of whoever did know.
    @Test("an already-resolved workspace is passed through")
    func resolvedWorkspaceIsPassedThrough() {
        let sessions = Self.expand([], workspace: "/Users/dev/app#aaa")

        #expect(sessions.count == 1)
        #expect(sessions.first?.workspace == "/Users/dev/app#aaa")
        #expect(sessions.first?.host == Self.editor)
    }

    /// The rule on its own, stated once so the two callers cannot drift: only a
    /// count of one licenses a host.
    @Test("only a count of one licenses a host")
    func onlyOneLicensesAHost() {
        #expect(EditorLock.host(ideName: Self.editor, liveSessionCount: 1) == Self.editor)
        #expect(EditorLock.host(ideName: Self.editor, liveSessionCount: 0) == EditorLock.unknownHost)
        #expect(EditorLock.host(ideName: Self.editor, liveSessionCount: 2) == EditorLock.unknownHost)
        #expect(EditorLock.host(ideName: Self.editor, liveSessionCount: 7) == EditorLock.unknownHost)
    }

    /// A dot-directory project has to survive expansion too: the workspace path
    /// is carried through untouched, so the key still encodes to the directory
    /// Claude Code actually wrote.
    @Test("a dot-directory workspace survives expansion")
    func dotDirectoryWorkspaceSurvivesExpansion() {
        let sessions = Self.expand(["aaa"], workspace: "/Users/dev/vault/.repos/homelab")

        #expect(sessions.first?.workspace == "/Users/dev/vault/.repos/homelab#aaa")
        #expect(
            WorkspaceRef(sessions.first?.workspace ?? "").projectKey
                == "-Users-dev-vault--repos-homelab"
        )
    }
}
