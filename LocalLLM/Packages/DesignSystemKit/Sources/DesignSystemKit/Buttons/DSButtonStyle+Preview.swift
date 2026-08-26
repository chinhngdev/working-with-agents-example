import SwiftUI

#Preview("DSButtonStyle") {
    HStack(spacing: DSSpacing.space3) {
        Button("Check grammar") {}
            .buttonStyle(.ds(.primary))
        Button("Cancel") {}
            .buttonStyle(.ds(.secondary))
        Button("Skip") {}
            .buttonStyle(.ds(.ghost))
        Button("Unload model") {}
            .buttonStyle(.ds(.destructive))
        Button("New chat") {}
            .buttonStyle(.ds(.primary, size: .sm))
        Button("Loading…") {}
            .buttonStyle(.ds(.primary))
            .disabled(true)
    }
    .padding(DSSpacing.space5)
    .background(DSColor.bgPage)
}
