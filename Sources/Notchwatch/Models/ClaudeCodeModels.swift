//
//  ClaudeCodeModels.swift
//  Notchwatch
//
//  Created for Claude Code JSONL integration
//

import Foundation

// MARK: - Session Discovery

/// Represents an active Claude Code IDE session from ~/.claude/ide/*.lock
struct ClaudeSession: Identifiable, Codable, Equatable {
    /// Marks a session whose host application is not knowable. A transcript
    /// records no parent process, so nothing connects it to the terminal or
    /// editor it runs in; only an editor lock claims a host, and only when the
    /// project holds a single session can that claim be trusted.
    static let unknownHost = "Unknown"

    var id: String {
        "\(ideName):\(workspaceFolders.first ?? "\(pid)")"
    }

    let pid: Int
    let workspaceFolders: [String]
    let ideName: String
    let transport: String?
    let runningInWindows: Bool?

    /// Derived from workspace path for project JSONL lookup
    /// Claude Code uses path with "/" replaced by "-" as the project directory name
    var projectKey: String? {
        guard let workspace = workspaceFolders.first else { return nil }
        // Strip session fragment if present (e.g., /path#sessionId -> /path)
        let cleanPath = workspace.components(separatedBy: "#").first ?? workspace
        // Claude Code escapes the path: "/" -> "-", but keeps leading "-" for absolute paths
        // e.g., /Users/foo/project -> -Users-foo-project
        return cleanPath
            .replacingOccurrences(of: "/", with: "-")
    }

    /// Display name for UI (last folder component)
    var displayName: String {
        guard let workspace = workspaceFolders.first else { return "Unknown" }
        // Strip session fragment if present (e.g., /path#sessionId -> /path)
        let cleanPath = workspace.components(separatedBy: "#").first ?? workspace
        return URL(fileURLWithPath: cleanPath).lastPathComponent
    }

    /// Terminal session ID extracted from workspace fragment (nil for IDE sessions)
    var terminalSessionId: String? {
        guard let workspace = workspaceFolders.first else { return nil }
        let parts = workspace.components(separatedBy: "#")
        return parts.count > 1 ? parts[1] : nil
    }
}

// MARK: - Context Window

/// The denominator of the context bar.
///
/// The window is a property of the model plus whether Claude Code was launched
/// with the 1M-context opt-in, and neither fact is written where the obvious
/// place would be. Measured over 44 local transcripts (26,750 assistant entries
/// carrying `usage`), `message.model` is one of `claude-opus-4-8`,
/// `claude-opus-5`, `claude-fable-5` or `<synthetic>` — never once suffixed. The
/// opt-in survives in two other places, and both have to be brought in by the
/// caller:
///
/// * the model *pin* — `~/.claude/settings.json` → `"model": "opus[1m]"`, an
///   alias rather than a full id;
/// * `toolUseResult.resolvedModel` on a `Task` result — present in 9 of the 44
///   transcripts, and only when a subagent actually ran.
///
/// Neither is complete: 8 transcripts with no marker anywhere still reached
/// prompts of 214k–620k, which a 200k window could not have held. So the last
/// word belongs to the session itself — a window can never be smaller than a
/// prompt that demonstrably fit inside it.
enum ClaudeContextWindow {
    /// Window of the models that predate the 1M-token context — and of anything
    /// unrecognised.
    static let standard = 200_000
    static let extended = 1_000_000

    /// Windows this app can name, smallest first. Evidence promotes a session to
    /// the first tier large enough to hold what it has already sent.
    private static let tiers = [standard, extended]

    /// Whether `modelID` carries Claude Code's 1M-context opt-in suffix.
    ///
    /// Applies to the bare aliases a pin uses (`opus[1m]`) as much as to full ids,
    /// so it deliberately tests only the suffix.
    static func declaresLongWindow(_ modelID: String) -> Bool {
        modelID.lowercased().hasSuffix("[1m]")
    }

    /// Window the model id implies on its own.
    ///
    /// A bare id always means the standard window, however recent the model. The
    /// 1M context is an opt-in a session either took or did not — it is not a
    /// property of the model, even where the API offers one. Deriving it from the
    /// id instead would hand 1M to every modern model, leave `longWindowOptIn`
    /// and the evidence floor with nothing to decide, and show a full 200k window
    /// as 19%.
    static func forModel(_ model: String) -> Int {
        declaresLongWindow(model) ? extended : standard
    }

    /// Window to measure against, from the model, any opt-in seen for the
    /// session, and the largest prompt the session has actually sent.
    ///
    /// The evidence floor is what keeps a misread model from pinning the bar at
    /// 100%: a session that has already sent 620k tokens is not running a 200k
    /// window, whatever the id says.
    static func resolve(model: String, longWindowOptIn: Bool, observedPromptTokens: Int) -> Int {
        let declared = longWindowOptIn ? extended : forModel(model)
        guard observedPromptTokens > declared else { return declared }
        return tiers.first { $0 >= observedPromptTokens } ?? observedPromptTokens
    }
}

// MARK: - Token Usage

/// Token usage from the `message.usage` object of a transcript entry.
///
/// Every field describes one API request, not a running session total — the API
/// reports usage per request and Claude Code records each one verbatim.
struct ClaudeTokenUsage: Equatable {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheReadInputTokens: Int = 0
    var cacheCreationInputTokens: Int = 0

    /// How much of the context window the last request actually occupied.
    ///
    /// The three input fields partition one prompt: `cache_read` is the prefix
    /// served from cache, `cache_creation` the part written to cache on this
    /// request, `input` the remainder billed at full price. Only their sum is the
    /// prompt — and only the sum grows monotonically across a session. When a
    /// cache entry expires, a large prefix moves from `cache_read` to
    /// `cache_creation` in a single step, so any subset of the three collapses at
    /// a moment when the real context did not move at all.
    ///
    /// `output` is deliberately excluded: it is not in the window during the
    /// request that produced it, and the next request folds it into that
    /// request's prefix, so counting it here counts it twice.
    var promptTokens: Int {
        inputTokens + cacheReadInputTokens + cacheCreationInputTokens
    }

    /// Share of `window` the prompt occupies, clamped to 0…1.
    func contextFraction(window: Int) -> Double {
        guard window > 0 else { return 0 }
        return min(1.0, Double(promptTokens) / Double(window))
    }
}

// A price readout used to live here: it multiplied the *last* request's four
// token counts by an opus-or-sonnet guess and was labelled the session's cost.
// Both halves were wrong — the price of one request is not the price of a
// session, and `model.contains("opus")` silently charged `claude-fable-5`
// (present in the reference corpus) at Sonnet rates. An honest figure has to
// accumulate over every request of the session, which this app cannot do: it
// attaches to a transcript at a 2 MB tail (`TranscriptTail.historyWindowBytes`)
// and never sees what came before. Rather than keep a number that reads like a
// bill and is not one, there is none.

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
