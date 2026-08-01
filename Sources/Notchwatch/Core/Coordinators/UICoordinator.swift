import AppKit
import Combine
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

    private var notchPanel: NotchPanel?
    private var menuBarController: MenuBarController?
    private var cancellables = Set<AnyCancellable>()

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
        panel.setContent {
            NotchContentView()
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
