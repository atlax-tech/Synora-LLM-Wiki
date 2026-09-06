import SwiftUI

public struct SynoraDesignSystemPreview: View {
  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: SynoraSpacing.md) {
      Text("Synora Wiki")
        .font(SynoraTypography.documentTitle.font)
        .foregroundStyle(SynoraSemanticColor.inkPrimary.color)

      Text("Design system preview")
        .font(SynoraTypography.body.font)
        .foregroundStyle(SynoraSemanticColor.inkSecondary.color)

      HStack(spacing: SynoraSpacing.sm) {
        Circle().fill(SynoraSemanticColor.accentPrimary.color).frame(width: 24, height: 24)
        Circle().fill(SynoraSemanticColor.aiPrimary.color).frame(width: 24, height: 24)
        Circle().fill(SynoraSemanticColor.journalHighlight.color).frame(width: 24, height: 24)
      }
    }
    .padding(SynoraSpacing.xl)
    .background(SynoraSemanticColor.canvas.color)
  }
}
