//
//  HookSettings.swift
//  NotchwatchKit
//
//  What registering the relay does to a Claude Code settings file.
//

import Foundation

/// The edit `settings.json` receives when hooks are registered, as a function of
/// its contents.
///
/// Separated from the file access on purpose: this is somebody else's
/// configuration file, and the three properties that make writing to it
/// defensible — unrelated keys survive, a second install replaces rather than
/// stacks, and removal restores the shape we found — are decidable from the
/// dictionary alone, which is where they can be tested.
public enum HookSettings {
    /// The flag that marks a command as ours. No other tool has a reason to pass
    /// it, which is what lets removal leave hooks the user wrote in place.
    public static let relayFlag = "--hook-relay"

    /// Seconds Claude Code waits for the relay before abandoning it. The relay
    /// budgets a fraction of this for itself; the setting is the outer guarantee
    /// that a wedged relay cannot hold up a tool.
    public static let commandTimeout = 5

    /// Every hook the app subscribes to, in the order they are written.
    public static let subscribedEvents = HookEvent.Kind.allCases

    /// Raised rather than overwriting a value we did not put there.
    public enum Conflict: Error, LocalizedError, Equatable {
        case hooksNotAnObject
        case eventNotAnArray(String)

        public var errorDescription: String? {
            switch self {
            case .hooksNotAnObject:
                "\"hooks\" is not a JSON object."
            case let .eventNotAnArray(event):
                "\"hooks.\(event)\" is not an array of hook entries."
            }
        }
    }

    /// Whether every subscribed event already runs our relay.
    ///
    /// Deliberately "every" and not "any": a file that carries six of the seven
    /// entries — an install from a version that subscribed to fewer events, or a
    /// hand edit — is not registered, and saying otherwise leaves the missing
    /// event silently dead.
    public static func isInstalled(in settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return subscribedEvents.allSatisfy { event in
            guard let entries = hooks[event.rawValue] as? [[String: Any]] else { return false }
            return entries.contains(where: isOurs)
        }
    }

    /// The settings with our entries registered, replacing any we had left before.
    public static func adding(command: String, to settings: [String: Any]) throws -> [String: Any] {
        var settings = settings
        var hooks: [String: Any] = [:]
        if let existing = settings["hooks"] {
            guard let existing = existing as? [String: Any] else { throw Conflict.hooksNotAnObject }
            hooks = existing
        }

        for event in subscribedEvents {
            var entries: [[String: Any]] = []
            if let existing = hooks[event.rawValue] {
                guard let existing = existing as? [[String: Any]] else {
                    throw Conflict.eventNotAnArray(event.rawValue)
                }
                entries = existing
            }
            // Drop our own entry first, so re-registering after the app moves
            // updates the path instead of stacking a second relay on every call.
            entries.removeAll(where: isOurs)
            entries.append(entry(for: event, command: command))
            hooks[event.rawValue] = entries
        }

        settings["hooks"] = hooks
        return settings
    }

    /// The settings with our entries taken out, and nothing else changed.
    ///
    /// Never throws on a shape it does not recognise: removal is the escape
    /// hatch, so anything it cannot read it leaves exactly as it found it.
    public static func removing(from settings: [String: Any]) -> [String: Any] {
        var settings = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }

        for (event, value) in hooks {
            guard var entries = value as? [[String: Any]] else { continue }
            entries.removeAll(where: isOurs)
            // An event left with no entries is an empty array we introduced;
            // dropping the key returns the file to the shape we found it in.
            if entries.isEmpty {
                hooks.removeValue(forKey: event)
            } else {
                hooks[event] = entries
            }
        }

        if hooks.isEmpty {
            settings.removeValue(forKey: "hooks")
        } else {
            settings["hooks"] = hooks
        }
        return settings
    }

    /// One `hooks.<Event>` entry running the relay.
    public static func entry(for event: HookEvent.Kind, command: String) -> [String: Any] {
        let invocation: [String: Any] = [
            "type": "command",
            "command": command,
            "timeout": commandTimeout,
        ]
        var entry: [String: Any] = ["hooks": [invocation]]
        if event.takesMatcher {
            entry["matcher"] = "*"
        }
        return entry
    }

    /// Whether an entry runs our relay. Matching on the flag rather than on the
    /// path means a bundle that moved is still recognised as ours.
    public static func isOurs(_ entry: [String: Any]) -> Bool {
        guard let invocations = entry["hooks"] as? [[String: Any]] else { return false }
        return invocations.contains { ($0["command"] as? String)?.contains(relayFlag) == true }
    }
}
