import AppKit
import SwiftUI

final class NotchwatchAppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Directly, not through a Task: this method already runs on the main
        // actor, and the hop only delayed the moment the app could act on a
        // `--panel` command that was already waiting in the port.
        UICoordinator.shared.setupUI()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    @objc func showSettingsWindow() {
        if let existingWindow = settingsWindow, existingWindow.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = NSHostingController(rootView: SettingsView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        // The app is an accessory: it has no menu bar of its own, so this title
        // is the only place the settings window names the product.
        window.title = "\(AppIdentity.displayName) Settings"
        window.setFrameAutosaveName("SettingsWindow")
        window.center()
        window.isReleasedWhenClosed = false

        settingsWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
