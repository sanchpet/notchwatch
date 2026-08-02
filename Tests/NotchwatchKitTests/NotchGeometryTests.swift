//
//  NotchGeometryTests.swift
//  NotchwatchKitTests
//
//  Rectangles that either line up with a cut-out or do not. The machine running
//  these tests may have no cut-out at all — which is the point: the arithmetic
//  takes the display's numbers as arguments, so every size can be checked
//  against a display that is not attached.
//

import CoreGraphics
@testable import NotchwatchKit
import Testing

@Suite("Notch geometry")
struct NotchGeometryTests {
    /// What a display reports: its frame, the two menu bar strips beside the
    /// cut-out, and the height the menu bar was grown to in order to clear it.
    private struct Display {
        var frame: CGRect
        var leftStrip: CGFloat
        var rightStrip: CGFloat
        var menuBarHeight: CGFloat

        var geometry: NotchGeometry? {
            NotchGeometry.resolve(
                screenFrame: frame,
                leftStripWidth: leftStrip,
                rightStripWidth: rightStrip,
                menuBarHeight: menuBarHeight
            )
        }
    }

    /// A 13" Air: 1470 × 956 points, a 179 pt cut-out centred in a 24 pt menu bar.
    private static let air = Display(
        frame: CGRect(x: 0, y: 0, width: 1470, height: 956),
        leftStrip: 645.5,
        rightStrip: 645.5,
        menuBarHeight: 24
    )

    /// A 16" Pro: wider screen, wider cut-out, taller menu bar. Nothing may be
    /// tabulated per model, so the same arithmetic has to serve both.
    private static let pro = Display(
        frame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
        leftStrip: 764,
        rightStrip: 764,
        menuBarHeight: 37
    )

    // MARK: - Resolution

    /// The ordinary case on most Macs, and the one that must not produce a
    /// panel: the two menu bar strips meet, so there is no gap to live in.
    @Test("a display with no gap between the menu bar strips has no geometry")
    func noGapMeansNoGeometry() {
        var display = Self.air
        display.leftStrip = 735
        display.rightStrip = 735
        #expect(display.geometry == nil)

        // Negative, too: an external display can report strips that overlap or
        // add up to more than the frame. Same answer — there is no cut-out.
        display.rightStrip = 800
        #expect(display.geometry == nil)
    }

    /// The cut-out's height *is* the height the menu bar was grown to, so a menu
    /// bar of no height is a cut-out no closed shape could ever line up with.
    @Test("a menu bar of no height has no geometry")
    func noMenuBarHeightMeansNoGeometry() {
        var display = Self.air
        display.menuBarHeight = 0
        #expect(display.geometry == nil)
    }

    /// The cut-out is derived as the gap, never as a constant: a fudge factor
    /// added here lands on top of a menu title on the next machine.
    @Test("the cut-out is the gap between the strips, at the top of the screen")
    func cutOutIsTheGap() throws {
        let geometry = try #require(Self.air.geometry)

        #expect(geometry.notchRect.width == 179)
        #expect(geometry.notchRect.height == 24)
        #expect(geometry.notchRect.minX == 645.5)
        #expect(geometry.notchRect.maxY == geometry.screenFrame.maxY)
    }

    /// A second display sits at a non-zero origin in the global coordinate
    /// space, and the cut-out is placed relative to its own frame.
    @Test("the cut-out follows a screen frame with a non-zero origin")
    func cutOutFollowsTheScreenOrigin() throws {
        var display = Self.air
        display.frame = CGRect(x: -1470, y: 0, width: 1470, height: 956)
        let geometry = try #require(display.geometry)

        #expect(geometry.notchRect.minX == -1470 + 645.5)
        #expect(geometry.notchRect.maxY == geometry.screenFrame.maxY)
    }

    // MARK: - Closed shape

