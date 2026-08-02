//
//  ClaudeConfigRootsTests.swift
//  NotchwatchKitTests
//
//  Which roots are watched. Reading only ~/.claude is a silent failure: the
//  default root still exists, still holds old transcripts, and the app shows
//  nothing while the user's real profile works away next door.
//

import Foundation
@testable import NotchwatchKit
import Testing

@Suite("Config roots")
struct ClaudeConfigRootsTests {
    private static let home = URL(fileURLWithPath: "/Users/dev")

    /// Selection over a fixed home directory listing, standing in for the
    /// filesystem: `withProjects` are the entries that hold a `projects`
    /// directory, and the rest exist but do not.
    private static func select(_ entries: [String], withProjects: Set<String>) -> [String] {
        ClaudeConfigRoots.select(
            home: home,
            entries: entries.map { home.appendingPathComponent($0) },
            hasProjects: { withProjects.contains($0.lastPathComponent) }
        ).map(\.lastPathComponent)
    }

    /// The regression. `CLAUDE_CONFIG_DIR` is unreadable from a Finder-launched
    /// app, so a profile is found by its directory: work goes on under
    /// `~/.claude-personal` while `~/.claude` sits there stale, and watching only
    /// the default root means watching the one root with nothing live in it.
    @Test("a profile beside the default root is watched")
    func profileBesideTheDefaultRootIsWatched() {
        let roots = Self.select(
            [".claude", ".claude-personal", ".claude-work", "Documents"],
            withProjects: [".claude", ".claude-personal", ".claude-work"]
        )

        #expect(roots == [".claude", ".claude-personal", ".claude-work"])
    }

    /// A machine that only ever used a profile has no default root at all, and
    /// must still be watched — this is the case where reading `~/.claude` alone
    /// finds literally nothing.
    @Test("the default root is not required")
    func defaultRootIsNotRequired() {
        #expect(Self.select([".claude-personal"], withProjects: [".claude-personal"]) == [".claude-personal"])
    }

    /// `projects` is what makes a root a root. A freshly created or half-migrated
    /// `.claude-*` directory holds settings and no transcripts; watching it adds
    /// a directory that never produces an event.
    @Test("a directory without projects is not a root")
    func directoryWithoutProjectsIsNotARoot() {
        let roots = Self.select(
            [".claude", ".claude-work"],
            withProjects: [".claude"]
        )

        #expect(roots == [".claude"])
    }

    /// `~/.claude.json` and its backup sit right beside the roots and start with
    /// the same eight characters. They are files, and the name test rejects them
    /// on its own rather than by luck of holding no `projects` directory.
    @Test("the settings file next door is not a root")
    func settingsFileNextDoorIsNotARoot() {
        #expect(ClaudeConfigRoots.isRootName(".claude"))
        #expect(ClaudeConfigRoots.isRootName(".claude-personal"))
        #expect(ClaudeConfigRoots.isRootName(".claude.json") == false)
        #expect(ClaudeConfigRoots.isRootName(".claude.json.backup") == false)
        #expect(ClaudeConfigRoots.isRootName("claude") == false)
        #expect(ClaudeConfigRoots.isRootName(".claudecode") == false)

        // Even when something claims they hold `projects`, they are not selected.
        #expect(
            Self.select(
                [".claude.json", ".claude.json.backup"],
                withProjects: [".claude.json", ".claude.json.backup"]
            ).isEmpty
        )
    }

    /// The default root comes first — it is the one most sessions are under, and
    /// the lookups that stop at the first hit should try it first. The rest are
    /// ordered by name so two profiles do not swap places between scans.
    @Test("the default root leads and the rest are ordered")
    func defaultRootLeadsAndTheRestAreOrdered() {
        let roots = Self.select(
            [".claude-work", ".claude-personal", ".claude"],
            withProjects: [".claude", ".claude-personal", ".claude-work"]
        )

        #expect(roots == [".claude", ".claude-personal", ".claude-work"])
    }

    /// The default root is seeded *and* listed by the directory scan, so without
    /// a dedup it would be watched twice — two file-system sources on every
    /// transcript, and every tool counted twice.
    @Test("the default root is listed once")
    func defaultRootIsListedOnce() {
        #expect(Self.select([".claude"], withProjects: [".claude"]) == [".claude"])
    }
}
