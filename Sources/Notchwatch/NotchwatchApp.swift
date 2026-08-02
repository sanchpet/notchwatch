import SwiftUI

/// How the product names itself in the interface.
///
/// Read from the bundle rather than hardcoded so the name has one source:
/// `scripts/product.env` feeds `CFBundleName` through `Resources/Info.plist.in`.
/// The literal is the fallback for `swift run`, which has no bundle at all.
enum AppIdentity {
    static let displayName = Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "Notchwatch"
}

/// Process entry point.
///
/// The same binary is also the Claude Code hook command, so the relay is checked
/// for before anything else: it must not bring up AppKit, must not touch a
/// running instance, and must return in milliseconds. Everything else is the app.
@main
enum NotchwatchMain {
    static func main() {
        if HookRelay.isRelayInvocation(CommandLine.arguments) {
            HookRelay.run()
        }

        // Read before anything can replace the file underneath us, and before
        // the branches below can consume it.
        BuildInfo.capture()

        if BuildInfo.isVersionInvocation(CommandLine.arguments) {
            print(BuildInfo.stamp.full)
            exit(0)
        }

        // Same reasoning as the relay: a control invocation talks to whatever
        // instance is already running and must never become a second one.
        if PanelControl.isControlInvocation(CommandLine.arguments) {
            PanelControl.run(CommandLine.arguments)
        }

        // Before AppKit, and that is the point: a command posted while nothing is
        // listening is dropped, never queued, so the observer has to exist before
        // anything can be sent at a process that has visibly started. What it
        // still cannot cover — dyld and static initialisation — is why the sender
        // repeats itself. See `PanelControl.startListening`.
        PanelControl.startListening()

        NotchwatchApp.main()
    }
}

struct NotchwatchApp: App {
    @NSApplicationDelegateAdaptor(NotchwatchAppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
