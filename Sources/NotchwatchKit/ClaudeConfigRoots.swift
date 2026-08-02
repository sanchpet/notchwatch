//
//  ClaudeConfigRoots.swift
//  NotchwatchKit
//
//  Which configuration roots hold sessions worth watching.
//

import Foundation

/// Selection of Claude Code configuration roots out of the home directory.
///
/// `~/.claude` is only the default. `CLAUDE_CONFIG_DIR` moves the whole
/// configuration elsewhere, and keeping separate accounts in `~/.claude-personal`
/// and `~/.claude-work` is the documented way to run more than one. Reading the
/// default root alone therefore misses every session of anyone who uses that
/// mechanism — silently, because the default root still exists and still holds
/// whatever transcripts were written before the split, so the app looks like it
/// is working and shows nothing.
///
/// The variable itself cannot be read: the app is launched from Finder and
/// inherits no shell environment. The roots are found instead, by the `projects`
/// directory that makes a root a root — which is why the check is a parameter
/// here, and the whole rule is decidable without a filesystem.
public enum ClaudeConfigRoots {
    /// The roots to watch, the default one first, each listed once.
    ///
    /// - Parameters:
    ///   - home: the user's home directory.
    ///   - entries: its contents. Must be listed *without* `.skipsHiddenFiles` —
    ///     every root is a dot-directory, so that option hides exactly what is
    ///     being looked for.
    ///   - hasProjects: whether a candidate holds a `projects` directory.
    public static func select(home: URL, entries: [URL], hasProjects: (URL) -> Bool) -> [URL] {
        // Seeding the default root keeps it first when it exists; the dedup below
        // drops the copy the directory listing then yields. Sorting the rest makes
        // the order of two profiles independent of the order the filesystem
        // happens to return them in.
        let candidates = [home.appendingPathComponent(".claude")] + entries.sorted { $0.path < $1.path }

        var seen = Set<String>()
        return candidates
            .filter { isRootName($0.lastPathComponent) }
            .filter(hasProjects)
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// `.claude` itself, or a `.claude-<profile>` beside it.
    ///
    /// The dash matters: `~/.claude.json` and `~/.claude.json.backup` sit in the
    /// same directory and are files, not roots. They fail this test on their own
    /// rather than by luck of not holding a `projects` directory.
    public static func isRootName(_ name: String) -> Bool {
        name == ".claude" || name.hasPrefix(".claude-")
    }
}
