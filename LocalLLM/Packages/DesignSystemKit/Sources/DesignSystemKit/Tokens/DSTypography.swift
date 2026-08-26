import SwiftUI

/// Typography scale for the LocalLLM design system. See `tokens/typography.css`.
///
/// Native platform stacks only — `.system(...)` resolves to SF Pro (UI/Display)
/// and SF Mono (monospaced) on both macOS and iOS, matching what ships.
public enum DSTypography {
    public static let text2xl = Font.system(size: 28, weight: .semibold, design: .default)
    public static let textXl = Font.system(size: 22, weight: .semibold, design: .default)
    public static let textLg = Font.system(size: 17, weight: .medium, design: .default)
    public static let textMd = Font.system(size: 15, weight: .regular, design: .default)
    public static let textSm = Font.system(size: 13, weight: .regular, design: .default)
    public static let textXs = Font.system(size: 11, weight: .medium, design: .default)

    public static let textMonoMd = Font.system(size: 13, weight: .regular, design: .monospaced)
    public static let textMonoSm = Font.system(size: 12, weight: .regular, design: .monospaced)

    public static let trackingLabel: CGFloat = 0.02
}
