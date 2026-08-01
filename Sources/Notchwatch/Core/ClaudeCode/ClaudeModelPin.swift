//
//  ClaudeModelPin.swift
//  Notchwatch
//
//  Reads the model Claude Code was pinned to, for the one fact the transcript
//  cannot answer.
//

import Foundation

/// The `model` key of Claude Code's settings files.
///
/// The transcript names the model of every request but never its context window:
/// across 44 local transcripts `message.model` is always a bare id
/// (`claude-opus-4-8`, `claude-opus-5`, `claude-fable-5`), while the 1M-context
/// opt-in lives on the *pin* — `~/.claude/settings.json` → `"model": "opus[1m]"`.
/// That file is the only place the suffix is guaranteed to appear, and it is the
/// same file the hook installer already writes, so reading it adds no new reach.
///
/// The answer is a single boolean on purpose. A pin is an alias, not an id
/// (`opus`, `sonnet[1m]`), so it cannot resolve a window on its own; all it
/// settles is whether the long window was asked for.
enum ClaudeModelPin {
    /// Whether the effective model pin for `projectDirectory` opts in to the 1M
    /// context window.
    ///
    /// Settings layer, most specific first, and the first file that defines
    /// `model` decides — a project pin without the suffix has to be able to
    /// override a user pin that has one.
    static func declaresLongWindow(projectDirectory: String?) -> Bool {
        for url in settingsFiles(projectDirectory: projectDirectory) {
            guard let model = model(in: url) else { continue }
            return ClaudeContextWindow.declaresLongWindow(model)
        }
        return false
    }

    private static func settingsFiles(projectDirectory: String?) -> [URL] {
        var files: [URL] = []
        if let projectDirectory, !projectDirectory.isEmpty {
            let project = URL(fileURLWithPath: projectDirectory).appendingPathComponent(".claude")
            files.append(project.appendingPathComponent("settings.local.json"))
            files.append(project.appendingPathComponent("settings.json"))
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
        files.append(home.appendingPathComponent("settings.local.json"))
        files.append(home.appendingPathComponent("settings.json"))
        return files
    }

    private static func model(in url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = json["model"] as? String,
              !model.isEmpty else { return nil }
        return model
    }
}
