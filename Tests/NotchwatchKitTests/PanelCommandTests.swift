//
//  PanelCommandTests.swift
//  NotchwatchKitTests
//
//  The command line's two decisions: what was asked for, and whether it has
//  already been done. The second one exists because the sender now repeats
//  itself until it is answered.
//

import Foundation
@testable import NotchwatchKit
import Testing

@Suite("Panel commands")
struct PanelCommandTests {
    @Test("the command named after the flag is the command")
    func parsesTheCommandAfterTheFlag() {
        #expect(PanelCommand.parse(["Notchwatch", "--panel", "open"]) == .open)
        #expect(PanelCommand.parse(["Notchwatch", "--panel", "demo-quiet"]) == .demoQuiet)
    }

    /// A typo has to fail loudly. Answering it as if it were a known command
    /// would leave a script quietly doing nothing.
    @Test("an unknown or missing command does not parse")
    func rejectsUnknownAndMissingCommands() {
        #expect(PanelCommand.parse(["Notchwatch", "--panel", "opne"]) == nil)
        #expect(PanelCommand.parse(["Notchwatch", "--panel"]) == nil)
        #expect(PanelCommand.parse(["Notchwatch"]) == nil)
    }

    /// argv[0] is a path, not an argument: an executable that happens to live
    /// under a directory named `--panel` is still the app, not an invocation.
    @Test("the executable path is not read as an argument")
    func ignoresArgvZero() {
        #expect(PanelCommand.isInvocation(["/opt/--panel/Notchwatch"]) == false)
        #expect(PanelCommand.parse(["/opt/--panel/Notchwatch", "open"]) == nil)
        #expect(PanelCommand.isInvocation(["Notchwatch", "--panel", "close"]))
    }
}

@Suite("Repeated deliveries")
struct PanelDeliveryLedgerTests {
    private static let nonce = "8B0E0C1E-0000-4000-8000-000000000001"

    @Test("a nonce not seen before has no outcome")
    func firstDeliveryIsUnrecorded() {
        let ledger = PanelDeliveryLedger()

        #expect(ledger.outcome(for: Self.nonce) == nil)
    }

    /// The regression this guards: the sender's repeat and its acknowledgement
    /// cross in flight, the app hears one invocation twice, and `toggle` opens
    /// and closes the panel in a single call.
    @Test("a repeated nonce reports what was already done")
    func repeatedDeliveryReportsTheRecordedOutcome() {
        var ledger = PanelDeliveryLedger()
        ledger.record(.applied, for: Self.nonce)

        #expect(ledger.outcome(for: Self.nonce) == .applied)
        #expect(ledger.outcome(for: "some other nonce") == nil)
    }

    @Test("the recorded outcome is the one reported back")
    func remembersOutcomePerNonce() {
        var ledger = PanelDeliveryLedger()
        ledger.record(.noNotch, for: Self.nonce)

        #expect(ledger.outcome(for: Self.nonce) == .noNotch)
    }

    /// Nonces are never reused, so an entry only has to outlive the invocation
    /// that issued it. Without expiry the table grows for the life of the app.
    @Test("entries expire, and expiring one does not lose the others")
    func forgetsEntriesPastRetention() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        var ledger = PanelDeliveryLedger(retention: 30)
        ledger.record(.applied, for: Self.nonce, now: start)

        #expect(ledger.outcome(for: Self.nonce, now: start.addingTimeInterval(29)) == .applied)
        #expect(ledger.outcome(for: Self.nonce, now: start.addingTimeInterval(31)) == nil)

        let fresh = "8B0E0C1E-0000-4000-8000-000000000002"
        ledger.record(.applied, for: fresh, now: start.addingTimeInterval(31))

        #expect(ledger.outcome(for: fresh, now: start.addingTimeInterval(31)) == .applied)
        #expect(ledger.outcome(for: Self.nonce, now: start.addingTimeInterval(31)) == nil)
    }
}
