//
//  SessionStandingTests.swift
//  NotchwatchKitTests
//
//  The list is opened to answer one question — which of these is calling me —
//  and the answer is a priority and an order. Both fail silently: a row that
//  claims the wrong standing, or a caller pushed below an idle session, looks
//  exactly like a working panel.
//

import Foundation
@testable import NotchwatchKit
import Testing

@Suite("Session standing")
struct SessionStandingTests {
    // MARK: - Classification

    /// The priority that matters most. A session can be blocked on a permission
    /// prompt *and* have handed the turn back; saying "your turn" sends the user
    /// to a session that cannot take their input until the prompt is answered.
    @Test("a permission prompt outranks a finished turn")
    func permissionOutranksAFinishedTurn() {
        let standing = SessionStanding(needsPermission: true, isAwaitingReply: true, isActive: false)
        #expect(standing == .needsPermission)

        // And outranks activity too — a tool waiting to be allowed to run is not
        // work in progress, however busy the rest of the session looks.
        #expect(SessionStanding(needsPermission: true, isAwaitingReply: false, isActive: true) == .needsPermission)
    }

    /// The agent that is still working needs nothing; the one that stopped does.
    @Test("a finished turn outranks activity")
    func finishedTurnOutranksActivity() {
        let standing = SessionStanding(needsPermission: false, isAwaitingReply: true, isActive: true)
        #expect(standing == .awaitingReply)
    }

    @Test("activity outranks nothing at all")
    func activityOutranksIdle() {
        #expect(SessionStanding(needsPermission: false, isAwaitingReply: false, isActive: true) == .working)
        #expect(SessionStanding(needsPermission: false, isAwaitingReply: false, isActive: false) == .idle)
    }

    // MARK: - Label

    /// Colour alone is a poor carrier, and a badge on every row is a badge on
    /// none: exactly the two standings that are asking for something say so.
    @Test("only the two standings that ask for something are labelled")
    func exactlyTwoStandingsAreLabelled() {
        let labelled = SessionStanding.allCases.filter { $0.label != nil }

        #expect(labelled == [.needsPermission, .awaitingReply])
        #expect(SessionStanding.needsPermission.label == "needs you")
        #expect(SessionStanding.awaitingReply.label == "your turn")
    }

    // MARK: - Order

    /// The whole point of the ordering: the callers come to the top, whatever
    /// the clock says. Here the busiest and most recent sessions are the ones
    /// that want nothing, so recency alone would bury both callers.
    @Test("the rows asking for something sort to the top")
    func askersSortToTheTop() {
        let now = Date()
        let rows: [(standing: SessionStanding, lastUpdate: Date?)] = [
            (.idle, now),
            (.working, now.addingTimeInterval(-1)),
            (.awaitingReply, now.addingTimeInterval(-600)),
            (.needsPermission, now.addingTimeInterval(-3600)),
        ]

        let sorted = rows.sorted(by: SessionStanding.precedes)

        #expect(sorted.map(\.standing) == [.needsPermission, .awaitingReply, .working, .idle])
    }

    /// Recency is the tie-break, not the sort: it only orders rows of equal
    /// standing, newest first.
    @Test("equal standings are ordered newest first")
    func equalStandingsGoNewestFirst() {
        let now = Date()
        let rows: [(standing: SessionStanding, lastUpdate: Date?)] = [
            (.working, now.addingTimeInterval(-60)),
            (.working, now),
            (.working, now.addingTimeInterval(-10)),
        ]

        let sorted = rows.sorted(by: SessionStanding.precedes)

        #expect(sorted.map(\.lastUpdate) == [now, now.addingTimeInterval(-10), now.addingTimeInterval(-60)])
    }

    /// A session that has never been heard from has no claim to the top of its
    /// group — a missing date must not read as "just now".
    @Test("a session never heard from sorts last within its standing")
    func neverHeardFromSortsLast() {
        let now = Date()
        let rows: [(standing: SessionStanding, lastUpdate: Date?)] = [
            (.working, nil),
            (.working, now.addingTimeInterval(-86400)),
        ]

        let sorted = rows.sorted(by: SessionStanding.precedes)

        #expect(sorted.map(\.lastUpdate) == [now.addingTimeInterval(-86400), nil])
    }

    /// Sorting must be a strict order, or `sorted(by:)` is free to produce
    /// anything: a list that reshuffles between two identical scans is worse
    /// than a wrong order, because it cannot even be read twice.
    @Test("the order is strict — nothing precedes itself")
    func orderIsStrict() {
        let now = Date()

        for standing in SessionStanding.allCases {
            #expect(SessionStanding.precedes((standing, now), (standing, now)) == false)
            #expect(SessionStanding.precedes((standing, nil), (standing, nil)) == false)
        }
    }
}
