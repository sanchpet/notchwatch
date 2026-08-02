//
//  ClaudeContextTrackerTests.swift
//  NotchwatchKitTests
//
//  Which usage entry counts as the reading. The shapes tested here are the ones
//  the reference corpus actually contains — repeated lines, all-zero synthetics,
//  an entry appended again thousands of lines later, and compaction.
//
//  `apply` is mutating, and the `#expect` macro rewrites a call inside it into a
//  closure over an immutable copy — so every verdict is taken into a local first
//  and the expectation is stated about that value.
//

import Foundation
@testable import NotchwatchKit
import Testing

@Suite("Context reading")
struct ClaudeContextTrackerTests {
    private static func usage(_ prompt: Int) -> ClaudeTokenUsage {
        // Split the way a cached conversation is, so nothing under test can pass
        // by reading a single field.
        guard prompt >= 1000 else {
            return ClaudeTokenUsage(inputTokens: prompt, outputTokens: 400)
        }
        return ClaudeTokenUsage(
            inputTokens: 12,
            outputTokens: 400,
            cacheReadInputTokens: prompt - 12 - prompt / 100,
            cacheCreationInputTokens: prompt / 100
        )
    }

    /// The reading is the newest accepted request, not an accumulation. The bar
    /// once showed the session's running token turnover, which climbs past any
    /// window and never comes down.
    @Test("the reading is the last accepted entry")
    func readingIsTheLastAcceptedEntry() {
        var tracker = ClaudeContextTracker()
        var verdicts: [Bool] = []
        for (index, prompt) in [40000, 120_000, 260_000].enumerated() {
            verdicts.append(tracker.apply(Self.usage(prompt), messageID: "msg_\(index)"))
        }

        #expect(verdicts == [true, true, true])
        #expect(tracker.usage.promptTokens == 260_000)
        #expect(tracker.peakPromptTokens == 260_000)
    }

    /// Claude Code writes one line per content block of an assistant message and
    /// repeats the whole `usage` object on each — 15,378 of 26,750 usage-bearing
    /// lines in the corpus are such repeats. They are the same request and must
    /// not be counted twice, whatever the bar would do with them.
    @Test("repeated lines of one message are one reading")
    func repeatedLinesAreOneReading() {
        var tracker = ClaudeContextTracker()
        let first = tracker.apply(Self.usage(180_000), messageID: "msg_a")
        let second = tracker.apply(Self.usage(180_000), messageID: "msg_a")
        let third = tracker.apply(Self.usage(180_000), messageID: "msg_a")

        #expect(first)
        #expect(second == false)
        #expect(third == false)
        #expect(tracker.usage.promptTokens == 180_000)
        #expect(tracker.peakPromptTokens == 180_000)
    }

    /// `<synthetic>` entries — locally generated errors and interrupts — carry an
    /// all-zero usage block. The manager filters them by model, but the tracker
    /// must not depend on that: a zero reading on a loaded session would empty the
    /// bar of a session that is nearly full.
    @Test("an all-zero entry does not empty the reading")
    func allZeroEntryDoesNotEmptyTheReading() {
        var tracker = ClaudeContextTracker()
        let loaded = tracker.apply(Self.usage(310_000), messageID: "msg_a")
        let synthetic = tracker.apply(ClaudeTokenUsage(), messageID: "msg_synthetic")
        let emptyObject = tracker.apply(ClaudeTokenUsage(transcriptUsage: [:]), messageID: nil)

        #expect(loaded)
        #expect(synthetic == false)
        #expect(emptyObject == false)
        #expect(tracker.usage.promptTokens == 310_000)
    }

    /// Three entries in the corpus are an older line appended again verbatim
    /// thousands of lines later. The id no longer matches the previous one, so
    /// only monotonicity catches them.
    @Test("an old entry appended again later is not a new reading")
    func oldEntryAppendedAgainIsNotANewReading() {
        var tracker = ClaudeContextTracker()
        tracker.apply(Self.usage(96000), messageID: "msg_old")
        for index in 0 ..< 5 {
            tracker.apply(Self.usage(120_000 + index * 20000), messageID: "msg_\(index)")
        }
        let peak = tracker.usage.promptTokens

        let replayed = tracker.apply(Self.usage(96000), messageID: "msg_old")

        #expect(peak == 200_000)
        #expect(replayed == false)
        #expect(tracker.usage.promptTokens == peak)
        #expect(tracker.peakPromptTokens == peak)
    }

    /// Nothing but a compaction boundary may lower the reading. Every other drop
    /// in the corpus is an artefact of how the file is written, and honouring
    /// them makes the bar flap on entries that describe the same request.
    @Test("without a boundary the reading never falls", arguments: [0, 1, 100_000, 228_795, 481_999])
    func withoutABoundaryTheReadingNeverFalls(smaller: Int) {
        var tracker = ClaudeContextTracker()
        tracker.apply(Self.usage(482_112), messageID: "msg_a")

        let dropped = tracker.apply(Self.usage(smaller), messageID: "msg_b")

        #expect(dropped == false)
        #expect(tracker.usage.promptTokens == 482_112)
    }

    /// Compaction replaces the conversation with a summary, so the request after
    /// it legitimately reports a far smaller prompt. It is the one licensed drop.
    @Test("a compaction boundary licenses one drop")
    func compactionBoundaryLicensesOneDrop() {
        var tracker = ClaudeContextTracker()
        tracker.apply(Self.usage(640_000), messageID: "msg_a")

        tracker.noteCompactBoundary()
        let compacted = tracker.apply(Self.usage(90000), messageID: "msg_b")
        let readingAfterBoundary = tracker.usage.promptTokens

        // Spent: the next drop has no boundary behind it.
        let unlicensed = tracker.apply(Self.usage(70000), messageID: "msg_c")

        #expect(compacted)
        #expect(readingAfterBoundary == 90000)
        #expect(unlicensed == false)
        #expect(tracker.usage.promptTokens == 90000)
    }

