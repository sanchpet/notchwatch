import Foundation
import SwiftUI

@MainActor
public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    @AppStorage("recentToolCallsLimit") public var recentToolCallsLimit: Int = 10
    @AppStorage("showMenuBarItem") public var showMenuBarItem: Bool = false
    @AppStorage("showNotchTokenCount") public var showNotchTokenCount: Bool = true
    @AppStorage("showNotchTokenBreakdown") public var showNotchTokenBreakdown: Bool = true

    // Battery saver: 15 FPS on battery, 25 FPS when charging
    @AppStorage("batterySaverEnabled") public var batterySaverEnabled: Bool = true

    // Claude Code JSONL Session Tracking
    @AppStorage("enableClaudeCodeJSONL") public var enableClaudeCodeJSONL: Bool = true
    /// Whether the app listens for relayed hook events. Off by default: without
    /// hooks registered in ~/.claude/settings.json there is nothing to listen to,
    /// and registering them is a separate, explicit action.
    @AppStorage("enableHookBridge") public var enableHookBridge: Bool = false
    @AppStorage("showSessionDots") public var showSessionDots: Bool = true
    @AppStorage("showPermissionIndicator") public var showPermissionIndicator: Bool = true
    @AppStorage("showTodoList") public var showTodoList: Bool = true
    @AppStorage("showThinkingState") public var showThinkingState: Bool = true

    // Context and Display Settings
    /// Manual override for the context-bar denominator, in tokens; 0 means derive
    /// it from the session's model. Deliberately a new key: the retired
    /// `contextTokenLimit` defaulted to 200k, and reusing it would turn every
    /// existing install's stale default into a permanent override of the
    /// auto-detected window.
    @AppStorage("contextTokenLimitOverride") public var contextTokenLimitOverride: Int = 0
    @AppStorage("showContextProgress") public var showContextProgress: Bool = true
    /// How long a peek notice stays on screen, in seconds.
    ///
    /// Taste, not correctness: the notice is a courtesy, and the state it
    /// announces outlives it either way — the waiting glow holds until the
    /// session is answered. So this can be short for someone who only wants the
    /// nudge, or long for someone who wants to read the line without hurrying.
    @AppStorage("noticeDurationSeconds") public var noticeDurationSeconds: Double = 9

    /// What to show beneath the current-activity line: "off" for nothing,
    /// "singular" for one detailed event, "list" for the recent-events list.
    ///
    /// Defaults to "singular". The list answers "what has it done", which stops
    /// being a question once the agent is trusted; the line above the list
    /// answers "is it alive", which never does.
    @AppStorage("toolDisplayMode") public var toolDisplayMode: String = "singular"

    /// Denominator the context bar measures against: the manual override when the
    /// user set one, otherwise the window resolved from the session's model, its
    /// 1M opt-in, and the largest prompt it has already sent.
    /// Internal rather than `public`: `ClaudeCodeState` is, and the app is one
    /// module, so the access level is bookkeeping either way.
    func effectiveContextLimit(for state: ClaudeCodeState) -> Int {
        guard contextTokenLimitOverride <= 0 else { return contextTokenLimitOverride }
        return ClaudeContextWindow.resolve(
            model: state.model,
            longWindowOptIn: state.declaresLongContextWindow,
            observedPromptTokens: state.observedPeakPromptTokens
        )
    }

    public init() {}
}
