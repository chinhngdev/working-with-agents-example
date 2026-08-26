import SwiftUI

/// Color tokens for the LocalLLM design system.
///
/// Palette: warm off-white/paper neutrals (not cold gray), one teal accent
/// ("local signal" — on-device/private), amber for progress/streak feedback,
/// red reserved for destructive/error. See design system `tokens/colors.css`.
public enum DSColor {
    // Base neutrals
    public static let gray000 = Color(hex: 0xFAF9F7)
    public static let gray050 = Color(hex: 0xF3F1EE)
    public static let gray100 = Color(hex: 0xE8E5E1)
    public static let gray200 = Color(hex: 0xD6D2CC)
    public static let gray300 = Color(hex: 0xB8B3AC)
    public static let gray500 = Color(hex: 0x7A756E)
    public static let gray700 = Color(hex: 0x4A4640)
    public static let gray800 = Color(hex: 0x302D29)
    public static let gray900 = Color(hex: 0x1B1917)
    public static let white = Color.white

    // Accent — teal
    public static let teal100 = Color(hex: 0xDCEEE8)
    public static let teal300 = Color(hex: 0x8FC9B9)
    public static let teal500 = Color(hex: 0x2F8F76)
    public static let teal600 = Color(hex: 0x1F7560)
    public static let teal700 = Color(hex: 0x155C4B)

    // Secondary — amber
    public static let amber100 = Color(hex: 0xF6E7CB)
    public static let amber500 = Color(hex: 0xC6862A)
    public static let amber600 = Color(hex: 0xA66E1E)

    // Semantic danger
    public static let red100 = Color(hex: 0xF3DFD9)
    public static let red500 = Color(hex: 0xB8452F)

    // Semantic aliases — use these in components, not raw scales
    public static let bgPage = gray000
    public static let bgSurface = white
    public static let bgSunken = gray050
    public static let bgInverse = gray900

    public static let borderHairline = gray900.opacity(0.10)
    public static let borderStrong = gray900.opacity(0.20)

    public static let textPrimary = gray900
    public static let textSecondary = gray700
    public static let textTertiary = gray500
    public static let textOnAccent = white
    public static let textOnInverse = gray050

    public static let accent = teal600
    public static let accentHover = teal700
    public static let accentTint = teal100
    public static let accentText = teal700

    public static let progress = amber500
    public static let progressTint = amber100
    public static let progressText = amber600

    public static let danger = red500
    public static let dangerTint = red100

    public static let focusRing = teal500
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
