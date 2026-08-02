//
//  ClaudeModelPinTests.swift
//  NotchwatchKitTests
//
//  Which settings file the opt-in is read from. Reading the wrong one is a
//  silent failure: the pin simply reports "no long window" and the bar measures
//  a 1M context against 200k.
//

import Foundation
@testable import NotchwatchKit
import Testing

@Suite("Model pin")
struct ClaudeModelPinTests {
    private static let project = "/Users/dev/work/service"
    private static let configRoot = URL(fileURLWithPath: "/Users/dev/.claude-personal")

    /// A reader over a fixed table of paths, standing in for the filesystem.
    private static func reader(_ pins: [String: String]) -> (URL) -> String? {
        { url in pins[url.path] }
    }

    private static func declaresLongWindow(
        projectDirectory: String? = Self.project,
        configRoot: URL? = Self.configRoot,
        pins: [String: String]
    ) -> Bool {
        ClaudeModelPin.declaresLongWindow(
            projectDirectory: projectDirectory,
            configRoot: configRoot,
            readModel: reader(pins)
        )
    }

    /// The regression this layering exists for.
    ///
    /// The pin was read from `~/.claude` unconditionally. A session running under
    /// another configuration root — `CLAUDE_CONFIG_DIR`, i.e. a second profile —
    /// keeps its pin beside its own transcripts, so the default root answered for
    /// a file that has nothing to do with the session, and every session of every
    /// other profile came back "no opt-in".
    @Test("the session's own config root is what is read")
    func sessionConfigRootIsWhatIsRead() {
        let pins = [
            "/Users/dev/.claude-personal/settings.json": "opus[1m]",
            "/Users/dev/.claude/settings.json": "opus",
        ]

        #expect(Self.declaresLongWindow(pins: pins))

        // The default root is not consulted at all — no file under ~/.claude is
        // even opened, so a pin sitting there cannot answer for this session.
        let files = ClaudeModelPin.settingsFiles(projectDirectory: Self.project, configRoot: Self.configRoot)
        #expect(files.contains { $0.path.hasPrefix("/Users/dev/.claude/") } == false)
    }

    /// Most specific first, and the first file that *defines* `model` decides —
    /// a project pin without the suffix has to be able to override a user pin
    /// that has one, or a shared machine-wide pin would silently win everywhere.
    @Test("the most specific pin decides, suffix or not")
    func mostSpecificPinDecides() {
        #expect(
            Self.declaresLongWindow(pins: [
                "/Users/dev/work/service/.claude/settings.json": "opus",
                "/Users/dev/.claude-personal/settings.json": "opus[1m]",
            ]) == false
        )

        #expect(
            Self.declaresLongWindow(pins: [
                "/Users/dev/work/service/.claude/settings.json": "opus[1m]",
                "/Users/dev/.claude-personal/settings.json": "opus",
            ])
        )
    }

    /// `settings.local.json` is the personal, un-committed layer and outranks the
    /// checked-in `settings.json` at the same level.
    @Test("the local layer outranks the shared one")
    func localLayerOutranksTheSharedOne() {
        #expect(
            Self.declaresLongWindow(pins: [
                "/Users/dev/work/service/.claude/settings.local.json": "opus[1m]",
                "/Users/dev/work/service/.claude/settings.json": "opus",
            ])
        )

        #expect(
            Self.declaresLongWindow(pins: [
                "/Users/dev/.claude-personal/settings.local.json": "sonnet",
                "/Users/dev/.claude-personal/settings.json": "opus[1m]",
            ]) == false
        )
    }

    /// The full search order, spelled out. A file that defines no `model` is not
    /// a decision — the search goes on past it.
    @Test("the search order is project-local, project, root-local, root")
    func searchOrderIsMostSpecificFirst() {
        let files = ClaudeModelPin.settingsFiles(projectDirectory: Self.project, configRoot: Self.configRoot).map(\.path)

        #expect(files == [
            "/Users/dev/work/service/.claude/settings.local.json",
            "/Users/dev/work/service/.claude/settings.json",
            "/Users/dev/.claude-personal/settings.local.json",
            "/Users/dev/.claude-personal/settings.json",
        ])

        // Only the last file in that order defines a pin, and it is still found.
        #expect(Self.declaresLongWindow(pins: ["/Users/dev/.claude-personal/settings.json": "opus[1m]"]))
    }

    /// Nothing is known before a session's directory is: the transcript's first
    /// entries carry no `cwd`, and a session can be watched before one arrives.
    @Test("an unknown project falls back to the config root alone")
    func unknownProjectFallsBackToTheConfigRoot() {
        let pins = ["/Users/dev/.claude-personal/settings.local.json": "opus[1m]"]

        #expect(Self.declaresLongWindow(projectDirectory: nil, pins: pins))
        #expect(Self.declaresLongWindow(projectDirectory: "", pins: pins))
        #expect(ClaudeModelPin.settingsFiles(projectDirectory: "", configRoot: Self.configRoot).count == 2)
    }

    /// No pin anywhere is the common case, and it is not an opt-in.
    @Test("no pin means no opt-in")
    func noPinMeansNoOptIn() {
        #expect(Self.declaresLongWindow(pins: [:]) == false)
        #expect(ClaudeModelPin.settingsFiles(projectDirectory: nil, configRoot: nil).isEmpty)
    }

    /// A `model` key present but empty is not a pin — the file has been written by
    /// something that cleared it, and the layer below still has a say.
    @Test("an empty pin does not end the search")
    func emptyPinDoesNotEndTheSearch() {
        #expect(
            Self.declaresLongWindow(pins: [
                "/Users/dev/work/service/.claude/settings.json": "",
                "/Users/dev/.claude-personal/settings.json": "opus[1m]",
            ])
        )
    }
}
