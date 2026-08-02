//
//  ClaudeTokenUsage.swift
//  NotchwatchKit
//
//  What one API request put in the context window.
//

import Foundation

/// Token usage from the `message.usage` object of a transcript entry.
///
/// Every field describes one API request, not a running session total — the API
/// reports usage per request and Claude Code records each one verbatim.
public struct ClaudeTokenUsage: Equatable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadInputTokens: Int
    public var cacheCreationInputTokens: Int

    public init(
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheReadInputTokens: Int = 0,
        cacheCreationInputTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
    }

    /// Read a `message.usage` object as written by Claude Code.
    ///
    /// Every key is optional on purpose: a `<synthetic>` entry omits most of them
    /// and a future field must not stop the rest from being read.
    public init(transcriptUsage: [String: Any]) {
        self.init(
            inputTokens: transcriptUsage["input_tokens"] as? Int ?? 0,
            outputTokens: transcriptUsage["output_tokens"] as? Int ?? 0,
            cacheReadInputTokens: transcriptUsage["cache_read_input_tokens"] as? Int ?? 0,
            cacheCreationInputTokens: transcriptUsage["cache_creation_input_tokens"] as? Int ?? 0
        )
    }

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
    public var promptTokens: Int {
        inputTokens + cacheReadInputTokens + cacheCreationInputTokens
    }

    /// Share of `window` the prompt occupies, clamped to 0…1.
    public func contextFraction(window: Int) -> Double {
        guard window > 0 else { return 0 }
        return min(1.0, Double(promptTokens) / Double(window))
    }
}

// A price readout used to live beside this type: it multiplied the *last*
// request's four token counts by an opus-or-sonnet guess and was labelled the
// session's cost. Both halves were wrong — the price of one request is not the
// price of a session, and `model.contains("opus")` silently charged
// `claude-fable-5` (present in the reference corpus) at Sonnet rates. An honest
// figure has to accumulate over every request of the session, which this app
// cannot do: it attaches to a transcript at a 2 MB tail
// (`TranscriptTail.historyWindowBytes`) and never sees what came before. Rather
// than keep a number that reads like a bill and is not one, there is none.
