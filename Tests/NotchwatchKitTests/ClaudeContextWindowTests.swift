//
//  ClaudeContextWindowTests.swift
//  NotchwatchKitTests
//
//  The bar's denominator. Every rule here has shipped wrong at least once, and
//  none of the failures looked like failures: a wrong window is a plausible
//  number in a plausible bar.
//

import Foundation
@testable import NotchwatchKit
import Testing

@Suite("Context window")
struct ClaudeContextWindowTests {
    /// The regression that made the other two rules unreachable.
    ///
    /// The window was once derived from the model id — anything recent got 1M.
    /// That handed every current model the extended window, so the opt-in and the
    /// evidence floor had nothing left to decide, and a full 200k context drew as
    /// 19%. A bare id means the standard window however new the model is.
    @Test(
        "a bare model id means the standard window",
        arguments: ["claude-opus-4-8", "claude-opus-5", "claude-fable-5", "claude-sonnet-4-5", "opus", "sonnet", ""]
    )
    func bareModelIDMeansStandardWindow(model: String) {
        #expect(ClaudeContextWindow.declaresLongWindow(model) == false)
        #expect(ClaudeContextWindow.forModel(model) == ClaudeContextWindow.standard)
        #expect(
            ClaudeContextWindow.resolve(model: model, longWindowOptIn: false, observedPromptTokens: 0)
                == 200_000
        )
    }

    /// The suffix is the whole of the opt-in, and it has to be recognised on the
    /// bare aliases a pin uses (`opus[1m]`) as much as on a full id. Case is not
    /// ours to assume: the string can come from a hand-edited settings file or
    /// from a subagent's `resolvedModel`.
    @Test(
        "the [1m] suffix means the extended window",
        arguments: ["opus[1m]", "claude-opus-5[1m]", "Opus[1M]", "CLAUDE-OPUS-5[1m]"]
    )
    func longWindowSuffixMeansExtendedWindow(model: String) {
        #expect(ClaudeContextWindow.declaresLongWindow(model))
        #expect(ClaudeContextWindow.forModel(model) == ClaudeContextWindow.extended)
        #expect(
            ClaudeContextWindow.resolve(model: model, longWindowOptIn: false, observedPromptTokens: 0)
                == 1_000_000
        )
    }

    /// `[1m]` is a suffix, not a substring: a model whose name merely contains the
    /// marker somewhere is not an opt-in.
    @Test("the marker only counts as a suffix")
    func markerOnlyCountsAsASuffix() {
        #expect(ClaudeContextWindow.declaresLongWindow("claude-opus-5[1m]-preview") == false)
        #expect(ClaudeContextWindow.declaresLongWindow("[1m]claude-opus-5") == false)
    }

    /// The opt-in reaches the resolver from the pin or from a subagent's
    /// `resolvedModel`, never from `message.model` — so it has to be able to
    /// promote a session whose model id says nothing.
    @Test("an opt-in seen elsewhere promotes a bare id")
    func optInPromotesABareID() {
        #expect(
            ClaudeContextWindow.resolve(model: "claude-opus-5", longWindowOptIn: true, observedPromptTokens: 0)
                == 1_000_000
        )
    }

    /// The evidence floor: a prompt that was accepted proves the window held it.
    /// Eight transcripts in the reference corpus carry no opt-in marker anywhere
    /// and still reached 214k–620k, which a 200k window could not have done.
    @Test("a prompt too large for the standard window raises it", arguments: [200_001, 214_000, 620_000, 962_244])
    func evidenceFloorRaisesTheWindow(observed: Int) {
        #expect(
            ClaudeContextWindow.resolve(model: "claude-opus-5", longWindowOptIn: false, observedPromptTokens: observed)
                == 1_000_000
        )
    }

    /// The floor is a floor, not a ratchet: a prompt the declared window could
    /// have held leaves that window alone.
    @Test("a prompt the window could hold leaves it alone", arguments: [0, 1, 199_999, 200_000])
    func evidenceBelowTheWindowChangesNothing(observed: Int) {
        #expect(
            ClaudeContextWindow.resolve(model: "claude-opus-5", longWindowOptIn: false, observedPromptTokens: observed)
                == 200_000
        )
        #expect(
            ClaudeContextWindow.resolve(model: "opus[1m]", longWindowOptIn: false, observedPromptTokens: observed)
                == 1_000_000
        )
    }

    /// Above every tier this app can name, the prompt becomes its own window. The
    /// bar then reads full — which is the honest answer, since there is no larger
    /// window to measure against, but it also means the bar stops moving. Pinned
    /// so the day a larger tier exists, this test is what says where to add it.
    @Test("a prompt above every named tier becomes its own window")
    func aPromptAboveEveryTierBecomesItsOwnWindow() {
        let window = ClaudeContextWindow.resolve(
            model: "claude-opus-5",
            longWindowOptIn: true,
            observedPromptTokens: 1_200_000
        )

        #expect(window == 1_200_000)
        #expect(ClaudeTokenUsage(inputTokens: 1_200_000).contextFraction(window: window) == 1.0)
    }

    /// `promptTokens` sums the three input fields and excludes `output`. The
    /// readout was once the running total of everything the session had ever
    /// spent, which is turnover, not occupancy — it climbed past any window and
    /// never came down.
    @Test("the prompt is the three input fields, not the turnover")
    func promptIsTheThreeInputFields() {
        let usage = ClaudeTokenUsage(
            inputTokens: 12,
            outputTokens: 5000,
            cacheReadInputTokens: 180_000,
            cacheCreationInputTokens: 20000
        )

        #expect(usage.promptTokens == 200_012)
        #expect(usage.contextFraction(window: 200_000) == 1.0)
        #expect(abs(usage.contextFraction(window: 1_000_000) - 0.200012) < 1e-9)
    }

    /// A cache entry expiring moves a large prefix from `cache_read` to
    /// `cache_creation` in one step. Only the sum survives that; any subset
    /// collapses at a moment when the real context did not move.
    @Test("moving the prefix between cache fields does not move the prompt")
    func cacheFieldsPartitionOnePrompt() {
        let cached = ClaudeTokenUsage(inputTokens: 12, cacheReadInputTokens: 190_000, cacheCreationInputTokens: 10000)
        let rewritten = ClaudeTokenUsage(inputTokens: 12, cacheReadInputTokens: 0, cacheCreationInputTokens: 200_000)

        #expect(cached.promptTokens == rewritten.promptTokens)
    }

    /// A window of zero is not a licence to divide by it: `effectiveContextLimit`
    /// can hand one over when a stored override is nonsense.
    @Test("a non-positive window yields no fraction")
    func nonPositiveWindowYieldsNoFraction() {
        let usage = ClaudeTokenUsage(inputTokens: 100_000)

        #expect(usage.contextFraction(window: 0) == 0)
        #expect(usage.contextFraction(window: -1) == 0)
    }

    /// A `message.usage` object as `JSONSerialization` hands it over. Keys are
    /// read individually rather than through `Codable` so that a `<synthetic>`
    /// entry — which omits most of them — still decodes instead of throwing the
    /// whole entry away.
    @Test("usage is read key by key from the transcript object")
    func usageIsReadKeyByKey() {
        let full = ClaudeTokenUsage(transcriptUsage: [
            "input_tokens": 4,
            "output_tokens": 187,
            "cache_read_input_tokens": 421_312,
            "cache_creation_input_tokens": 1265,
            "service_tier": "standard",
        ])
        #expect(full.promptTokens == 422_581)
        #expect(full.outputTokens == 187)

        let sparse = ClaudeTokenUsage(transcriptUsage: ["output_tokens": 3])
        #expect(sparse.promptTokens == 0)

        #expect(ClaudeTokenUsage(transcriptUsage: [:]) == ClaudeTokenUsage())
    }
}
