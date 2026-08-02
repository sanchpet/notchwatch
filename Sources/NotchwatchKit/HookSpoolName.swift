//
//  HookSpoolName.swift
//  NotchwatchKit
//
//  How one spooled hook event is named.
//

import Foundation

/// Naming of the files the relay drops and the app picks up.
///
/// Two things ride on the name and neither is cosmetic. A directory listing is
/// replayed in lexical order, so the name has to sort by arrival — a tool that
/// started after another must not be replayed before it. And the file being
/// written is told apart from the file being published by its name alone, so a
/// reader that lists the directory mid-write picks up nothing half-formed.
public enum HookSpoolName {
    public static let fileExtension = "json"

    /// Zero-padded so that lexical order is chronological order. Milliseconds
    /// because two hooks of one tool call can land inside the same second; the
    /// identifier breaks the tie when they land inside the same millisecond.
    public static func event(at time: Date, id: UUID = UUID()) -> String {
        String(format: "%016llu-%@.%@", UInt64(time.timeIntervalSince1970 * 1000), id.uuidString, fileExtension)
    }

    /// Where the payload is written before being renamed into place. Hidden and
    /// differently suffixed, so it fails `isEvent` twice over.
    public static func staging(for name: String) -> String {
        ".\(name).partial"
    }

    /// Whether a directory entry is a published event.
    ///
    /// Excludes both the staging file and the temporaries Foundation leaves
    /// behind for an atomic write, which are hidden and carry no extension.
    public static func isEvent(_ name: String) -> Bool {
        !name.hasPrefix(".") && name.hasSuffix(".\(fileExtension)")
    }
}
