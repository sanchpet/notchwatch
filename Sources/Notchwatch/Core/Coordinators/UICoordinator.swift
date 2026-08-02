import AppKit
import Combine
import NotchwatchKit
import SwiftUI

@MainActor
public final class UICoordinator: ObservableObject {
    public static let shared = UICoordinator()

    @Published var isExpanded: Bool = false

    /// Geometry of the display carrying the cut-out, or `nil` when no attached
    /// display has one. Single source of truth for everything that has to know
    /// where the panel goes.
    @Published private(set) var geometry: NotchGeometry?

    /// Whether there is a cut-out to live in at all. Without one there is no
    /// panel, and the menu bar item is the whole UI.
    var hasNotch: Bool {
        geometry != nil
    }

    @Published private(set) var isVisible: Bool = true

    /// The panel's state, owned here rather than by the view that draws it.
    ///
    /// `--panel` must be answerable for as long as the process lives, and the
    /// view is not: on a display without a cut-out it is never built, and a
    /// display change tears it down. Lazy because the model reads back from this
    /// coordinator, which does not exist yet while `shared` is being created.
    private(set) lazy var notchViewModel = NotchViewModel(coordinator: self)

    private var notchPanel: NotchPanel?
    private var menuBarController: MenuBarController?
    private var cancellables = Set<AnyCancellable>()

    /// Whether there is anything for a command to act on yet.
    private var isReady = false

    /// Commands that arrived before `setupUI` ran. The observer is registered at
    /// process start, so this is possible; they wait here rather than being
    /// answered, which leaves the sender repeating until they can be applied for
    /// real instead of being acknowledged into a half-built app.
    private var deferredCommands: [(command: PanelCommand, nonce: String)] = []

    private var deliveries = PanelDeliveryLedger()

    private init() {}

    public func setupUI() {
        // Displays come and go: an external monitor is attached, the lid is
        // closed, the resolution changes. Each of those moves the cut-out or
        // removes it, so the panel is (re)built from the notification rather
        // than measured once at launch.
        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            // A single display change fires this several times in a row while
            // the arrangement settles; rebuilding on each one would move the
            // panel to intermediate positions it should never be seen in.
            .debounce(for: .milliseconds(150), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateGeometry()
            }
            .store(in: &cancellables)

        updateGeometry()

        // Always setup menu bar as fallback/additional control
        setupMenuBar()

        isReady = true
        let deferred = deferredCommands
        deferredCommands.removeAll()
        for delivery in deferred {
            receive(delivery.command, nonce: delivery.nonce)
        }
    }

    /// Act on one `--panel` command and say what became of it.
    ///
    /// The single entry point for everything the command line can ask of a
    /// running app — including on a machine with no cut-out, where the demo
    /// fixtures still make sense and the panel commands still have to answer for
    /// themselves rather than go quiet.
    func receive(_ command: PanelCommand, nonce: String) {
        if let alreadyDone = deliveries.outcome(for: nonce) {
            // A repeat that crossed its own acknowledgement in flight. Answer it
            // again, but do not act again: `toggle` is not idempotent.
            PanelControl.acknowledge(alreadyDone, nonce: nonce)
            return
        }

        guard isReady else {
            if !deferredCommands.contains(where: { $0.nonce == nonce }) {
                deferredCommands.append((command, nonce))
            }
            return
        }

        let outcome = apply(command)
        deliveries.record(outcome, for: nonce)
        PanelControl.acknowledge(outcome, nonce: nonce)
    }

    private func apply(_ command: PanelCommand) -> PanelOutcome {
        switch command {
        case .open: notchViewModel.open()
        case .close: notchViewModel.close()
        case .toggle: notchViewModel.toggle()
        case .peek: notchViewModel.peek(duration: AppSettings.shared.noticeDurationSeconds)
        // The fixtures drive the session data, not the panel, so they apply on
        // any display: `demo-on` before a screenshot is worth taking is exactly
        // when there is no cut-out to report about.
        case .demoOn: ClaudeCodeManager.shared.enterDemoMode(.busy); return .applied
        case .demoQuiet: ClaudeCodeManager.shared.enterDemoMode(.quiet); return .applied
        case .demoIdle: ClaudeCodeManager.shared.enterDemoMode(.idle); return .applied
        case .demoOff: ClaudeCodeManager.shared.exitDemoMode(); return .applied
        }

        // The state moved; whether anything can be seen is another matter, and
        // the caller is told which of the two it got.
        return hasNotch ? .applied : .noNotch
    }

    private func updateGeometry() {
        let resolved = NotchGeometry.resolve()
        guard resolved != geometry else { return }

        geometry = resolved

        if let resolved {
            syncNotchPanel(to: resolved)
        } else {
            cleanup()
        }
    }

    private func syncNotchPanel(to geometry: NotchGeometry) {
        let frame = geometry.windowFrame

        if let notchPanel {
            notchPanel.setFrame(frame, display: true)
            return
        }

        let panel = NotchPanel(contentRect: frame)
        panel.setContent { [notchViewModel] in
            NotchContentView(notchVM: notchViewModel)
        }

        // Add to the notch space for proper layering
        panel.addToNotchSpace()

        if isVisible {
            panel.orderFrontRegardless()
        }

        notchPanel = panel
    }

    private func setupMenuBar() {
        menuBarController = MenuBarController()
        menuBarController?.setup()
    }

    public func show() {
        isVisible = true
        notchPanel?.orderFront(nil)
    }

    public func hide() {
        isVisible = false
        notchPanel?.orderOut(nil)
    }

    public func cleanup() {
        notchPanel?.removeFromNotchSpace()
        notchPanel?.close()
        notchPanel = nil
    }
}