    /// The invariant the closed shape exists under. The menu bar either side of
    /// the cut-out belongs to the system, and AppKit will not say how far the
    /// menus or the status items reach, so a closed shape one point too wide
    /// paints black over somebody else's pixels — and nothing on screen says so.
    @Test("the closed shape is never wider than the cut-out")
    func closedShapeNeverExceedsTheCutOut() throws {
        var wideCutOut = Self.air
        wideCutOut.leftStrip = 400
        wideCutOut.rightStrip = 400

        for display in [Self.air, Self.pro, wideCutOut] {
            let geometry = try #require(display.geometry)
            #expect(geometry.closedSize.width <= geometry.notchRect.width)
        }
    }

    /// The lip below the cut-out is the only part of the closed shape the eye
    /// can see — everything above it is behind the camera housing.
    @Test("the closed shape is the cut-out plus the visible lip")
    func closedShapeIsTheCutOutPlusTheLip() throws {
        let geometry = try #require(Self.air.geometry)
        #expect(geometry.closedSize.width == geometry.notchRect.width)
        #expect(geometry.closedSize.height == geometry.notchRect.height + NotchGeometry.notchLip)
    }

    // MARK: - Panel size

    /// Room enough for what the panel wants, so it gets exactly that — no more.
    @Test("a roomy display gets the preferred panel")
    func roomyDisplayGetsThePreferredPanel() throws {
        for display in [Self.air, Self.pro] {
            let geometry = try #require(display.geometry)
            #expect(geometry.panelSize == NotchGeometry.preferredPanelSize)
        }
    }

    /// A Mac driving a small display is the case the constant would have got
    /// wrong: the panel takes the room that is there, minus the edge margin.
    @Test("a narrow display shrinks the panel to the room it has")
    func narrowDisplayShrinksThePanel() throws {
        let display = Display(
            frame: CGRect(x: 0, y: 0, width: 500, height: 400),
            leftStrip: 200,
            rightStrip: 200,
            menuBarHeight: 24
        )
        let geometry = try #require(display.geometry)

        #expect(geometry.panelSize.width == 500 - 2 * NotchGeometry.screenEdgeMargin)
        #expect(geometry.panelSize.width < NotchGeometry.preferredPanelSize.width)
        #expect(geometry.panelSize.width > NotchGeometry.minimumPanelWidth)
    }

    /// Below the minimum the panel stops shrinking: a panel narrower than this
    /// is not a smaller panel, it is an unreadable one. `windowFrame` deals with
    /// the overhang that follows.
    @Test("the panel never shrinks below the readable minimum")
    func panelNeverShrinksBelowTheMinimum() throws {
        let display = Display(
            frame: CGRect(x: 0, y: 0, width: 300, height: 400),
            leftStrip: 100,
            rightStrip: 120,
            menuBarHeight: 24
        )
        let geometry = try #require(display.geometry)

        #expect(geometry.panelSize.width == NotchGeometry.minimumPanelWidth)
        #expect(geometry.panelSize.width > geometry.screenFrame.width)
    }

    /// The same floor vertically, expressed against the closed shape: the panel
    /// may not open to less than it already occupies while shut.
    @Test("the panel is never shorter than the closed shape")
    func panelNeverShorterThanTheClosedShape() throws {
        let display = Display(
            frame: CGRect(x: 0, y: 0, width: 1470, height: 60),
            leftStrip: 645.5,
            rightStrip: 645.5,
            menuBarHeight: 24
        )
        let geometry = try #require(display.geometry)

        #expect(geometry.panelSize.height == geometry.closedSize.height)
    }

    /// `.none` stands in for "no display to speak of" while a live panel is torn
    /// down. Every size it reports has to stay finite and non-negative — a NaN
    /// or a negative here propagates into a SwiftUI frame and takes the view
    /// hierarchy with it.
    @Test("the empty geometry still reports usable sizes")
    func emptyGeometryReportsUsableSizes() {
        let geometry = NotchGeometry.none
        let sizes = [geometry.closedSize, geometry.panelSize, geometry.peekSize]

        for size in sizes {
            #expect(size.width.isFinite && size.width >= 0)
            #expect(size.height.isFinite && size.height >= 0)
        }
        #expect(geometry.panelSize == NotchGeometry.preferredPanelSize)
        #expect(geometry.maxTrayWidth >= 0)
    }

