import AppKit
import SwiftUI

public struct SynoraColorToken: Equatable, Sendable {
  public let red: Double
  public let green: Double
  public let blue: Double
  public let alpha: Double
  private let darkRed: Double?
  private let darkGreen: Double?
  private let darkBlue: Double?
  private let darkAlpha: Double?

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
    darkRed = nil
    darkGreen = nil
    darkBlue = nil
    darkAlpha = nil
  }

  fileprivate init(light: SynoraColorToken, dark: SynoraColorToken) {
    red = light.red
    green = light.green
    blue = light.blue
    alpha = light.alpha
    darkRed = dark.red
    darkGreen = dark.green
    darkBlue = dark.blue
    darkAlpha = dark.alpha
  }

  public static func == (lhs: SynoraColorToken, rhs: SynoraColorToken) -> Bool {
    lhs.red == rhs.red
      && lhs.green == rhs.green
      && lhs.blue == rhs.blue
      && lhs.alpha == rhs.alpha
  }

  public var color: Color {
    let token = self
    return Color(
      nsColor: NSColor(name: nil) { appearance in
        token.resolved(for: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
          .nsColor
      }
    )
  }

  public func resolved(for colorScheme: ColorScheme) -> SynoraColorToken {
    resolved(for: colorScheme == .dark)
  }

  private func resolved(for dark: Bool) -> SynoraColorToken {
    guard
      dark,
      let darkRed,
      let darkGreen,
      let darkBlue,
      let darkAlpha
    else {
      return SynoraColorToken(red: red, green: green, blue: blue, alpha: alpha)
    }

    return SynoraColorToken(
      red: darkRed,
      green: darkGreen,
      blue: darkBlue,
      alpha: darkAlpha
    )
  }

  private var nsColor: NSColor {
    NSColor(
      srgbRed: red,
      green: green,
      blue: blue,
      alpha: alpha
    )
  }
}

private func adaptiveColor(
  light: (Double, Double, Double),
  dark: (Double, Double, Double),
  alpha: Double = 1
) -> SynoraColorToken {
  SynoraColorToken(
    light: SynoraColorToken(red: light.0, green: light.1, blue: light.2, alpha: alpha),
    dark: SynoraColorToken(red: dark.0, green: dark.1, blue: dark.2, alpha: alpha)
  )
}

public enum SynoraSemanticColor {
  public static let inkPrimary = adaptiveColor(
    light: (0x15 / 255, 0x1A / 255, 0x2D / 255),
    dark: (0xF2 / 255, 0xF2 / 255, 0xF7 / 255)
  )
  public static let inkSecondary = adaptiveColor(
    light: (0x68 / 255, 0x70 / 255, 0x83 / 255),
    dark: (0xAE / 255, 0xAE / 255, 0xB2 / 255)
  )
  public static let inkTertiary = adaptiveColor(
    light: (0x96 / 255, 0x9C / 255, 0xAB / 255),
    dark: (0x8E / 255, 0x8E / 255, 0x93 / 255)
  )
  public static let canvas = adaptiveColor(
    light: (1, 1, 1),
    dark: (0x1C / 255, 0x1C / 255, 0x1E / 255)
  )
  public static let sidebar = adaptiveColor(
    light: (0xF4 / 255, 0xF5 / 255, 0xF7 / 255),
    dark: (0x24 / 255, 0x24 / 255, 0x26 / 255)
  )
  public static let list = adaptiveColor(
    light: (0xFB / 255, 0xFB / 255, 0xFC / 255),
    dark: (0x1E / 255, 0x1E / 255, 0x20 / 255)
  )
  public static let inspector = adaptiveColor(
    light: (0xF7 / 255, 0xF8 / 255, 0xFA / 255),
    dark: (0x24 / 255, 0x24 / 255, 0x26 / 255)
  )
  public static let borderSubtle = adaptiveColor(
    light: (0xE8 / 255, 0xEA / 255, 0xF0 / 255),
    dark: (0x38 / 255, 0x38 / 255, 0x3A / 255)
  )
  public static let accentPrimary = adaptiveColor(
    light: (0x5C / 255, 0x75 / 255, 0xE7 / 255),
    dark: (0x8E / 255, 0xA2 / 255, 1)
  )
  public static let accentText = adaptiveColor(
    light: (0x52 / 255, 0x68 / 255, 0xC8 / 255),
    dark: (0xA8 / 255, 0xB7 / 255, 1)
  )
  public static let accentSoft = adaptiveColor(
    light: (0xEA / 255, 0xF0 / 255, 1),
    dark: (0x2B / 255, 0x35 / 255, 0x59 / 255)
  )
  public static let aiPrimary = adaptiveColor(
    light: (0x76 / 255, 0x69 / 255, 0xEF / 255),
    dark: (0x9B / 255, 0x90 / 255, 1)
  )
  public static let journalHighlight = adaptiveColor(
    light: (0xEF / 255, 0x7F / 255, 0xB4 / 255),
    dark: (0xF0 / 255, 0x96 / 255, 0xC1 / 255)
  )
  public static let warningInline = adaptiveColor(
    light: (0xF3 / 255, 0xA5 / 255, 0x1D / 255),
    dark: (0xF5 / 255, 0xB9 / 255, 0x4D / 255)
  )
}

