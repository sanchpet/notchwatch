//
//  ClaudeContextTracker.swift
//  NotchwatchKit
//
//  Folds a transcript's usage entries into one honest context reading.
//

import Foundation

/// How much of the context window a session is using, folded from the transcript.
///
/// The raw sequence of `usage` blocks in a transcript is **not** monotonic. Over
/// 44 local transcripts (26,750 usage-bearing lines, 11,362 distinct requests) it
/// falls by more than 30% at a prompt above 100k on 41 occasions — and every one
/// of those is an artefact of how the file is written rather than a context that
/// actually shrank:
///
/// * **repeated lines.** Claude Code writes one line per content block of an
///   assistant message and repeats the whole `usage` object on each: 15,378 of
///   the 26,750 lines are such repeats. Three more are an entry from thousands of
///   lines earlier appended again verbatim.
/// * **`<synthetic>` entries.** Locally generated errors and interrupts, carrying
///   an all-zero usage block.
/// * **compaction.** A genuine reset, announced by a
///   `{"type":"system","subtype":"compact_boundary"}` entry. All 31 boundaries in
///   the corpus are `trigger: "manual"`; `preTokens` there ranges 116k–970k.
///
/// Skip the repeats by id, drop the synthetics, honour the boundaries, and the
/// sequence is monotonic within every compaction segment: exactly one decrease
/// survives in the whole corpus — a `/login` re-auth after which Claude Code
/// resumed on a trimmed history (482,112 → 228,795 tokens). Holding the older,
/// larger figure there errs high once in 11,362 requests, which is the cheaper
/// error than flapping on every repeat.
///
/// The type is a pure fold on purpose: it is handed entries, never files. The
/// reading it produces was wrong three times over — a running total mistaken for
/// occupancy, then a window handed to every modern model, then a pin read from
/// the wrong profile — and each was a plausible-looking number rather than a
/// visible break, which is exactly the kind of defect a test catches and a glance
/// does not.
public struct ClaudeContextTracker: Equatable {
    /// Usage of the newest accepted request — one request, never a running total.
    public private(set) var usage = ClaudeTokenUsage()

    /// Largest prompt this session has been observed to send, across compactions.
    ///
    /// Evidence about the *window*, not about occupancy: a prompt that was
    /// accepted proves the window is at least that large, and that stays true
    /// after the context is compacted away.
    public private(set) var peakPromptTokens = 0

    /// True once a 1M-context opt-in has been seen, from the model pin, a `Task`
    /// result's `resolvedModel`, or the model id itself.
    public private(set) var declaresLongWindow = false

    private var lastMessageID: String?
    private var isAfterCompaction = false

    public init() {}

    // MARK: - Signals

    /// Record that a compaction boundary was read: the next request is allowed to
    /// report a smaller prompt than the last one.
    public mutating func noteCompactBoundary() {
        isAfterCompaction = true
    }

    /// Record a model string from any source, adopting its 1M opt-in if it has
    /// one. Never clears the flag: an opt-in seen once holds for the session.
    public mutating func noteModelID(_ modelID: String) {
        if ClaudeContextWindow.declaresLongWindow(modelID) {
            noteLongWindowOptIn()
        }
    }

    /// Record an opt-in established outside the transcript — the model pin.
    public mutating func noteLongWindowOptIn() {
        declaresLongWindow = true
    }

    // MARK: - Usage

    /// Offer one request's usage as the session's current reading.
    ///
    /// - Returns: `true` when it was taken.
    @discardableResult
    public mutating func apply(_ candidate: ClaudeTokenUsage, messageID: String?) -> Bool {
        if let messageID, lastMessageID == messageID {
            return false
        }

        guard isAfterCompaction || candidate.promptTokens >= usage.promptTokens else {
            return false
        }

        isAfterCompaction = false
        if let messageID {
            lastMessageID = messageID
        }
        usage = candidate
        peakPromptTokens = max(peakPromptTokens, candidate.promptTokens)
        return true
    }

    /// Window to measure `usage` against, given the session's model.
    public func window(model: String) -> Int {
        ClaudeContextWindow.resolve(
            model: model,
            longWindowOptIn: declaresLongWindow,
            observedPromptTokens: peakPromptTokens
        )
    }
}
