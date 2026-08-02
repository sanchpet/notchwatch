//
//  HookInstaller.swift
//  Notchwatch
//
//  Registers (and unregisters) the relay in the user's Claude Code settings.
//

import Foundation
import NotchwatchKit

/// Adds or removes this app's hook entries in every Claude Code settings file.
///
/// **Every** file, not `~/.claude/settings.json`. Claude Code reads its user
/// settings from the configuration root it is running under, so on a machine
/// where `CLAUDE_CONFIG_DIR` points at `~/.claude-personal` — the documented way
/// to keep profiles apart, and the app already watches all of them for sessions —
/// hooks written to the default root are read by nobody. The failure is silent
/// and total: the settings pane says registered, the file says registered, and
/// not one event is ever raised.
///
/// The file is the user's, not ours. Nothing here runs on launch or on a settings
/// toggle: every call sits behind an explicit action, the previous contents are
/// copied aside first, and `uninstall` removes exactly what `install` added.
/// Unknown keys survive because the file is read as a dictionary and written back
/// whole; what the edit itself amounts to is `HookSettings`, in the kit.
@MainActor
enum HookInstaller {
    enum InstallError: LocalizedError {
        case settingsUnreadable(URL)
        case settingsNotAnObject(URL)
        case noSettingsFile
        case partial([(URL, Error)])

        var errorDescription: String? {
            switch self {
            case let .settingsUnreadable(url):
                "Could not read \(url.path)."
            case let .settingsNotAnObject(url):
                "\(url.path) is not a JSON object; refusing to rewrite it."
            case .noSettingsFile:
                "No Claude Code configuration directory was found in your home folder."
            case let .partial(failures):
                failures
                    .map { "\(Self.display($0.0)): \($0.1.localizedDescription)" }
                    .joined(separator: "\n")
            }
        }

        private static func display(_ url: URL) -> String {
            (url.path as NSString).abbreviatingWithTildeInPath
        }
    }

    static let subscribedEvents = HookSettings.subscribedEvents

    /// One settings file per configuration root the app watches.
    ///
    /// Falls back to the default root when none is found, so a first run with no
    /// Claude Code history still has somewhere to register.
    static var settingsFiles: [URL] {
        let roots = ClaudeRoots.all
        guard !roots.isEmpty else {
            return [ClaudeRoots.home.appendingPathComponent(".claude/settings.json")]
        }
        return roots.map { $0.appendingPathComponent("settings.json") }
    }

    /// The files as the user would name them, for the confirmation dialog. A
    /// prompt that says `~/.claude/settings.json` while writing three files is
    /// not the consent it claims to be.
    static var settingsFileDescription: String {
        settingsFiles
            .map { ($0.path as NSString).abbreviatingWithTildeInPath }
            .joined(separator: ", ")
    }

    /// The command Claude Code will run. Quoted: the bundle lives under a path
    /// with a space in it more often than not.
    static var relayCommand: String {
        let executable = Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? "notchwatch"
        return "\"\(executable)\" \(HookRelay.flag)"
    }

    /// True only when every file carries every entry: a root registered while
    /// another is not is not registered, and the sessions of the unregistered one
    /// would go on being read from the transcript alone with nothing to say so.
    static var isInstalled: Bool {
        let files = settingsFiles
        guard !files.isEmpty else { return false }
        return files.allSatisfy { file in
            guard let settings = try? readSettings(at: file) else { return false }
            return HookSettings.isInstalled(in: settings)
        }
    }

    // MARK: - Mutation

    static func install() throws {
        try each { file in
            let settings = try readSettings(at: file)
            try writeSettings(HookSettings.adding(command: relayCommand, to: settings), to: file)
        }
    }

    static func uninstall() throws {
        try each { file in
            let settings = try readSettings(at: file)
            guard settings["hooks"] != nil else { return }
            try writeSettings(HookSettings.removing(from: settings), to: file)
        }
    }

    /// Apply to every file, and report what failed rather than stopping at the
    /// first one: a root that cannot be written must not leave the others
    /// untouched, and the user has to be told which.
    private static func each(_ body: (URL) throws -> Void) throws {
        let files = settingsFiles
        guard !files.isEmpty else { throw InstallError.noSettingsFile }

        var failures: [(URL, Error)] = []
        for file in files {
            do {
                try body(file)
            } catch {
                failures.append((file, error))
            }
        }
        guard failures.isEmpty else { throw InstallError.partial(failures) }
    }

    // MARK: - File access

    private static func readSettings(at url: URL) throws -> [String: Any] {
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

    private static func writeSettings(_ settings: [String: Any], to url: URL) throws {
        try backupSettings(at: url)
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
    private static func backupSettings(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("settings.json.notchwatch-\(formatter.string(from: Date())).bak")
        guard !FileManager.default.fileExists(atPath: backup.path) else { return }
        try FileManager.default.copyItem(at: url, to: backup)
    }
}
