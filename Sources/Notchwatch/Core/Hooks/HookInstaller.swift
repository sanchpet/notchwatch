//
//  HookInstaller.swift
//  Notchwatch
//
//  Registers (and unregisters) the relay in the user's Claude Code settings.
//

import Foundation

/// Adds or removes this app's hook entries in `~/.claude/settings.json`.
///
/// That file is the user's, not ours. Nothing here runs on launch or on a
/// settings toggle: every call sits behind an explicit action, the previous
/// contents are copied aside first, and `uninstall` removes exactly what
/// `install` added — the file is left as it was found, minus our entries.
///
/// Unknown keys survive because the file is read as a dictionary and written
/// back whole; only the hook arrays we own are touched.
@MainActor
enum HookInstaller {
    enum InstallError: LocalizedError {
        case settingsUnreadable(URL)
        case settingsNotAnObject(URL)

        var errorDescription: String? {
            switch self {
            case let .settingsUnreadable(url):
                "Could not read \(url.path)."
            case let .settingsNotAnObject(url):
                "\(url.path) is not a JSON object; refusing to rewrite it."
            }
        }
    }

    /// Hooks we subscribe to, and whether they are per-tool.
    static let subscribedEvents: [HookEvent.Kind] = [
        .sessionStart, .userPromptSubmit, .preToolUse, .postToolUse, .notification, .stop, .sessionEnd,
    ]

    /// Seconds Claude Code waits for the relay before giving up on it. The relay
    /// budgets less than this for itself; the setting is the outer guarantee that
    /// a wedged relay cannot hold up a tool.
    private static let commandTimeout = 5

    static var settingsFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    /// The command Claude Code will run. Quoted: the bundle lives under a path
    /// with a space in it more often than not.
    static var relayCommand: String {
        let executable = Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? "notchwatch"
        return "\"\(executable)\" \(HookRelay.flag)"
    }

    static var isInstalled: Bool {
        guard let settings = try? readSettings(),
              let hooks = settings["hooks"] as? [String: Any] else { return false }
        return subscribedEvents.contains { event in
            guard let matchers = hooks[event.rawValue] as? [[String: Any]] else { return false }
            return matchers.contains { containsOurCommand($0) }
        }
    }

    // MARK: - Mutation

    static func install() throws {
        var settings = try readSettings()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        for event in subscribedEvents {
            var matchers = (hooks[event.rawValue] as? [[String: Any]]) ?? []
            // Drop our own entry first so re-installing after a move updates the
            // path instead of stacking a second relay on every tool call.
            matchers.removeAll(where: { containsOurCommand($0) })
            matchers.append(matcherEntry(for: event))
            hooks[event.rawValue] = matchers
        }

        settings["hooks"] = hooks
        try writeSettings(settings)
    }

    static func uninstall() throws {
        var settings = try readSettings()
        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        for key in hooks.keys {
            guard var matchers = hooks[key] as? [[String: Any]] else { continue }
            matchers.removeAll(where: { containsOurCommand($0) })
            // An event left with no matchers is an empty array we introduced;
            // remove the key so the file returns to its original shape.
            if matchers.isEmpty {
                hooks.removeValue(forKey: key)
            } else {
                hooks[key] = matchers
            }
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }
        try writeSettings(settings)
    }

    // MARK: - Entries

    private static func matcherEntry(for event: HookEvent.Kind) -> [String: Any] {
        let command: [String: Any] = [
            "type": "command",
            "command": relayCommand,
            "timeout": commandTimeout,
        ]
        var entry: [String: Any] = ["hooks": [command]]
        if event.takesMatcher {
            entry["matcher"] = "*"
        }
        return entry
    }

    /// Our entries are recognised by the relay flag, which no other tool has a
    /// reason to pass. That keeps `uninstall` from touching a hook the user wrote.
    private static func containsOurCommand(_ entry: [String: Any]) -> Bool {
        guard let commands = entry["hooks"] as? [[String: Any]] else { return false }
        return commands.contains { ($0["command"] as? String)?.contains(HookRelay.flag) == true }
    }

    // MARK: - File access

    private static func readSettings() throws -> [String: Any] {
        let url = settingsFile
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        guard let data = FileManager.default.contents(atPath: url.path) else {
            throw InstallError.settingsUnreadable(url)
        }
        guard !data.isEmpty else { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw InstallError.settingsUnreadable(url)
        }
        guard let settings = object as? [String: Any] else {
            throw InstallError.settingsNotAnObject(url)
        }
        return settings
    }

    private static func writeSettings(_ settings: [String: Any]) throws {
        let url = settingsFile
        try backupSettings()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        try data.write(to: url, options: .atomic)
    }

    /// Re-serialising the file normalises its formatting, so the copy is what the
    /// user falls back to — timestamped, because the pristine original must
    /// survive a second install.
    private static func backupSettings() throws {
        let url = settingsFile
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("settings.json.notchwatch-\(formatter.string(from: Date())).bak")
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        try FileManager.default.copyItem(at: url, to: backup)
    }
}
