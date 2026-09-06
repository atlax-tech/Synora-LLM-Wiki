import Foundation
import Testing

@testable import SynoraDesignSystem

struct DesignTokenTests {
  @Test
  func semanticColorsMatchDesignContract() {
    #expect(
      SynoraSemanticColor.inkPrimary
        == SynoraColorToken(red: 0x15 / 255, green: 0x1A / 255, blue: 0x2D / 255))
    #expect(
      SynoraSemanticColor.inkSecondary
        == SynoraColorToken(red: 0x68 / 255, green: 0x70 / 255, blue: 0x83 / 255))
    #expect(SynoraSemanticColor.canvas == SynoraColorToken(red: 1, green: 1, blue: 1))
    #expect(
      SynoraSemanticColor.accentPrimary
        == SynoraColorToken(red: 0x5C / 255, green: 0x75 / 255, blue: 0xE7 / 255))
  }

  @Test
  func informativeTextMeetsContrastRequirement() {
    let bodyContrast = contrast(SynoraSemanticColor.inkPrimary, SynoraSemanticColor.canvas)
    let secondaryContrast = contrast(SynoraSemanticColor.inkSecondary, SynoraSemanticColor.canvas)
    #expect(bodyContrast >= 4.5)
    #expect(secondaryContrast >= 4.5)
  }

  @Test
  func tertiaryTextIsNotAnInformativeColor() {
    let tertiaryContrast = contrast(SynoraSemanticColor.inkTertiary, SynoraSemanticColor.canvas)
    #expect(tertiaryContrast < 4.5)
  }

  @Test
  func reducingMotionRemovesAnimationDuration() {
    #expect(SynoraMotion.hover.duration(reducingMotion: false) == 0.12)
    #expect(SynoraMotion.hover.duration(reducingMotion: true) == 0)
    #expect(SynoraMotion.collapse.duration(reducingMotion: true) == 0)
  }

  @Test
  func typographyAndSpacingStayWithinContract() {
    #expect(SynoraTypography.body.size == 12.5)
    #expect(SynoraTypography.body.lineHeight == 1.78)
    #expect(SynoraSpacing.xxs == 4)
    #expect(SynoraSpacing.xxxl == 32)
    #expect(SynoraRadius.inspectorCard == 10)
  }

  private func contrast(_ foreground: SynoraColorToken, _ background: SynoraColorToken) -> Double {
    let foregroundLuminance = luminance(foreground)
    let backgroundLuminance = luminance(background)
    let lighter = max(foregroundLuminance, backgroundLuminance)
    let darker = min(foregroundLuminance, backgroundLuminance)
    return (lighter + 0.05) / (darker + 0.05)
  }

  private func luminance(_ color: SynoraColorToken) -> Double {
    func linear(_ component: Double) -> Double {
      component <= 0.03928 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }

    return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
  }
}
