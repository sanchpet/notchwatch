// NotchSizing.swift
// Sizing constants for the notch UI. Anything that depends on the display is
// derived from the screen instead — see NotchGeometry.

import SwiftUI

// MARK: - Fixed Sizes

// The shadow padding around the window lives with the frame it is part of —
// `NotchGeometry.shadowPadding` — because `windowFrame` is the only thing that
// ever needed it, and a second copy here is a second number to keep in step.

/// Extra bottom spacing to allow the closed-state glow to render fully
let closedNotchGlowPadding: CGFloat = 24

/// Corner radius for open/closed states
let cornerRadiusInsets = (
    opened: (top: CGFloat(19), bottom: CGFloat(24)),
    closed: (top: CGFloat(6), bottom: CGFloat(14))
)
