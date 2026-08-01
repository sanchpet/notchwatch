//
//  HookSpool.swift
//  Notchwatch
//
//  The drop box hook processes write to and the app reads from.
//

import Foundation

/// Location and naming of the hook spool.
///
/// A directory of one-file-per-event, published by `rename(2)`, is the transport
/// because of what a hook is allowed to cost. `PreToolUse` runs *before* the tool
/// it describes, so a hook that blocks — on a socket with no listener, on a lock
/// held by another session — stalls the user's agent. Writing a file and renaming
/// it never waits on us being alive, and the rename makes a reader see the whole
/// event or none of it. Appending to a shared log would not: a `Write` tool's
/// payload is far past `PIPE_BUF`, so concurrent sessions would interleave.
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

    /// Events older than this are stale — the app was not running when they were
    /// written, and replaying them would show a session state long since gone.
    static let maxEventAge: TimeInterval = 5 * 60

    static func createDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Names sort in arrival order, so a directory listing replays events in the
    /// order the hooks fired.
    static func eventFileName(now: Date = Date()) -> String {
        let milliseconds = UInt64(now.timeIntervalSince1970 * 1000)
        return String(format: "%016llu-%@.json", milliseconds, UUID().uuidString)
    }
}
