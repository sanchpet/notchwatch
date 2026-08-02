//
//  PanelControl.swift
//  Notchwatch
//
//  Driving the panel from the command line.
//

import Foundation
import NotchwatchKit

/// Opens, closes and peeks the panel from another process.
///
/// The panel is otherwise reachable only by pointing at it, which makes the app
/// awkward to photograph, to demonstrate and — the reason this exists — to
/// debug: reproducing "how does it look with five sessions and a workflow
/// running" should not depend on where a cursor landed.
///
/// The alternative was to grant an agent macOS Accessibility so it could
/// synthesise clicks. That permission cannot be scoped to one application: it is
/// the right to send input anywhere, to press any button in any window. Handing
/// it out so that something can open *our own* window is the wrong trade, and
/// the app can simply be asked instead.
///
/// Transport is a distributed notification rather than a file: the message must
/// not leave anything behind if nothing is listening. Unlike a hook event, which
/// is a fact about the past and may legitimately go stale on disk, a command is
/// an imperative — spooled, it would fire at the next launch and open the panel
/// by itself minutes later.
///
/// The one thing that centre does not do is queue. A post made while no observer
/// is registered is dropped outright; there is no store-and-forward for a
/// subscriber that arrives a moment later. Posting once and exiting therefore
/// lost, silently, every command sent while the app was still starting. So the
/// sender repeats until the app answers, and exits non-zero if it never does.
enum PanelControl {
    /// Namespaced by bundle id: distributed notifications are machine-wide.
    static let notificationName = Notification.Name("io.github.sanchpet.notchwatch.panel")
    /// The answer. Its absence is the whole signal that a command was lost.
    static let ackName = Notification.Name("io.github.sanchpet.notchwatch.panel.ack")

    /// Ties one invocation to its own repeats and to its answer. It travels in
    /// `userInfo` because a distributed notification's `object` must be a string.
    private static let nonceKey = "nonce"
    private static let outcomeKey = "outcome"

    /// How long the sender keeps asking before calling the command undelivered.
    /// Paid in full only when nothing is listening: a running app answers in
    /// single-digit milliseconds, which is quicker than the fixed 200 ms pause
    /// this replaced.
    private static let deadline: TimeInterval = 2.0
    /// Gap between repeats. Wide enough not to flood a machine-wide broadcast,
    /// narrow enough to catch an app that is still starting.
    private static let repeatInterval: TimeInterval = 0.05
    /// Run-loop slice between checks for the answer. This, not the repeat gap, is
    /// what bounds how long a successful call takes.
    private static let pollInterval: TimeInterval = 0.01

    static func isControlInvocation(_ arguments: [String]) -> Bool {
        PanelCommand.isInvocation(arguments)
    }

    /// Post the command named after `--panel`, wait to be told it landed, exit.
    ///
    /// Exits non-zero on a command it does not know, and on a command nobody
    /// acted on: a typo and a lost message are both failures a script has to be
    /// able to see. Silence is the one outcome a debugging affordance must not
    /// have — which is what this cost, before, on every launch race and forever
    /// on a display without a cut-out.
    static func run(_ arguments: [String]) -> Never {
        guard let command = PanelCommand.parse(arguments) else {
            fail(PanelCommand.usage, code: 2)
        }

        let center = DistributedNotificationCenter.default()
        let nonce = UUID().uuidString
        let inbox = Inbox()

        // Listening before the first post, and the order is not incidental: an
        // answer arriving while nothing is registered is gone, exactly as a
        // command posted at a not-yet-listening app is gone.
        _ = center.addObserver(forName: ackName, object: nil, queue: .main) { notification in
            guard notification.userInfo?[nonceKey] as? String == nonce else { return }
            inbox.outcome = (notification.userInfo?[outcomeKey] as? String)
                .flatMap(PanelOutcome.init(rawValue:)) ?? .applied
        }

        var nextPost = Date.distantPast
        let giveUp = Date().addingTimeInterval(deadline)

        while inbox.outcome == nil, Date() < giveUp {
            if Date() >= nextPost {
                center.postNotificationName(
                    notificationName,
                    object: command.rawValue,
                    userInfo: [nonceKey: nonce],
                    deliverImmediately: true
                )
                nextPost = Date().addingTimeInterval(repeatInterval)
            }
            // Turning the run loop is both how a post drains to the system
            // broker — the process exiting on the next line would lose it — and
            // how the answer gets delivered.
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }

        switch inbox.outcome {
        case .applied:
            exit(0)
        case .noNotch:
            fail("\(PanelCommand.flag) \(command.rawValue): no attached display has a cut-out, so there is no panel to show", code: 1)
        case nil:
            fail("\(PanelCommand.flag) \(command.rawValue): no running instance answered within \(Int(deadline * 1000)) ms", code: 1)
        }
    }

    /// Start answering `--panel`, for as long as the process lives.
    ///
    /// Called from `main()`, ahead of AppKit, because registration is the
    /// cut-off and the run loop is not: a notification that arrives with the
    /// observer in place but the run loop not yet turning waits in the mach port
    /// and is delivered the moment it turns, while one that arrives an instant
    /// earlier is simply gone. Registering any later — in the app delegate, or in
    /// a view's `onAppear`, where this used to live — is a window in which
    /// commands vanish; and since the panel's view is never built on a display
    /// without a cut-out, `onAppear` left `--panel` dead for the whole session
    /// rather than for a fraction of one.
    static func startListening() {
        _ = DistributedNotificationCenter.default().addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { notification in
            guard let raw = notification.object as? String,
                  let command = PanelCommand(rawValue: raw),
                  let nonce = notification.userInfo?[nonceKey] as? String
            else { return }

            // `queue: .main` runs the block on the main thread, which is the
            // main actor's executor. Hopping through a Task instead would only
            // add latency and leave the order against the app's own launch open.
            MainActor.assumeIsolated {
                UICoordinator.shared.receive(command, nonce: nonce)
            }
        }
    }

    /// Tell the sender what became of its command, so it can stop asking.
    static func acknowledge(_ outcome: PanelOutcome, nonce: String) {
        DistributedNotificationCenter.default().postNotificationName(
            ackName,
            object: nil,
            userInfo: [nonceKey: nonce, outcomeKey: outcome.rawValue],
            deliverImmediately: true
        )
    }

    /// Holds the answer for the loop waiting on it: the observer's block outlives
    /// the call that registers it. Only the main thread ever touches this.
    private final class Inbox {
        var outcome: PanelOutcome?
    }

    private static func fail(_ message: String, code: Int32) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(code)
    }
}
