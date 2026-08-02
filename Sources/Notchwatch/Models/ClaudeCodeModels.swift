//
//  ClaudeCodeModels.swift
//  Notchwatch
//
//  Created for Claude Code JSONL integration
//

import Foundation
import NotchwatchKit

// MARK: - Session Discovery

/// Represents an active Claude Code IDE session from ~/.claude/ide/*.lock
struct ClaudeSession: Identifiable, Codable, Equatable {
    /// Marks a session whose host application is not knowable. A transcript
    /// records no parent process, so nothing connects it to the terminal or
    /// editor it runs in; only an editor lock claims a host, and only when the
    /// project holds a single session can that claim be trusted — the rule, and
    /// this constant, live in `EditorLock`.
    static let unknownHost = EditorLock.unknownHost

    var id: String {
        "\(ideName):\(workspaceFolders.first ?? "\(pid)")"
    }

    let pid: Int
    let workspaceFolders: [String]
    let ideName: String
    let transport: String?
    let runningInWindows: Bool?

    /// Where this session runs and which of the project's sessions it is. The
    /// parsing is the kit's — see `WorkspaceRef`.
    var workspace: WorkspaceRef? {
        workspaceFolders.first.map { WorkspaceRef($0) }
    }

    /// Name of the directory holding this project's transcripts.
    var projectKey: String? {
        workspace?.projectKey
    }

    /// Display name for UI (last folder component)
    var displayName: String {
        guard let name = workspace?.displayName, !name.isEmpty else { return "Unknown" }
        return name
    }

    /// Transcript id from the workspace fragment (nil for a bare editor lock)
    var terminalSessionId: String? {
        workspace?.sessionID
    }
}

// MARK: - Tool Execution

/// Represents a tool call in progress or completed
struct ClaudeToolExecution: Identifiable, Equatable {
    let id: String
    let toolName: String
    let argument: String?
    let startTime: Date
    var endTime: Date?
    var isRunning: Bool {
        endTime == nil
    }

    // New fields from JSONL
    var description: String?
    var timeout: Int?
    var inputTokens: Int?
    var outputTokens: Int?
    var cacheReadTokens: Int?
    var cacheWriteTokens: Int?

    var durationMs: Int? {
        guard let end = endTime else { return nil }
        return Int(end.timeIntervalSince(startTime) * 1000)
    }

    var formattedDuration: String {
        guard let ms = durationMs else {
            let elapsed = Int(Date().timeIntervalSince(startTime) * 1000)
            return formatMs(elapsed)
        }
        return formatMs(ms)
    }

    private func formatMs(_ ms: Int) -> String {
        if ms < 1000 {
            return "\(ms)ms"
        } else if ms < 60000 {
            return String(format: "%.1fs", Double(ms) / 1000.0)
        } else {
            let seconds = ms / 1000
            let minutes = seconds / 60
            let remainingSeconds = seconds % 60
            return "\(minutes)m \(remainingSeconds)s"
        }
    }
}

// MARK: - Todo Item

/// Claude Code todo item from TodoWrite tool
struct ClaudeTodoItem: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let status: TodoStatus

    enum TodoStatus: String {
        case pending
        case inProgress = "in_progress"
        case completed
    }
}

// MARK: - Complete State

/// Complete Claude Code state for display
struct ClaudeCodeState: Equatable {
    var sessionId: String = ""
    var model: String = ""
    var cwd: String = ""
    var gitBranch: String = ""

    /// Usage of the newest API request on this session's main chain — one
    /// request, deduplicated and guarded, never a running total.
    var tokenUsage: ClaudeTokenUsage = .init()

    /// Largest prompt this session has been observed to send, across compactions.
    ///
    /// Evidence about the *window*, not about occupancy: a prompt that was
    /// accepted proves the window is at least that large. Survives compaction for
    /// exactly that reason — the window does not shrink when the context does.
    var observedPeakPromptTokens: Int = 0

    /// True once a 1M-context opt-in has been seen for this session, from the
    /// model pin, a `Task` result's `resolvedModel`, or the model id itself.
    var declaresLongContextWindow: Bool = false

    var lastMessage: String = ""
    var lastMessageTime: Date?

    var activeTools: [ClaudeToolExecution] = []
    var recentTools: [ClaudeToolExecution] = []

    var todos: [ClaudeTodoItem] = []

    var isConnected: Bool = false
    var lastUpdateTime: Date?

    /// True when Claude is waiting for user permission to execute a tool
    var needsPermission: Bool = false
    /// The tool waiting for permission (if any)
    var pendingPermissionTool: String?

    /// Opening line of the agent's closing message, for the hand-back notice.
    ///
    /// "The turn is yours" is more use with a sentence of what was just done
    /// than without one, and the transcript already carries it: the assistant's
    /// last text block is that report. Only the first line is kept — a notice
    /// that has to be read rather than glanced at defeats itself.
    var lastAssistantSummary: String?

    /// True when Claude is actively generating a response (thinking)
    var isThinking: Bool = false

    /// Last stop_reason from Claude (e.g., "end_turn", "tool_use")
    var lastStopReason: String?

    /// True when the session completed its last response (stop_reason = end_turn and not active)
    var isSessionComplete: Bool {
        lastStopReason == "end_turn" && !isThinking && activeTools.isEmpty
    }

    // Convenience accessors
    var hasActiveTools: Bool {
        !activeTools.isEmpty
    }

    var currentToolName: String? {
        activeTools.first?.toolName
    }

    /// True when the session is actively processing (thinking or running tools)
    var isActive: Bool {
        isThinking || hasActiveTools
    }
}

// MARK: - Daily Stats (from stats-cache.json)

/// Daily activity stats from ~/.claude/stats-cache.json
struct ClaudeDailyStats: Equatable {
    var messageCount: Int = 0
    var toolCallCount: Int = 0
    var sessionCount: Int = 0
    var tokensUsed: Int = 0
    var date: String = ""

    var isEmpty: Bool {
        date.isEmpty
    }
}

/// Stats cache structure matching ~/.claude/stats-cache.json
struct ClaudeStatsCache: Codable {
    let dailyActivity: [DailyActivity]?
    let dailyModelTokens: [DailyModelTokens]?
    let modelUsage: [String: ModelUsageStats]?
    let totalSessions: Int?
    let totalMessages: Int?

    struct DailyActivity: Codable {
        let date: String
        let messageCount: Int?
        let sessionCount: Int?
        let toolCallCount: Int?
    }

    struct DailyModelTokens: Codable {
        let date: String
        let tokensByModel: [String: Int]?
    }

    struct ModelUsageStats: Codable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cacheReadInputTokens: Int?
        let cacheCreationInputTokens: Int?
    }
}
