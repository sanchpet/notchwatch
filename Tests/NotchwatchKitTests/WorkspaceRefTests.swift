//
//  WorkspaceRefTests.swift
//  NotchwatchKitTests
//
//  Reading "<path>#<transcript id>" — the key that tells one session of a
//  project from another, and the label the user reads in the panel.
//

@testable import NotchwatchKit
import Testing

@Suite("Workspace references")
struct WorkspaceRefTests {
    /// The form an editor lock arrives in: a project, with nothing saying which
    /// of its sessions is meant. Reading a session id out of it would be an
    /// invention, and everything downstream branches on its absence.
    @Test("a lock without a fragment names no session")
    func lockWithoutAFragmentNamesNoSession() {
        let reference = WorkspaceRef("/Users/dev/app")

        #expect(reference.path == "/Users/dev/app")
        #expect(reference.sessionID == nil)
        #expect(reference.raw == "/Users/dev/app")
        #expect(reference.displayName == "app")
    }

    /// The form the terminal scan and the hook bridge build.
    @Test("a fragment is the transcript id")
    func fragmentIsTheTranscriptID() {
        let reference = WorkspaceRef("/Users/dev/app#d587c100-1f4e-4f0a-9e6f-6b2a0b6f6c11")

        #expect(reference.path == "/Users/dev/app")
        #expect(reference.sessionID == "d587c100-1f4e-4f0a-9e6f-6b2a0b6f6c11")
        #expect(reference.displayName == "app")
    }

    /// Composing and parsing have to be inverses, or a session would be watched
    /// under one key and looked up under another.
    @Test("composing and parsing round-trip")
    func composingAndParsingRoundTrip() {
        let composed = WorkspaceRef(path: "/Users/dev/app", sessionID: "abc").raw
        #expect(composed == "/Users/dev/app#abc")
        #expect(WorkspaceRef(composed) == WorkspaceRef(path: "/Users/dev/app", sessionID: "abc"))

        // A `#` inside the path belongs to the path: only the first one splits,
        // so the rest survives the round trip instead of being silently dropped.
        let odd = WorkspaceRef("/Users/dev/c#sharp#abc")
        #expect(odd.path == "/Users/dev/c")
        #expect(odd.sessionID == "sharp#abc")
        #expect(odd.raw == "/Users/dev/c#sharp#abc")
    }

    /// A path decoded from a directory name holds empty components — the dot of
    /// `.repos` decodes to a second slash — and a trailing slash is ordinary.
    /// Taking the last component blindly would label the session with a blank.
    @Test("the display name skips empty components")
    func displayNameSkipsEmptyComponents() {
        #expect(WorkspaceRef("/Users/dev/hypomnemata//repos/homelab#abc").displayName == "homelab")
        #expect(WorkspaceRef("/Users/dev/app/").displayName == "app")
        #expect(WorkspaceRef("/Users/dev/app/#abc").displayName == "app")
    }

    /// The reference knows where its transcripts are filed; the manager should
    /// not be re-deriving that from the raw string, fragment and all.
    @Test("the project key comes from the path, not the fragment")
    func projectKeyComesFromThePath() {
        let bare = WorkspaceRef("/Users/dev/hypomnemata/.repos/homelab")
        let withSession = WorkspaceRef("/Users/dev/hypomnemata/.repos/homelab#abc")

        #expect(bare.projectKey == "-Users-dev-hypomnemata--repos-homelab")
        #expect(withSession.projectKey == bare.projectKey)
    }
}
