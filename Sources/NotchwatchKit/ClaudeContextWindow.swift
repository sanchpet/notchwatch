//
//  ClaudeContextWindow.swift
//  NotchwatchKit
//
//  The denominator of the context bar.
//

import Foundation

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
/// * the model *pin* — `settings.json` → `"model": "opus[1m]"`, an alias rather
///   than a full id, and read from the session's own config root (see
///   `ClaudeModelPin`);
/// * `toolUseResult.resolvedModel` on a `Task` result — present in 9 of the 44
///   transcripts, and only when a subagent actually ran.
///
/// Neither is complete: 8 transcripts with no marker anywhere still reached
/// prompts of 214k–620k, which a 200k window could not have held. So the last
/// word belongs to the session itself — a window can never be smaller than a
/// prompt that demonstrably fit inside it.
///
/// This lives in the kit, apart from the settings object and the bar that draws
/// it, because all three of its rules have been wrong in production and none of
/// the failures were visible: a plausible number in a bar looks exactly like a
/// correct one.
public enum ClaudeContextWindow {
    /// Window of the models that predate the 1M-token context — and of anything
    /// unrecognised.
    public static let standard = 200_000
    public static let extended = 1_000_000

    /// Windows this app can name, smallest first. Evidence promotes a session to
    /// the first tier large enough to hold what it has already sent.
    private static let tiers = [standard, extended]

    /// Whether `modelID` carries Claude Code's 1M-context opt-in suffix.
    ///
    /// Applies to the bare aliases a pin uses (`opus[1m]`) as much as to full ids,
    /// so it deliberately tests only the suffix — case-insensitively, because the
    /// string can come from a hand-edited settings file as readily as from a
    /// `resolvedModel` field.
    public static func declaresLongWindow(_ modelID: String) -> Bool {
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
    public static func forModel(_ model: String) -> Int {
        declaresLongWindow(model) ? extended : standard
    }

    /// Window to measure against, from the model, any opt-in seen for the
    /// session, and the largest prompt the session has actually sent.
    ///
    /// The evidence floor is what keeps a misread model from pinning the bar at
    /// 100%: a session that has already sent 620k tokens is not running a 200k
    /// window, whatever the id says. A prompt larger than every named tier
    /// becomes its own window — the bar then reads full, which is the honest
    /// answer when the app has no larger tier to name.
    public static func resolve(model: String, longWindowOptIn: Bool, observedPromptTokens: Int) -> Int {
        let declared = longWindowOptIn ? extended : forModel(model)
        guard observedPromptTokens > declared else { return declared }
        return tiers.first { $0 >= observedPromptTokens } ?? observedPromptTokens
    }
}
