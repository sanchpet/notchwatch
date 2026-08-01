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
    static func declaresLongWindow(projectDirectory: String?, configRoot: URL?) -> Bool {
        for url in settingsFiles(projectDirectory: projectDirectory, configRoot: configRoot) {
            guard let model = model(in: url) else { continue }
            return ClaudeContextWindow.declaresLongWindow(model)
        }
        return false
    }

    private static func settingsFiles(projectDirectory: String?, configRoot: URL?) -> [URL] {
        var files: [URL] = []
        if let projectDirectory, !projectDirectory.isEmpty {
            let project = URL(fileURLWithPath: projectDirectory).appendingPathComponent(".claude")
            files.append(project.appendingPathComponent("settings.local.json"))
            files.append(project.appendingPathComponent("settings.json"))
        }
        // The session's own configuration root, not `~/.claude`. A session run
        // under CLAUDE_CONFIG_DIR keeps its pin beside its transcripts, so
        // reading the default root asks the wrong file: the answer comes back
        // "no long-context opt-in" for every session of every other profile, and
        // the bar measures a 1M window against 200k until the session happens to
        // send a prompt too large for the smaller one to have held.
        if let configRoot {
            files.append(configRoot.appendingPathComponent("settings.local.json"))
            files.append(configRoot.appendingPathComponent("settings.json"))
        }
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
