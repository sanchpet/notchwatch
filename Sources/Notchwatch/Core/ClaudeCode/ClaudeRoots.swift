//
//  ClaudeRoots.swift
//  Notchwatch
//
//  Which Claude Code configuration roots exist on this machine.
//

import Foundation
import NotchwatchKit

/// The configuration roots, read off the disk.
///
/// `~/.claude` is only the default. `CLAUDE_CONFIG_DIR` relocates the whole
/// directory and `~/.claude-personal` / `~/.claude-work` is the documented way to
/// run several profiles; the variable cannot be read from a Finder-launched app,
/// so the roots are discovered by the `projects` directory that makes a root a
/// root. Which candidates qualify is `ClaudeConfigRoots` in the kit; this only
/// lists the directory.
///
/// Everything that reads or writes Claude Code's configuration goes through here.
/// The session watcher and the hook installer disagreeing about which roots exist
/// is exactly how hooks came to be registered in a profile nobody was running.
enum ClaudeRoots {
    /// Read from the password database rather than `NSHomeDirectory` so that a
    /// future sandboxed build still finds the real home directory.
    static let home: URL = {
        if let pw = getpwuid(getuid()), let home = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home))
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()

    /// Every root on this machine, the default one first. Computed on demand: a
    /// profile can appear between launching the app and opening its settings.
    static var all: [URL] {
        let fileManager = FileManager.default
        // Deliberately without `.skipsHiddenFiles`: every root is a dot-directory,
        // so that option would hide exactly what is being looked for.
        let entries = (try? fileManager.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants]
        )) ?? []

        return ClaudeConfigRoots.select(home: home, entries: entries) {
            fileManager.fileExists(atPath: $0.appendingPathComponent("projects").path)
        }
    }
}
