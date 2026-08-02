//
//  HookSpool.swift
//  Notchwatch
//
//  The drop box hook processes write to and the app reads from.
//

import Foundation
import NotchwatchKit

/// Location and upkeep of the hook spool.
///
/// A directory of one-file-per-event, published by `rename(2)`, is the transport
/// because of what a hook is allowed to cost. `PreToolUse` runs *before* the tool
/// it describes, so a hook that blocks — on a socket with no listener, on a lock
/// held by another session — stalls the user's agent. Writing a file and renaming
/// it never waits on us being alive, and the rename makes a reader see the whole
/// event or none of it. Appending to a shared log would not: a `Write` tool's
/// payload is far past `PIPE_BUF`, so concurrent sessions would interleave.
///
/// The transport's one liability is that nobody has to be reading. Every writer
/// therefore sweeps as well, which is what keeps a spool nobody drains — the app
/// quit, the bridge switched off — from growing for as long as Claude Code runs.
enum HookSpool {
    /// Used when the relay runs outside a bundle (a development build invoked
    /// straight from `.build`), where there is no bundle identifier to read.
    static let fallbackIdentifier = "io.github.sanchpet.notchwatch"

    static var directory: URL {
        let identifier = Bundle.main.bundleIdentifier ?? fallbackIdentifier
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent(identifier, isDirectory: true)
            .appendingPathComponent("hook-events", isDirectory: true)
    }

    /// Events older than this are stale — nothing was draining them when they
    /// were written, and replaying them would show a session state long since
    /// gone. It is also the bound on the spool: with every writer sweeping, the
    /// directory cannot hold more than this much of Claude Code's output.
    static let maxEventAge: TimeInterval = 5 * 60

    static func createDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Delete everything past `maxEventAge`, whatever it is.
    ///
    /// By modification time rather than by the timestamp in the name, so that the
    /// abandoned staging file of a relay that was killed mid-write is collected
    /// too — the one kind of leftover that nothing else removes.
    static func discardStale(now: Date = Date()) {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: []
        ) else { return }

        let cutoff = now.addingTimeInterval(-maxEventAge)
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if (modified ?? .distantPast) < cutoff {
                try? fileManager.removeItem(at: file)
            }
        }
    }
}
