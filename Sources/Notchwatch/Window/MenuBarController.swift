import AppKit
import Combine
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var eventMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var settingsCancellable: AnyCancellable?

    /// The status item is optional next to the notch panel, but it is the only
    /// UI left on a Mac without a cut-out — an external display, or anything
    /// built before the notch — so there it stays regardless of the setting.
    private var shouldShowStatusItem: Bool {
        AppSettings.shared.showMenuBarItem || !UICoordinator.shared.hasNotch
    }

    func setup() {
        updateMenuBarVisibility()
        settingsCancellable = AppSettings.shared.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenuBarVisibility()
            }

        // Unplugging the built-in display takes the panel with it; the status
        // item has to appear in its place without a relaunch.
        UICoordinator.shared.$geometry
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateMenuBarVisibility()
            }
            .store(in: &cancellables)
    }

    private func updateMenuBarVisibility() {
        if shouldShowStatusItem {
            if statusItem == nil {
                setupStatusItemAndPopover()
            }
        } else if let statusItem {
            closePopover()
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
            if let eventMonitor {
                NSEvent.removeMonitor(eventMonitor)
                self.eventMonitor = nil
            }
            popover = nil
        }
    }

    private func setupStatusItemAndPopover() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem?.button {
            button.image = NSImage(
                systemSymbolName: "waveform.path.ecg",
                accessibilityDescription: AppIdentity.displayName
            )
            button.action = #selector(togglePopover)
            button.target = self
        }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 400)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView()
                .environmentObject(UICoordinator.shared)
        )
        self.popover = popover

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            closePopover()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
