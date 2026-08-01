//
//  WorkflowProgress.swift
//  Notchwatch
//
//  How far along a fan-out of subagents is.
//

import Foundation

/// Agents finished against agents started, for the workflow a session is running.
///
/// A workflow spawns many subagents and the main transcript says nothing about
/// their progress — it records the one `Workflow` tool call and then goes quiet
/// for as long as the run takes, which on a real fan-out is over an hour. The
/// only place the progress exists is the run's own journal.
///
/// This is the fragile half of the panel and is written to fail small. The
/// journal is internal Claude Code structure with no compatibility promise —
/// the same class of thing whose drift left upstream's tool list permanently
/// empty. When the shape changes, `read` returns nil, one row disappears, and
/// nothing else in the app notices.
struct WorkflowProgress: Equatable {
    let runID: String
    let started: Int
    let finished: Int

    var fraction: Double {
        started > 0 ? Double(finished) / Double(started) : 0
    }

    /// A run counts as live while its journal is still being written to. Started
    /// minus finished is not enough on its own: an agent that dies returns no
    /// result line, so a crashed fan-out would otherwise show as forever busy.
    private static let liveWindow: TimeInterval = 180

    /// Progress of the most recently active workflow run of `transcript`'s
    /// session, or nil when none is running.
    ///
    /// Runs live in a directory named for the session, beside the transcript:
    /// `<project>/<session-id>/subagents/workflows/wf_*/journal.jsonl`.
    static func read(forTranscript transcript: URL) -> WorkflowProgress? {
        let fm = FileManager.default
        let sessionID = transcript.deletingPathExtension().lastPathComponent
        let runsDir = transcript
            .deletingLastPathComponent()
            .appendingPathComponent(sessionID)
            .appendingPathComponent("subagents/workflows")

        guard let runs = try? fm.contentsOfDirectory(
            at: runsDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }

        let cutoff = Date().addingTimeInterval(-liveWindow)
        var newest: (date: Date, url: URL)?

        for run in runs where run.lastPathComponent.hasPrefix("wf_") {
            let journal = run.appendingPathComponent("journal.jsonl")
            guard let modified = (try? journal.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate, modified > cutoff else { continue }
            if modified > (newest?.date ?? .distantPast) {
                newest = (modified, journal)
            }
        }

        guard let journal = newest?.url,
              let contents = try? String(contentsOf: journal, encoding: .utf8) else { return nil }

        var started = 0
        var finished = 0
        for line in contents.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = json["type"] as? String else { continue }
            switch type {
            case "started": started += 1
            case "result": finished += 1
            default: break
            }
        }

        guard started > 0, finished < started else { return nil }
        return WorkflowProgress(
            runID: journal.deletingLastPathComponent().lastPathComponent,
            started: started,
            finished: finished
        )
    }
}
