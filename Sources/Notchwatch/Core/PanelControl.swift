//
//  PanelControl.swift
//  Notchwatch
//
//  Driving the panel from the command line.
//

import Foundation

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
/// Transport is a distributed notification rather than a file: the message is
/// fire-and-forget, carries no payload worth persisting, and must not leave
/// anything behind if nothing is listening. The invoking process posts and
/// exits; a running instance acts on it; with no instance running, nothing
/// happens and no state accumulates.
enum PanelControl {
    static let flag = "--panel"

    enum Command: String, CaseIterable {
        case open
        case close
        case peek
        case toggle
        /// Fabricated sessions, so that documentation never photographs real
        /// work. See `DemoScenario`.
        case demoOn = "demo-on"
        case demoOff = "demo-off"
    }

    /// Namespaced by bundle id: distributed notifications are machine-wide.
    static let notificationName = Notification.Name("io.github.sanchpet.notchwatch.panel")

    static func isControlInvocation(_ arguments: [String]) -> Bool {
        arguments.dropFirst().contains(flag)
    }

    /// Post the command named after `--panel` and exit.
    ///
    /// Exits non-zero on a command it does not know, so a typo in a script fails
    /// loudly instead of silently doing nothing.
    static func run(_ arguments: [String]) -> Never {
        guard let index = arguments.firstIndex(of: flag),
              index + 1 < arguments.count,
              let command = Command(rawValue: arguments[index + 1])
        else {
            let names = Command.allCases.map(\.rawValue).joined(separator: "|")
            FileHandle.standardError.write(Data("usage: \(flag) <\(names)>\n".utf8))
            exit(2)
        }

        DistributedNotificationCenter.default().postNotificationName(
            notificationName,
            object: command.rawValue,
            userInfo: nil,
            deliverImmediately: true
        )

        // The post hands off to the system's notification broker over XPC, so
        // exiting on the next line loses it: the process is gone before the
        // message leaves. A brief turn of the run loop is what lets it drain —
        // measured in milliseconds, and the command is a debugging affordance
        // whose whole cost is this pause.
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        exit(0)
    }

    /// Call `handler` whenever another process asks for a panel state.
    static func observe(_ handler: @escaping (Command) -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { notification in
            guard let raw = notification.object as? String,
                  let command = Command(rawValue: raw) else { return }
            handler(command)
        }
    }
}
