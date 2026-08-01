import SwiftUI

struct NotchGlowBorder: View {
    let topCornerRadius: CGFloat
    let bottomCornerRadius: CGFloat
    let glowColor: Color
    let brightColor: Color
    /// Weight of the traced edge. The default suits the activity glow, which is
    /// ambient and running most of the time; a signal that has to be noticed
    /// rather than merely seen is given a heavier one.
    var lineWidth: CGFloat = 2.5
    /// Multiplies the halo. Same reasoning as `lineWidth`: the outer bloom is
    /// what makes the border legible in peripheral vision, where the stroke
    /// itself is too fine to register.
    var glowStrength: CGFloat = 1.0
    /// Draw the whole edge at once instead of sweeping a highlight around it.
    ///
    /// The sweeping gradient leaves 40% of the circle fully transparent and
    /// gives full colour to a narrow arc, so at any instant most of the border
    /// is not there. That reads as motion, which is the right way to say "work
    /// is happening" and the wrong way to say "this is waiting for you" — a
    /// standing state wants a standing outline. It also stops the animation:
    /// waiting can last for as long as the user is away, and a signal that means
    /// "come back" should not cost frames while nobody is looking.
    var isSteady: Bool = false

    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var powerMonitor = PowerStateMonitor.shared

    // Battery saver: 15 FPS on battery, 25 FPS when charging or disabled
    private var frameInterval: Double {
        if settings.batterySaverEnabled, !powerMonitor.isCharging {
            return 1.0 / 15.0 // 15 FPS on battery
        }
        return 1.0 / 25.0 // 25 FPS when charging or battery saver off
    }

    var body: some View {
        if isSteady {
            steadyBorder
        } else {
            sweepingBorder
        }
    }

    private var steadyBorder: some View {
        NotchShape(topCornerRadius: topCornerRadius, bottomCornerRadius: bottomCornerRadius)
            .stroke(
                LinearGradient(
                    colors: [brightColor, glowColor, brightColor],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                lineWidth: lineWidth
            )
            .shadow(color: glowColor.opacity(0.9), radius: 6 * glowStrength)
            .shadow(color: glowColor.opacity(0.6), radius: 14 * glowStrength)
            .shadow(color: glowColor.opacity(0.35), radius: 26 * glowStrength)
            .shadow(color: glowColor.opacity(0.2), radius: 40 * glowStrength)
            .mask(
                VStack(spacing: 0) {
                    Color.clear.frame(height: 4)
                    Color.white
                }
            )
            .allowsHitTesting(false)
    }

    private var sweepingBorder: some View {
        TimelineView(.animation(minimumInterval: frameInterval)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            let rotation = (time.truncatingRemainder(dividingBy: 2.0)) / 2.0 * 360

            NotchShape(
                topCornerRadius: topCornerRadius,
                bottomCornerRadius: bottomCornerRadius
            )
            .stroke(
                AngularGradient(
                    stops: [
                        .init(color: Color.clear, location: 0.0),
                        .init(color: glowColor.opacity(0.3), location: 0.1),
                        .init(color: glowColor, location: 0.2),
                        .init(color: brightColor, location: 0.3),
                        .init(color: glowColor, location: 0.4),
                        .init(color: glowColor.opacity(0.3), location: 0.5),
                        .init(color: Color.clear, location: 0.6),
                        .init(color: Color.clear, location: 1.0),
                    ],
                    center: .center,
                    startAngle: .degrees(rotation),
                    endAngle: .degrees(rotation + 360)
                ),
                lineWidth: lineWidth
            )
            .shadow(color: glowColor.opacity(0.7 * glowStrength), radius: 8 * glowStrength)
            .shadow(color: glowColor.opacity(0.4 * glowStrength), radius: 16 * glowStrength)
            .shadow(color: glowColor.opacity(0.2 * glowStrength), radius: 24 * glowStrength)
            .mask(
                VStack(spacing: 0) {
                    Color.clear.frame(height: 4)
                    Color.white
                }
            )
        }
        .allowsHitTesting(false)
    }
}
