import SwiftUI

/// Action button variants used across the app — menu-bar-style commands
/// (New Conversation, Check Grammar) and in-view actions.
///
/// - `primary`: teal fill, main CTA
/// - `secondary`: outlined, default action
/// - `ghost`: no fill, toolbar/inline
/// - `destructive`: red fill, delete/unload model
public enum DSButtonVariant {
    case primary
    case secondary
    case ghost
    case destructive
}

/// `sm` for toolbars/dense rows, `md` for standard forms.
public enum DSButtonSize {
    case sm
    case md

    var horizontalPadding: CGFloat {
        switch self {
        case .sm: 10
        case .md: 14
        }
    }

    var verticalPadding: CGFloat {
        switch self {
        case .sm: 5
        case .md: 7
        }
    }

    var font: Font {
        switch self {
        case .sm: DSTypography.textSm
        case .md: DSTypography.textMd
        }
    }

    var radius: CGFloat {
        switch self {
        case .sm: DSEffect.radiusSm
        case .md: DSEffect.radiusMd
        }
    }
}

public struct DSButtonStyle: ButtonStyle {
    let variant: DSButtonVariant
    let size: DSButtonSize

    public init(variant: DSButtonVariant = .primary, size: DSButtonSize = .md) {
        self.variant = variant
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        DSButtonBody(configuration: configuration, variant: variant, size: size)
    }

    private struct DSButtonBody: View {
        @Environment(\.isEnabled) private var isEnabled
        let configuration: Configuration
        let variant: DSButtonVariant
        let size: DSButtonSize

        var body: some View {
            configuration.label
                .font(size.font)
                .fontWeight(.medium)
                .foregroundStyle(foreground)
                .padding(.horizontal, size.horizontalPadding)
                .padding(.vertical, size.verticalPadding)
                .background(
                    RoundedRectangle(cornerRadius: size.radius, style: .continuous)
                        .fill(background)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size.radius, style: .continuous)
                        .strokeBorder(border, lineWidth: 1)
                )
                .opacity(isEnabled ? 1 : 0.45)
                .animation(DSEffect.easeFast, value: configuration.isPressed)
        }

        private var background: Color {
            switch variant {
            case .primary:
                configuration.isPressed ? DSColor.accentHover : DSColor.accent
            case .secondary:
                DSColor.bgSurface
            case .ghost:
                configuration.isPressed ? DSColor.bgSunken : .clear
            case .destructive:
                configuration.isPressed ? DSColor.red500.opacity(0.85) : DSColor.danger
            }
        }

        private var foreground: Color {
            switch variant {
            case .primary: DSColor.textOnAccent
            case .secondary: DSColor.textPrimary
            case .ghost: DSColor.textPrimary
            case .destructive: DSColor.white
            }
        }

        private var border: Color {
            switch variant {
            case .secondary: DSColor.borderStrong
            case .primary, .ghost, .destructive: .clear
            }
        }
    }
}

extension ButtonStyle where Self == DSButtonStyle {
    public static func ds(_ variant: DSButtonVariant = .primary, size: DSButtonSize = .md) -> DSButtonStyle {
        DSButtonStyle(variant: variant, size: size)
    }
}
