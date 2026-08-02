//
//  NotchGeometry.swift
//  NotchwatchKit
//
//  Where the cut-out is and how much room the panel may take — as arithmetic.
//

import CoreGraphics

/// Geometry of the display the panel lives on.
///
/// Cut-out sizes differ per machine — 179 pt on a 13" Air, wider on the 14"/16"
/// Pros — and they change under the user's hands when a display is plugged in or
/// the resolution is switched, so none of it may be tabulated per model or cached
/// at launch. What the display reports is therefore an *input* here: four numbers
/// go in (the screen frame, the two menu bar strips beside the cut-out, and the
/// height the menu bar was grown to in order to clear it) and every size the UI
/// needs comes out. Asking `NSScreen` for those four numbers is the app's job and
/// stays there; none of it appears below.
///
/// The split is what makes the sizes checkable at all. Every one of them is a
/// rectangle that either lines up with a cut-out no test machine has, or does
/// not, and the failure is silent both ways: a closed shape a few points too wide
/// paints black over the menu bar, a panel centred on the screen instead of the
/// cut-out sits a point off and stops being invisible.
public struct NotchGeometry: Equatable {
    /// Frame of the screen carrying the cut-out, in AppKit screen coordinates.
    public let screenFrame: CGRect

    /// The cut-out itself, in AppKit screen coordinates.
    public let notchRect: CGRect

    /// Sliver of the closed shape left below the cut-out. It is the only part of
    /// that shape the eye can see — everything above it is behind the camera
    /// housing — and it is what the activity glow renders into.
    static let notchLip: CGFloat = 2

    /// What the expanded panel would like to be, and what it may never shrink
    /// below before it stops being readable.
    static let preferredPanelSize = CGSize(width: 580, height: 368)
    static let minimumPanelWidth: CGFloat = 360

    /// Breathing room kept between the expanded panel and the screen edges.
    static let screenEdgeMargin: CGFloat = 24

    /// How far the closed-state tray stays inside the expanded panel's outline,
    /// so that opening the panel reads as the tray growing rather than jumping.
    static let trayInset: CGFloat = 24

    /// Room the window keeps below the panel for its shadow. Part of the window,
    /// not of the panel: `windowFrame` is taller than `panelSize` by exactly this.
    public static let shadowPadding: CGFloat = 20

    /// Stand-in for "no display to speak of". Keeps the view model total when the
    /// screen is pulled out from under a live panel; the coordinator tears that
    /// panel down on the same notification.
    public static let none = NotchGeometry(screenFrame: .zero, notchRect: .zero)

    public init(screenFrame: CGRect, notchRect: CGRect) {
        self.screenFrame = screenFrame
        self.notchRect = notchRect
    }

    // MARK: - Resolution

    /// Geometry for a display reporting these measurements, or `nil` when the
    /// display has no cut-out to speak of.
    ///
    /// The cut-out is the gap between the two menu bar strips — on macOS,
    /// `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea`. Deriving it
    /// as a gap is what keeps fudge factors out: a constant added here lands on
    /// top of a menu title on the next machine with a different cut-out.
    ///
    /// A gap of zero or less is the ordinary case, not an error: an external
    /// monitor, or any Mac built before the notch, has strips that meet or a
    /// menu bar that reports the whole width. So is a menu bar of no height —
    /// the cut-out's height *is* the height the menu bar was grown to, and a
    /// zero-height cut-out is one no closed shape could ever line up with. Both
    /// mean the same thing to the caller: there is no panel, and the app lives
    /// in the menu bar.
    public static func resolve(
        screenFrame: CGRect,
        leftStripWidth: CGFloat,
        rightStripWidth: CGFloat,
        menuBarHeight: CGFloat
    ) -> NotchGeometry? {
        let notchWidth = screenFrame.width - leftStripWidth - rightStripWidth
        guard notchWidth > 0, menuBarHeight > 0 else { return nil }

        return NotchGeometry(
            screenFrame: screenFrame,
            notchRect: CGRect(
                x: screenFrame.minX + leftStripWidth,
                y: screenFrame.maxY - menuBarHeight,
                width: notchWidth,
                height: menuBarHeight
            )
        )
    }

    // MARK: - Derived sizes

    /// Size of the closed shape: exactly the cut-out, plus the visible lip.
    ///
    /// It is deliberately never wider. The menu bar either side of the cut-out
    /// belongs to the system — the frontmost app's menus grow into it from the
    /// left, status items from the right — and AppKit exposes no way to ask how
    /// far either reaches, so the closed panel does not go there at all. Anything
    /// it has to say goes into the tray below the menu bar instead.
    public var closedSize: CGSize {
        CGSize(width: notchRect.width, height: notchRect.height + Self.notchLip)
    }

    /// Size of the expanded panel, taken from the room the screen actually has
    /// rather than from a constant: a 13" Air and a 16" Pro do not get the same
    /// panel, and neither does a Mac driving a small display.
    ///
    /// Readability wins over fitting: a display too narrow for the minimum gets
    /// the minimum anyway, and `windowFrame` deals with the overhang.
    public var panelSize: CGSize {
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
    public var peekSize: CGSize {
        CGSize(width: panelSize.width, height: closedSize.height + 60)
    }

    /// Widest the closed-state tray may get. It hangs below the menu bar, where
    /// the app owns the pixels, so the only thing limiting it is the panel it
    /// grows into.
    public var maxTrayWidth: CGFloat {
        max(closedSize.width, panelSize.width - 2 * Self.trayInset)
    }

    /// Frame for the panel window: wide enough for the expanded panel, pinned to
    /// the top of the screen and centred on the cut-out rather than on the screen
    /// — the two differ by a point or so, and the closed shape has to line up
    /// with the cut-out exactly or it stops being invisible.
    public var windowFrame: CGRect {
        let size = CGSize(width: panelSize.width, height: panelSize.height + Self.shadowPadding)
        let centredOnNotch = notchRect.midX - size.width / 2

        // Clamped so a cut-out near an edge — an oddly placed one, or a screen
        // frame with a non-zero origin in a multi-display arrangement — does not
        // drag the panel off the display. A panel wider than the display cannot
        // be kept inside it at all: clamping would then pin its *right* edge and
        // push the origin off to the left, so it starts at the left edge instead
        // and overhangs where the eye expects it to.
        let x = screenFrame.width >= size.width
            ? min(max(centredOnNotch, screenFrame.minX), screenFrame.maxX - size.width)
            : screenFrame.minX

        return CGRect(
            x: x,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}
