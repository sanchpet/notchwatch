//
//  HookRelay.swift
//  Notchwatch
//
//  The app binary in its second role: a Claude Code hook command.
//

import Foundation

/// Copies one hook payload from standard input into the spool and exits.
///
/// The app ships a single binary; invoked with `--hook-relay` it never brings up
/// AppKit and never touches the running instance. That keeps the hook independent
/// of whether the app is running, and keeps the install instructions to one path.
///
/// The overriding rule is **fail open**. A hook that exits non-zero or hangs is
/// felt by the user as their agent misbehaving, and `PreToolUse` can block a tool
/// outright. So every path here ends in `exit(0)` and a watchdog enforces the
/// deadline: dropping an event costs a stale display for a moment, refusing to
/// return costs the user their session.
enum HookRelay {
    static let flag = "--hook-relay"

    /// Beyond this the payload is a tool input we would not display anyway
    /// (a whole file being written), and buffering it is pure cost.
    private static let maxPayloadBytes = 4 * 1024 * 1024

    /// Wall-clock budget for the whole relay, stdin included.
    private static let deadline: TimeInterval = 2.0

    static func isRelayInvocation(_ arguments: [String]) -> Bool {
        arguments.dropFirst().contains(flag)
    }

    static func run() -> Never {
        // Armed before the first blocking call: if Claude Code holds stdin open,
        // or the volume stalls, the hook still returns inside its budget.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + deadline) {
            exit(0)
        }

        let payload = FileHandle.standardInput.readDataToEndOfFile()
        guard !payload.isEmpty, payload.count <= maxPayloadBytes else { exit(0) }

        deliver(payload)
        exit(0)
    }

    private static func deliver(_ payload: Data) {
        let directory = HookSpool.directory
        guard (try? HookSpool.createDirectory()) != nil else { return }

        let name = HookSpool.eventFileName()
        // Staged in the same directory so the publish is a rename within one
        // volume — the atomicity the reader depends on.
        let staged = directory.appendingPathComponent(".\(name).partial")
        let published = directory.appendingPathComponent(name)

        do {
            try payload.write(to: staged, options: .atomic)
            try FileManager.default.moveItem(at: staged, to: published)
        } catch {
            try? FileManager.default.removeItem(at: staged)
        }
    }
}
