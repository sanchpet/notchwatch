//
//  DemoScenario.swift
//  Notchwatch
//
//  Fabricated sessions, for documentation and for states real work will not pose.
//

import Foundation

/// A made-up set of sessions covering the states worth showing.
///
/// This exists because of what the app is. Every pixel of the panel is a report
/// on the user's own work: project names, branches, the commands being run and
/// the first line of what the agent just said. An honest screenshot is therefore
/// a screenshot of somebody's private activity — the first one attempted here
/// caught a path into a personal vault and a task description from an unrelated
/// session. Documentation cannot be produced safely by pointing a camera at real
/// use.
///
/// It also buys reproducibility. "Four sessions, one nearly out of context, one
/// waiting on you, a workflow half done" is a layout that has to be checked and
/// cannot be arranged on demand — you would have to wait for it to happen.
///
/// Everything here is invented: the paths, the ids, the commands. Names are
/// deliberately generic, so that nothing taken from this ever needs a second look
/// before publishing.
enum DemoScenario {
    /// A tool the fixture describes.
    struct ToolSpec {
        let name: String
        let argument: String
        let secondsAgo: TimeInterval
    }

    /// One fabricated session. A description rather than nine call arguments —
    /// these fields are exactly what the panel reads, so they are worth naming.
    struct SessionSpec {
        let project: String
        let id: String
        let branch: String
        let promptTokens: Int
        /// Puts the session on the 1M window, as a real opt-in would.
        let longWindow: Bool
        let updatedSecondsAgo: TimeInterval
        let isThinking: Bool
        let stopReason: String?
        var activeTool: ToolSpec?
        var recentTools: [ToolSpec] = []
        var summary: String?
    }

    struct Fixture {
        let sessions: [ClaudeSession]
        let states: [String: ClaudeCodeState]
        let workflow: WorkflowProgress?
    }

    private static let model = "claude-opus-5"

    private static let specs: [SessionSpec] = [
        // Busy, with a long command under way — which is what the clock is for.
        SessionSpec(
            project: "checkout-service",
            id: "a1b2c3d4-0000-4000-8000-000000000001",
            branch: "feat/idempotent-retries",
            promptTokens: 412_000,
            longWindow: true,
            updatedSecondsAgo: 2,
            isThinking: false,
            stopReason: "tool_use",
            activeTool: ToolSpec(name: "Bash", argument: "go test ./... -race", secondsAgo: 47),
            recentTools: [
                ToolSpec(name: "Edit", argument: "internal/retry/backoff.go", secondsAgo: 30),
                ToolSpec(name: "Read", argument: "internal/retry/backoff_test.go", secondsAgo: 58),
            ]
        ),
        // Nearly out of context: the bar's warning colours are otherwise only
        // reachable at the end of a long session.
        SessionSpec(
            project: "docs-site",
            id: "c3d4e5f6-0000-4000-8000-000000000003",
            branch: "chore/link-audit",
            promptTokens: 191_000,
            longWindow: false,
            updatedSecondsAgo: 9,
            isThinking: true,
            stopReason: nil
        ),
        // Waiting on the user — the state the notch exists to announce.
        SessionSpec(
            project: "infra",
            id: "b2c3d4e5-0000-4000-8000-000000000002",
            branch: "main",
            promptTokens: 96000,
            longWindow: false,
            updatedSecondsAgo: 40,
            isThinking: false,
            stopReason: "end_turn",
            recentTools: [ToolSpec(name: "Write", argument: "terraform/dns.tf", secondsAgo: 45)],
            summary: "Both records are in place; the plan replaces nothing."
        ),
        // Idle long enough to be worth saying so.
        SessionSpec(
            project: "notchwatch",
            id: "d4e5f607-0000-4000-8000-000000000004",
            branch: "fix/tray-width",
            promptTokens: 58000,
            longWindow: true,
            updatedSecondsAgo: 22 * 60,
            isThinking: false,
            stopReason: "end_turn",
            recentTools: [ToolSpec(name: "Grep", argument: "maxTrayWidth", secondsAgo: 22 * 60)],
            summary: "The tray is content-sized now; the capsule follows the row."
        ),
    ]

    static func make(now: Date = Date()) -> Fixture {
        var sessions: [ClaudeSession] = []
        var states: [String: ClaudeCodeState] = [:]

        for spec in specs {
            let workspace = "/Users/demo/code/\(spec.project)"
            let session = ClaudeSession(
                pid: 0,
                workspaceFolders: ["\(workspace)#\(spec.id)"],
                ideName: "Terminal",
                transport: nil,
                runningInWindows: nil
            )
            sessions.append(session)
            states[session.id] = state(for: spec, workspace: workspace, now: now)
        }

        return Fixture(
            sessions: sessions,
            states: states,
            workflow: WorkflowProgress(runID: "wf_demo", started: 13, finished: 8)
        )
    }

    private static func state(for spec: SessionSpec, workspace: String, now: Date) -> ClaudeCodeState {
        var state = ClaudeCodeState()
        state.sessionId = spec.id
        state.cwd = workspace
        state.gitBranch = spec.branch
        state.model = model
        state.isConnected = true
        state.isThinking = spec.isThinking
        state.lastStopReason = spec.stopReason
        state.lastUpdateTime = now.addingTimeInterval(-spec.updatedSecondsAgo)
        state.lastAssistantSummary = spec.summary
        state.declaresLongContextWindow = spec.longWindow
        state.observedPeakPromptTokens = spec.promptTokens

        // Split across the three input fields the way a cached conversation does,
        // so the footer's cache-read and cache-write badges are populated too.
        let prompt = spec.promptTokens
        state.tokenUsage = ClaudeTokenUsage(
            inputTokens: prompt / 20,
            outputTokens: prompt / 40,
            cacheReadInputTokens: prompt - prompt / 20 - prompt / 10,
            cacheCreationInputTokens: prompt / 10
        )

        if let tool = spec.activeTool {
            state.activeTools = [
                ClaudeToolExecution(
                    id: "\(spec.id)-active",
                    toolName: tool.name,
                    argument: tool.argument,
                    startTime: now.addingTimeInterval(-tool.secondsAgo)
                ),
            ]
        }

        state.recentTools = spec.recentTools.enumerated().map { index, tool in
            var execution = ClaudeToolExecution(
                id: "\(spec.id)-recent-\(index)",
                toolName: tool.name,
                argument: tool.argument,
                startTime: now.addingTimeInterval(-tool.secondsAgo - 2)
            )
            execution.endTime = now.addingTimeInterval(-tool.secondsAgo)
            return execution
        }

        return state
    }
}