    // MARK: - Window frame

    /// The reason the panel is not simply centred on the screen. The cut-out and
    /// the screen centre differ by a point or so on a real machine, and the
    /// closed shape has to sit exactly over the cut-out or it stops being
    /// invisible — so the whole window is placed by the cut-out.
    @Test("the panel is centred on the cut-out, not on the screen")
    func panelIsCentredOnTheCutOut() throws {
        var display = Self.air
        display.leftStrip = 500
        display.rightStrip = 791
        let geometry = try #require(display.geometry)

        #expect(geometry.windowFrame.midX == geometry.notchRect.midX)
        #expect(geometry.windowFrame.midX != geometry.screenFrame.midX)
    }

    /// Centring wins until it would push the window off the display; then the
    /// edge wins. A cut-out this far off-centre is not what any Mac reports, but
    /// the clamp is what stands between an odd arrangement and a panel drawn
    /// half outside the screen.
    @Test("a cut-out near an edge does not drag the panel off the screen")
    func edgeClampKeepsThePanelOnScreen() throws {
        var display = Self.air
        display.leftStrip = 1290
        display.rightStrip = 1
        let geometry = try #require(display.geometry)

        #expect(geometry.windowFrame.maxX == geometry.screenFrame.maxX)
        #expect(geometry.windowFrame.minX >= geometry.screenFrame.minX)
    }

    /// When the panel is wider than the display there is no placement that fits.
    /// It starts at the left edge and overhangs to the right, rather than having
    /// its right edge clamped — which would push the origin off to the left and
    /// hide the beginning of every line in it.
    @Test("a panel wider than the display starts at the left edge")
    func tooWideAPanelStartsAtTheLeftEdge() throws {
        let display = Display(
            frame: CGRect(x: 120, y: 0, width: 300, height: 400),
            leftStrip: 100,
            rightStrip: 120,
            menuBarHeight: 24
        )
        let geometry = try #require(display.geometry)

        #expect(geometry.windowFrame.width > geometry.screenFrame.width)
        #expect(geometry.windowFrame.minX == geometry.screenFrame.minX)
    }

    /// The window hangs from the top of the screen and is exactly the panel plus
    /// the room its shadow needs.
    @Test("the window is pinned to the top and carries the shadow")
    func windowIsPinnedToTheTop() throws {
        let geometry = try #require(Self.air.geometry)

        #expect(geometry.windowFrame.maxY == geometry.screenFrame.maxY)
        #expect(geometry.windowFrame.width == geometry.panelSize.width)
        #expect(geometry.windowFrame.height == geometry.panelSize.height + NotchGeometry.shadowPadding)
    }

    // MARK: - Tray and peek

    /// The tray hangs below the menu bar, where the app owns the pixels, so it
    /// is bounded by the panel it grows into — and never by less than the closed
    /// shape it grows out of.
    @Test("the tray stays inside the panel and never below the closed shape")
    func trayStaysInsideThePanel() throws {
        let geometry = try #require(Self.air.geometry)
        #expect(geometry.maxTrayWidth == geometry.panelSize.width - 2 * NotchGeometry.trayInset)

        // A cut-out wider than the panel's inset outline: the closed shape wins,
        // because the tray may not be narrower than the shape it comes from.
        var wide = Self.air
        wide.leftStrip = 400
        wide.rightStrip = 400
        let wideGeometry = try #require(wide.geometry)
        #expect(wideGeometry.maxTrayWidth == wideGeometry.closedSize.width)
    }

    /// The peek appears uninvited, so it claims no more width than the panel.
    @Test("the peek is no wider than the panel")
    func peekIsNoWiderThanThePanel() throws {
        for display in [Self.air, Self.pro] {
            let geometry = try #require(display.geometry)
            #expect(geometry.peekSize.width == geometry.panelSize.width)
            #expect(geometry.peekSize.height > geometry.closedSize.height)
        }
    }
}
