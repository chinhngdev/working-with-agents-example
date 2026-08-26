import SwiftUI

/// Radius, shadow, and motion tokens. See `tokens/effects.css`.
public enum DSEffect {
    public static let radiusSm: CGFloat = 6
    public static let radiusMd: CGFloat = 8
    public static let radiusLg: CGFloat = 12
    public static let radiusPill: CGFloat = 999

    public static let durationFast: TimeInterval = 0.12
    public static let durationStandard: TimeInterval = 0.18

    public static let easeStandard: Animation = .timingCurve(0.2, 0.8, 0.2, 1, duration: durationStandard)
    public static let easeFast: Animation = .timingCurve(0.2, 0.8, 0.2, 1, duration: durationFast)
}