    /// The peak is evidence about the *window*, not about occupancy: a prompt
    /// that was accepted proves the window held it, and that stays true after the
    /// context is compacted away. Losing it at a boundary would drop a session
    /// back to a 200k denominator mid-conversation.
    @Test("the peak survives compaction")
    func peakSurvivesCompaction() {
        var tracker = ClaudeContextTracker()
        tracker.apply(Self.usage(620_000), messageID: "msg_a")
        tracker.noteCompactBoundary()
        tracker.apply(Self.usage(90000), messageID: "msg_b")

        #expect(tracker.usage.promptTokens == 90000)
        #expect(tracker.peakPromptTokens == 620_000)
        #expect(tracker.window(model: "claude-opus-5") == ClaudeContextWindow.extended)
    }

    /// A repeat arriving between the boundary and the compacted request must not
    /// consume the licence — repeats are how the file is written, and the drop
    /// they precede is still legitimate.
    @Test("a repeated line does not spend the boundary")
    func repeatedLineDoesNotSpendTheBoundary() {
        var tracker = ClaudeContextTracker()
        tracker.apply(Self.usage(400_000), messageID: "msg_a")
        tracker.noteCompactBoundary()

        let repeated = tracker.apply(Self.usage(400_000), messageID: "msg_a")
        let compacted = tracker.apply(Self.usage(50000), messageID: "msg_b")

        #expect(repeated == false)
        #expect(compacted)
        #expect(tracker.usage.promptTokens == 50000)
    }

    /// Entries without an `id` cannot be deduplicated, so monotonicity is all
    /// that guards them — a repeat of the same figure is accepted and changes
    /// nothing, while a decrease is still refused.
    @Test("entries without an id are guarded by monotonicity alone")
    func entriesWithoutAnIDAreGuardedByMonotonicity() {
        var tracker = ClaudeContextTracker()
        let first = tracker.apply(Self.usage(150_000), messageID: nil)
        let same = tracker.apply(Self.usage(150_000), messageID: nil)
        let smaller = tracker.apply(Self.usage(149_000), messageID: nil)

        #expect(first)
        #expect(same)
        #expect(smaller == false)
        #expect(tracker.usage.promptTokens == 150_000)
    }

    /// The opt-in reaches the tracker from three places and must stick once seen:
    /// the pin is read once, at the entry that first reveals the session's cwd,
    /// and `resolvedModel` only appears when a subagent happens to run.
    @Test("an opt-in seen once holds for the session")
    func optInHoldsForTheSession() {
        var tracker = ClaudeContextTracker()
        tracker.noteModelID("claude-opus-5")
        #expect(tracker.declaresLongWindow == false)
        #expect(tracker.window(model: "claude-opus-5") == ClaudeContextWindow.standard)

        tracker.noteModelID("claude-opus-5[1m]")
        #expect(tracker.declaresLongWindow)

        // Every later entry names the bare id — the flag must not be cleared.
        tracker.noteModelID("claude-opus-5")
        tracker.noteModelID("claude-fable-5")
        #expect(tracker.declaresLongWindow)
        #expect(tracker.window(model: "claude-opus-5") == ClaudeContextWindow.extended)
    }

    /// The pin's opt-in is established outside the transcript entirely.
    @Test("the pin's opt-in reaches the window")
    func pinOptInReachesTheWindow() {
        var tracker = ClaudeContextTracker()
        tracker.noteLongWindowOptIn()

        #expect(tracker.window(model: "claude-opus-5") == ClaudeContextWindow.extended)
    }

    /// A fresh tracker must not claim a window it has no evidence for.
    @Test("a session with nothing observed gets the standard window")
    func freshTrackerGetsTheStandardWindow() {
        let tracker = ClaudeContextTracker()

        #expect(tracker.usage == ClaudeTokenUsage())
        #expect(tracker.peakPromptTokens == 0)
        #expect(tracker.window(model: "claude-opus-5") == ClaudeContextWindow.standard)
    }

    /// The whole fold, on the shape a real transcript has: a climb, repeats of
    /// every line, a synthetic interrupt, a compaction, then a fresh climb. The
    /// reading must track the last real request and the window must stay where
    /// the evidence put it.
    @Test("a whole session folds to one reading")
    func aWholeSessionFoldsToOneReading() {
        var tracker = ClaudeContextTracker()

        for (index, prompt) in [64000, 210_000, 455_000].enumerated() {
            let id = "msg_\(index)"
            tracker.apply(Self.usage(prompt), messageID: id)
            tracker.apply(Self.usage(prompt), messageID: id) // second content block
            tracker.apply(Self.usage(prompt), messageID: id) // third
        }
        tracker.apply(ClaudeTokenUsage(), messageID: "msg_synthetic")

        #expect(tracker.usage.promptTokens == 455_000)
        #expect(tracker.window(model: "claude-opus-5") == ClaudeContextWindow.extended)

        tracker.noteCompactBoundary()
        for (index, prompt) in [88000, 132_000].enumerated() {
            tracker.apply(Self.usage(prompt), messageID: "post_\(index)")
        }

        #expect(tracker.usage.promptTokens == 132_000)
        #expect(tracker.peakPromptTokens == 455_000)
        #expect(tracker.window(model: "claude-opus-5") == ClaudeContextWindow.extended)
    }
}
