// NotchGeometry+Screen.swift
// The one thing about the cut-out that only AppKit can answer: which display has
// one, and how wide it is. The arithmetic over those numbers is NotchwatchKit's.

import AppKit
import NotchwatchKit

extension NotchGeometry {
    /// Geometry of the screen that carries a cut-out, or `nil` when none of the
    /// attached displays has one — an external monitor, or any Mac built before
    /// the notch. There is no panel in that case: the app lives in the menu bar.
    ///
    /// `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` are the two menu bar
    /// strips beside the cut-out, which makes whatever lies between them the
    /// cut-out itself, and `safeAreaInsets.top` is the height the menu bar was
    /// grown to in order to clear it. Reading those four numbers is all this
    /// does — what they mean, and every size derived from them, is decided in
    /// the kit, where it can be tested on a machine that has no notch.
    static func resolve() -> NotchGeometry? {
        guard let screen = notchedScreen(),
              let leftStrip = screen.auxiliaryTopLeftArea,
              let rightStrip = screen.auxiliaryTopRightArea else { return nil }

        return resolve(
            screenFrame: screen.frame,
            leftStripWidth: leftStrip.width,
            rightStripWidth: rightStrip.width,
            menuBarHeight: screen.safeAreaInsets.top
        )
    }

    /// The built-in display, identified by the fact that it has a cut-out rather
    /// than by `NSScreen.main`: `main` follows the key window, and an accessory
    /// app never owns one, so it can just as well point at an external monitor.
    private static func notchedScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }
    }
}