public enum SynoraFontWeight: String, Equatable, Sendable {
  case regular
  case medium
  case semibold
  case bold

  fileprivate var swiftUIWeight: Font.Weight {
    switch self {
    case .regular: .regular
    case .medium: .medium
    case .semibold: .semibold
    case .bold: .bold
    }
  }
}

public struct SynoraTypographyToken: Equatable, Sendable {
  public let size: Double
  public let lineHeight: Double
  public let weight: SynoraFontWeight

  public init(size: Double, lineHeight: Double, weight: SynoraFontWeight) {
    self.size = size
    self.lineHeight = lineHeight
    self.weight = weight
  }

  public var font: Font {
    Font.system(size: size, weight: weight.swiftUIWeight)
  }
}

public enum SynoraTypography {
  public static let documentTitle = SynoraTypographyToken(size: 29, lineHeight: 1.2, weight: .bold)
  public static let sectionTitle = SynoraTypographyToken(
    size: 16, lineHeight: 1.3, weight: .semibold)
  public static let body = SynoraTypographyToken(size: 12.5, lineHeight: 1.78, weight: .regular)
  public static let quote = SynoraTypographyToken(size: 13, lineHeight: 1.55, weight: .regular)
  public static let listTitle = SynoraTypographyToken(
    size: 12.5, lineHeight: 1.25, weight: .semibold)
  public static let navigation = SynoraTypographyToken(
    size: 12.5, lineHeight: 1.3, weight: .regular)
  public static let metadata = SynoraTypographyToken(
    size: 10.25, lineHeight: 1.35, weight: .regular)
  public static let sectionLabel = SynoraTypographyToken(size: 11, lineHeight: 1.3, weight: .medium)
}

public enum SynoraSpacing {
  public static let xxs = 4.0
  public static let xs = 8.0
  public static let sm = 12.0
  public static let md = 16.0
  public static let lg = 20.0
  public static let xl = 24.0
  public static let xxl = 28.0
  public static let xxxl = 32.0
}

public enum SynoraRadius {
  public static let control = 7.0
  public static let selection = 8.0
  public static let inspectorCard = 10.0
  public static let floatingControl = 11.0
}

public struct SynoraMotionToken: Equatable, Sendable {
  public let seconds: Double

  public init(seconds: Double) {
    self.seconds = seconds
  }

  public func duration(reducingMotion: Bool) -> Double {
    reducingMotion ? 0 : seconds
  }
}

public enum SynoraMotion {
  public static let hover = SynoraMotionToken(seconds: 0.12)
  public static let collapse = SynoraMotionToken(seconds: 0.18)
  public static let inspector = SynoraMotionToken(seconds: 0.19)
}
