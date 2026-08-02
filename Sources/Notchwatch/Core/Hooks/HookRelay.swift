//
//  HookRelay.swift
//  Notchwatch
//
//  The app binary in its second role: a Claude Code hook command.
//

import Foundation
import NotchwatchKit

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
/// return costs the user their session. Nothing here is allowed to trap, either —
/// a crash is a non-zero exit with a stack trace in the user's terminal.
enum HookRelay {
    static let flag = HookSettings.relayFlag

    /// Beyond this the payload is a tool input we would not display anyway
    /// (a whole file being written), and buffering it is pure cost.
    private static let maxPayloadBytes = 4 * 1024 * 1024

    /// Wall-clock budget for the whole relay, stdin included.
    private static let deadline: TimeInterval = 2.0

    private static let readChunkBytes = 64 * 1024

    static func isRelayInvocation(_ arguments: [String]) -> Bool {
        arguments.dropFirst().contains(flag)
    }

    static func run() -> Never {
        // Armed before the first blocking call: if Claude Code holds stdin open,
        // or the volume stalls, the hook still returns inside its budget.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + deadline) {
            exit(0)
        }

        if let payload = readPayload(), !payload.isEmpty {
            deliver(payload)
        }
        // Whoever wrote last sweeps: with the app not running there is no other
        // reader, and an unswept spool is the one way this transport grows
        // without bound. Deliberately after the publish, so a sweep over a large
        // directory delays nothing but our own exit.
        HookSpool.discardStale()
        exit(0)
    }

    /// The payload, or nil if there is nothing usable to deliver.
    ///
    /// Read through `read(2)` rather than `FileHandle.readDataToEndOfFile`, for
    /// two reasons that are both about failing open. The `FileHandle` call raises
    /// an Objective-C exception on a read error — which Swift cannot catch, so a
    /// closed or unreadable descriptor would abort the process instead of
    /// returning quietly. And it reads to the end before anyone can look at the
    /// size, so the 4 MB ceiling was applied to a payload that had already been
    /// buffered whole; here it stops the read instead.
    private static func readPayload() -> Data? {
        var payload = Data()
        var buffer = [UInt8](repeating: 0, count: readChunkBytes)

        while true {
            let count = buffer.withUnsafeMutableBytes { read(STDIN_FILENO, $0.baseAddress, $0.count) }
            if count > 0 {
                payload.append(contentsOf: buffer[0 ..< count])
                if payload.count > maxPayloadBytes {
                    return nil
                }
                continue
            }
            if count == 0 {
                return payload
            }
            if errno == EINTR {
                continue
            }
            return nil
        }
    }

    private static func deliver(_ payload: Data) {
        let directory = HookSpool.directory
        guard (try? HookSpool.createDirectory()) != nil else { return }

        let name = HookSpoolName.event(at: Date())
        // Staged in the same directory so the publish is a rename within one
        // volume — the atomicity the reader depends on.
        let staged = directory.appendingPathComponent(HookSpoolName.staging(for: name))
        let published = directory.appendingPathComponent(name)

        do {
            try payload.write(to: staged, options: .atomic)
            try FileManager.default.moveItem(at: staged, to: published)
        } catch {
            try? FileManager.default.removeItem(at: staged)
        }
    }
}
