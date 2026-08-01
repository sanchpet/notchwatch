//
//  TurnBoundaryTests.swift
//  NotchwatchKitTests
//
//  swift-testing rather than XCTest: XCTest ships with Xcode.app, and this
//  project is built with the Command Line Tools, so a test that imports it
//  cannot run on the machine that develops the app.
//

@testable import NotchwatchKit
import Testing

@Suite("Turn boundaries")
struct TurnBoundaryTests {
    /// The regression this type exists for.
    ///
    /// The assistant message that ends a turn carries both `role: assistant` and
    /// `stop_reason: end_turn`. Handling the role after the reason — and clearing
    /// the reason in that branch — erased the completed turn one line after
    /// recording it, so a session could never be seen to finish.
    @Test("end_turn survives the assistant role")
    func endTurnSurvivesTheAssistantRole() {
        let state = TurnBoundary.apply(
            role: "assistant",
            stopReason: "end_turn",
            to: TurnBoundary.State(isThinking: true, lastStopReason: "tool_use")
        )

        #expect(state.lastStopReason == "end_turn")
        #expect(state.isThinking == false)
        #expect(state.isAwaitingUser)
    }

    @Test("tool_use keeps the turn open")
    func toolUseKeepsTheTurnOpen() {
        let state = TurnBoundary.apply(role: "assistant", stopReason: "tool_use", to: .init())

        #expect(state.isThinking)
        #expect(state.isAwaitingUser == false)
    }

    @Test("a user message opens a new turn")
    func userMessageOpensANewTurn() {
        let finished = TurnBoundary.State(isThinking: false, lastStopReason: "end_turn")
        let state = TurnBoundary.apply(role: "user", stopReason: nil, to: finished)

        #expect(state.isThinking)
        #expect(state.lastStopReason == nil)
        #expect(state.isAwaitingUser == false)
    }

    /// A system entry — a compaction boundary, a summary — is not a turn.
    @Test("unrelated roles do not move the turn")
    func unrelatedRolesDoNotMoveTheTurn() {
        let working = TurnBoundary.State(isThinking: true, lastStopReason: "tool_use")
        let state = TurnBoundary.apply(role: "system", stopReason: nil, to: working)

        #expect(state == working)
    }

    /// The shape a real exchange has: a prompt, tool calls, then the hand-back.
    /// Only the last entry may leave the session awaiting the user.
    @Test("only the final entry of an exchange awaits the user")
    func aWholeExchange() {
        let entries: [(role: String?, stop: String?)] = [
            ("user", nil),
            ("assistant", "tool_use"),
            ("user", nil), // tool_result is recorded under the user role
            ("assistant", "tool_use"),
            ("user", nil),
            ("assistant", "end_turn"),
        ]

        var state = TurnBoundary.State()
        var awaitingAt: [Int] = []
        for (index, entry) in entries.enumerated() {
            state = TurnBoundary.apply(role: entry.role, stopReason: entry.stop, to: state)
            if state.isAwaitingUser {
                awaitingAt.append(index)
            }
        }

        #expect(awaitingAt == [entries.count - 1])
    }

    /// A turn that ended and then resumed must stop awaiting the user, or the
    /// notch would keep signalling after the agent picked the work back up.
    @Test("resuming clears the signal")
    func resumingClearsTheSignal() {
        var state = TurnBoundary.apply(role: "assistant", stopReason: "end_turn", to: .init())
        #expect(state.isAwaitingUser)

        state = TurnBoundary.apply(role: "user", stopReason: nil, to: state)
        #expect(state.isAwaitingUser == false)
    }
}
