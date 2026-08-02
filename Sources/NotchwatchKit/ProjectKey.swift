//
//  ProjectKey.swift
//  NotchwatchKit
//
//  The name Claude Code gives the directory that holds a project's transcripts.
//

import Foundation

/// Translation between a working directory and the transcript directory named
/// after it — `<config root>/projects/<key>/<session id>.jsonl`.
///
/// Claude Code builds that name by replacing **every non-alphanumeric character**
/// with a dash, not just the separators. The distinction is not academic: this
/// repository lives at `…/hypomnemata/.repos/github/notchwatch`, whose directory
/// is `-Users-…-hypomnemata--repos-github-notchwatch` — two dashes, one for the
/// separator and one for the dot. Escaping only `/` produced `-.repos-`, no such
/// directory existed, and every session in a dot-directory (`.repos`, `.config`,
/// any dotfiles checkout) was watched by nobody and shown nowhere.
///
/// The mapping is **many-to-one and therefore not invertible**: a dash in the
/// path, a slash, and a dot all arrive as the same dash. `decode` is a guess kept
/// only for the one thing it is good for — see its own note.
public enum ProjectKey {
    /// Longest directory name Claude Code writes before it truncates and appends
    /// a hash of the full path. The hash is not reproducible here, so a path this
    /// long is matched by its surviving prefix rather than by equality.
    public static let maximumLength = 200

    /// The transcript directory name for `workspacePath`.
    public static func encode(_ workspacePath: String) -> String {
        // Claude Code is JavaScript, so the replacement runs over UTF-16 code
        // units against an ASCII-only character class. A Cyrillic directory name
        // therefore becomes one dash per character and an emoji two — which only
        // walking the same units reproduces. `Character.isLetter` would keep both.
        let units = workspacePath.utf16.map { unit -> UInt16 in
            switch unit {
            case 0x30 ... 0x39, 0x41 ... 0x5A, 0x61 ... 0x7A:
                return unit
            default:
                return 0x2D // "-"
            }
        }
        return String(decoding: units, as: UTF16.self)
    }

    /// A working directory that *could* have produced `directoryName`.
    ///
    /// Lossy by construction — every dash becomes a slash, so a real dash in a
    /// directory name comes back as a separator and a dot comes back as an empty
    /// path component. It is used for two things that tolerate that: keying a
    /// terminal session, whose true directory arrives later in the transcript's
    /// `cwd`, and deriving a display name, which only needs the last component.
    ///
    /// What it must not lose is the round trip: `encode(decode(name)) == name`
    /// for every name Claude Code writes, which is what lets a session keyed off
    /// a decoded path still find the directory it came from.
    public static func decode(_ directoryName: String) -> String {
        let path = directoryName.replacingOccurrences(of: "-", with: "/")
        return path.hasPrefix("/") ? path : "/" + path
    }

    /// Whether `directoryName` is the transcript directory of `workspacePath`.
    ///
    /// Case-insensitive because the comparison stands in for a filesystem lookup,
    /// and the default macOS filesystem is case-insensitive: a session reported
    /// with a differently-cased path is the same project.
    public static func matches(directoryName: String, workspacePath: String) -> Bool {
        let key = encode(workspacePath)
        if directoryName.compare(key, options: .caseInsensitive) == .orderedSame {
            return true
        }
        guard key.count > maximumLength else { return false }
        // Truncated form: the first `maximumLength` characters, then a dash and a
        // hash of the whole path. Only the prefix can be checked.
        let prefix = String(key.prefix(maximumLength)) + "-"
        return directoryName.count > prefix.count
            && directoryName.prefix(prefix.count).compare(prefix, options: .caseInsensitive) == .orderedSame
    }
}
