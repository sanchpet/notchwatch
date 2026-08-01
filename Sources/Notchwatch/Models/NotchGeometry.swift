// NotchGeometry.swift
// Where the cut-out is and how much room the panel may take, as reported by the display

import AppKit

/// Geometry of the display the panel lives on, read back from AppKit.
///
/// Cut-out sizes differ per machine — 179 pt on a 13" Air, wider on the 14"/16"
/// Pros — and they change under the user's hands when a display is plugged in or
/// the resolution is switched, so none of it may be tabulated per model or cached
/// at launch. `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` are the two menu
/// bar strips beside the cut-out, which makes whatever lies between them the
/// cut-out itself, and `safeAreaInsets.top` is the height the menu bar was grown
/// to in order to clear it.
struct NotchGeometry: Equatable {
    /// Frame of the screen carrying the cut-out, in AppKit screen coordinates.
    let screenFrame: CGRect

    /// The cut-out itself, in AppKit screen coordinates.
    let notchRect: CGRect

    /// Sliver of the closed shape left below the cut-out. It is the only part of
    /// that shape the eye can see — everything above it is behind the camera
    /// housing — and it is what the activity glow renders into.
    private static let notchLip: CGFloat = 2

    /// What the expanded panel would like to be, and what it may never shrink
    /// below before it stops being readable.
    private static let preferredPanelSize = CGSize(width: 580, height: 368)
    private static let minimumPanelWidth: CGFloat = 360

    /// Breathing room kept between the expanded panel and the screen edges.
    private static let screenEdgeMargin: CGFloat = 24

    /// How far the closed-state tray stays inside the expanded panel's outline,
    /// so that opening the panel reads as the tray growing rather than jumping.
    private static let trayInset: CGFloat = 24

    /// Stand-in for "no display to speak of". Keeps the view model total when the
    /// screen is pulled out from under a live panel; the coordinator tears that
    /// panel down on the same notification.
    static let none = NotchGeometry(screenFrame: .zero, notchRect: .zero)

    // MARK: - Resolution

    /// Geometry of the screen that carries a cut-out, or `nil` when none of the
    /// attached displays has one — an external monitor, or any Mac built before
    /// the notch. There is no panel in that case: the app lives in the menu bar.
    static func resolve() -> NotchGeometry? {
        guard let screen = notchedScreen(),
              let leftStrip = screen.auxiliaryTopLeftArea,
              let rightStrip = screen.auxiliaryTopRightArea else { return nil }

        // The gap between the two menu bar strips is the cut-out. Deriving it
        // this way is what keeps fudge factors out: a constant added here lands
        // on top of a menu title on the next machine with a different cut-out.
        let frame = screen.frame
        let notchWidth = frame.width - leftStrip.width - rightStrip.width
        guard notchWidth > 0 else { return nil }

        return NotchGeometry(
            screenFrame: frame,
            notchRect: CGRect(
                x: frame.minX + leftStrip.width,
                y: frame.maxY - screen.safeAreaInsets.top,
                width: notchWidth,
                height: screen.safeAreaInsets.top
            )
        )
    }

    /// The built-in display, identified by the fact that it has a cut-out rather
    /// than by `NSScreen.main`: `main` follows the key window, and an accessory
    /// app never owns one, so it can just as well point at an external monitor.
    private static func notchedScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }
    }

    // MARK: - Derived sizes

    /// Size of the closed shape: exactly the cut-out, plus the visible lip.
    ///
    /// It is deliberately never wider. The menu bar either side of the cut-out
    /// belongs to the system — the frontmost app's menus grow into it from the
    /// left, status items from the right — and AppKit exposes no way to ask how
    /// far either reaches, so the closed panel does not go there at all. Anything
    /// it has to say goes into the tray below the menu bar instead.
    var closedSize: CGSize {
        CGSize(width: notchRect.width, height: notchRect.height + Self.notchLip)
    }

    /// Size of the expanded panel, taken from the room the screen actually has
    /// rather than from a constant: a 13" Air and a 16" Pro do not get the same
    /// panel, and neither does a Mac driving a small display.
    var panelSize: CGSize {
        guard !screenFrame.isEmpty else { return Self.preferredPanelSize }

        let availableWidth = screenFrame.width - 2 * Self.screenEdgeMargin
        let availableHeight = screenFrame.height - notchRect.height - 2 * Self.screenEdgeMargin

        return CGSize(
            width: min(Self.preferredPanelSize.width, max(Self.minimumPanelWidth, availableWidth)),
            height: min(Self.preferredPanelSize.height, max(closedSize.height, availableHeight))
        )
    }

    /// Size of the peek drop-down. It appears uninvited, so it claims only the
    /// height it needs and no more width than the panel it belongs to.
    var peekSize: CGSize {
        CGSize(width: panelSize.width, height: closedSize.height + 60)
    }

    /// Widest the closed-state tray may get. It hangs below the menu bar, where
    /// the app owns the pixels, so the only thing limiting it is the panel it
    /// grows into.
    var maxTrayWidth: CGFloat {
        max(closedSize.width, panelSize.width - 2 * Self.trayInset)
    }

    /// Frame for the panel window: wide enough for the expanded panel, pinned to
    /// the top of the screen and centred on the cut-out rather than on the screen
    /// — the two differ by a point or so, and the closed shape has to line up
    /// with the cut-out exactly or it stops being invisible.
    var windowFrame: CGRect {
        let size = CGSize(width: panelSize.width, height: panelSize.height + shadowPadding)
        let centredX = notchRect.midX - size.width / 2
        let clampedX = min(max(centredX, screenFrame.minX), screenFrame.maxX - size.width)

        return CGRect(
            x: screenFrame.width >= size.width ? clampedX : screenFrame.minX,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
