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
        // Same reasoning as the relay: a control invocation talks to whatever
        // instance is already running and must never become a second one.
        if PanelControl.isControlInvocation(CommandLine.arguments) {
            PanelControl.run(CommandLine.arguments)
        }
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
