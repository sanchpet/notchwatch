//
//  PanelCommand.swift
//  NotchwatchKit
//
//  The vocabulary of `--panel`, and the two parts of it that are pure logic.
//

import Foundation

/// What `--panel` can ask of a running instance.
///
/// Kept apart from the transport because the testable parts of the command line
/// — what the arguments mean, and whether a delivery has already been acted on —
/// are pure logic, while everything around them is a machine-wide notification
/// centre that no unit test can stand up.
public enum PanelCommand: String, CaseIterable, Sendable {
    case open
    case close
    case peek
    case toggle
    /// Fabricated sessions, so that documentation never photographs real work.
    /// See `DemoScenario`.
    case demoOn = "demo-on"
    /// The fixture with nothing running — every session waiting on the user.
    case demoQuiet = "demo-quiet"
    /// The fixture with sessions open but between turns.
    case demoIdle = "demo-idle"
    case demoOff = "demo-off"

    public static let flag = "--panel"

    /// Whether the process was started to drive a running instance rather than to
    /// become one. `dropFirst` skips argv[0], which is a path we do not read.
    public static func isInvocation(_ arguments: [String]) -> Bool {
        arguments.dropFirst().contains(flag)
    }

    /// The command named after `--panel`, or `nil` when it is absent or unknown.
    public static func parse(_ arguments: [String]) -> PanelCommand? {
        guard let index = arguments.dropFirst().firstIndex(of: flag),
              index + 1 < arguments.count
        else { return nil }
        return PanelCommand(rawValue: arguments[index + 1])
    }

    public static var usage: String {
        "usage: \(flag) <\(allCases.map(\.rawValue).joined(separator: "|"))>"
    }
}

/// What became of a command that reached a running instance.
public enum PanelOutcome: String, Sendable {
    case applied
    /// Heard, but no attached display has a cut-out, so there is no panel to
    /// show. Reported separately from silence: the app is running and did
    /// listen, which is a different problem from nothing listening at all.
    case noNotch = "no-notch"
}

/// Remembers which deliveries have already been acted on.
///
/// The sender repeats its post until it is acknowledged, so one invocation can
/// arrive twice — the acknowledgement and the next repeat cross in flight. Every
/// repeat carries the same nonce, and a nonce seen before is answered again
/// rather than acted on again: `toggle` is the one command that would otherwise
/// end up back where it started.
public struct PanelDeliveryLedger: Sendable {
    private struct Entry: Sendable {
        let outcome: PanelOutcome
        let at: Date
    }

    private var entries: [String: Entry] = [:]
    private let retention: TimeInterval

    /// `retention` only has to outlive a sender's retry window. Nonces are never
    /// reused, so nothing needs remembering past the invocation that issued one,
    /// and expiry is what keeps the table from growing for the life of the app.
    public init(retention: TimeInterval = 30) {
        self.retention = retention
    }

    /// The outcome already recorded for `nonce`, or `nil` if this is its first
    /// delivery.
    public func outcome(for nonce: String, now: Date = Date()) -> PanelOutcome? {
        guard let entry = entries[nonce], now.timeIntervalSince(entry.at) < retention else {
            return nil
        }
        return entry.outcome
    }

    public mutating func record(_ outcome: PanelOutcome, for nonce: String, now: Date = Date()) {
        entries = entries.filter { now.timeIntervalSince($0.value.at) < retention }
        entries[nonce] = Entry(outcome: outcome, at: now)
    }
}
