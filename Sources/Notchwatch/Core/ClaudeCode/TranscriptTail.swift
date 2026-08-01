//
//  TranscriptTail.swift
//  Notchwatch
//
//  Incremental, line-boundary-safe reading of a Claude Code transcript.
//

import Foundation

/// Tracks one transcript's read position and the bytes of a line that has not
/// arrived in full yet.
///
/// Claude Code appends to the transcript while we read it, so a read can land in
/// the middle of a line — and a single line can be megabytes long
/// (`file-history-snapshot` entries routinely are). Both facts were previously
/// ignored: the read position was advanced past everything fetched and the
/// partial line thrown away, so any entry straddling two file-system
/// notifications was lost for good, and a history window measured in bytes could
/// be filled entirely by one snapshot line.
///
/// Here the position advances over bytes *taken into the buffer*, never over
/// bytes parsed, and the remainder is carried to the next read.
struct TranscriptTail {
    /// How far back to look when a transcript is first attached. Large enough
    /// that a couple of snapshot lines cannot crowd out the real entries.
    static let historyWindowBytes: UInt64 = 2 * 1024 * 1024

    /// Longest line worth decoding. Nothing we read — tool calls, usage, model —
    /// comes close; anything bigger is a snapshot or an embedded attachment, and
    /// turning it into a String costs far more than it can tell us.
    static let maxLineBytes = 256 * 1024

    private static let newline = UInt8(ascii: "\n")

    /// Byte offset of the first byte not yet buffered.
    private(set) var offset: UInt64 = 0

    private var pending = Data()

    /// True while the bytes ahead belong to a line already rejected for length.
    private var isSkippingOverlongLine = false

    // MARK: - Reading

    /// Complete lines appended since the last call.
    ///
    /// A transcript that shrank was replaced (a new session reusing the path, or
    /// a rewrite), so the position resets rather than seeking past the new end.
    mutating func read(_ handle: FileHandle) -> [String] {
        guard let size = try? handle.seekToEnd() else { return [] }

        if size < offset {
            offset = 0
            pending.removeAll(keepingCapacity: false)
            isSkippingOverlongLine = false
        }
        guard size > offset else { return [] }

        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return [] }
        offset += UInt64(data.count)

        return consume(data)
    }

    /// Start reading at the end of the transcript, ignoring what is already there.
    mutating func seekToEnd(_ handle: FileHandle) {
        offset = (try? handle.seekToEnd()) ?? 0
        pending.removeAll(keepingCapacity: false)
        isSkippingOverlongLine = false
    }

    // MARK: - History

    /// The last `maxLines` usable lines of `file`.
    static func history(of file: URL, maxLines: Int) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return [] }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > historyWindowBytes ? size - historyWindowBytes : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd() else { return [] }

        var tail = TranscriptTail()
        var lines = tail.consume(data)
        // A window that opens mid-file opens mid-line; that fragment is not JSON.
        if start > 0, !lines.isEmpty {
            lines.removeFirst()
        }
        return Array(lines.suffix(maxLines))
    }

    /// The first line of `file` that carries a value for `key`.
    ///
    /// Used for facts fixed at session start (the working directory), which the
    /// tail cannot answer because it only ever sees the recent end of the file.
    static func firstValue(forKey key: String, in file: URL, scanningFirstBytes limit: Int = 64 * 1024) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit) else { return nil }

        var tail = TranscriptTail()
        for line in tail.consume(data) {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let value = json[key] as? String,
                  !value.isEmpty else { continue }
            return value
        }
        return nil
    }

    // MARK: - Buffering

    /// Split `chunk` into complete lines, keeping any unterminated remainder.
    private mutating func consume(_ chunk: Data) -> [String] {
        pending.append(chunk)

        guard let lastNewline = pending.lastIndex(of: Self.newline) else {
            // No line boundary in sight. A remainder this large is not a line we
            // would parse anyway, so drop it and resynchronise on the next one —
            // otherwise one snapshot line grows the buffer without bound.
            if pending.count > Self.maxLineBytes {
                pending.removeAll(keepingCapacity: false)
                isSkippingOverlongLine = true
            }
            return []
        }

        let complete = pending[pending.startIndex ... lastNewline]
        pending = Data(pending[pending.index(after: lastNewline)...])

        var lines: [String] = []
        for raw in complete.split(separator: Self.newline, omittingEmptySubsequences: true) {
            if isSkippingOverlongLine {
                // The tail of the line we already gave up on.
                isSkippingOverlongLine = false
                continue
            }
            guard raw.count <= Self.maxLineBytes,
                  let line = String(data: raw, encoding: .utf8) else { continue }
            lines.append(line)
        }
        return lines
    }
}
