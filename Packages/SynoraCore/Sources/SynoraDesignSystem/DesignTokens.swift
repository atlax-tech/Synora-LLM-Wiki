import SwiftUI

public struct SynoraColorToken: Equatable, Sendable {
  public let red: Double
  public let green: Double
  public let blue: Double
  public let alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  public var color: Color {
    Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
  }
}

public enum SynoraSemanticColor {
  public static let inkPrimary = SynoraColorToken(
    red: 0x15 / 255, green: 0x1A / 255, blue: 0x2D / 255)
  public static let inkSecondary = SynoraColorToken(
    red: 0x68 / 255, green: 0x70 / 255, blue: 0x83 / 255)
  public static let inkTertiary = SynoraColorToken(
    red: 0x96 / 255, green: 0x9C / 255, blue: 0xAB / 255)
  public static let canvas = SynoraColorToken(red: 1, green: 1, blue: 1)
  public static let sidebar = SynoraColorToken(red: 0xF4 / 255, green: 0xF5 / 255, blue: 0xF7 / 255)
  public static let list = SynoraColorToken(red: 0xFB / 255, green: 0xFB / 255, blue: 0xFC / 255)
  public static let inspector = SynoraColorToken(
    red: 0xF7 / 255, green: 0xF8 / 255, blue: 0xFA / 255)
  public static let borderSubtle = SynoraColorToken(
    red: 0xE8 / 255, green: 0xEA / 255, blue: 0xF0 / 255)
  public static let accentPrimary = SynoraColorToken(
    red: 0x5C / 255, green: 0x75 / 255, blue: 0xE7 / 255)
  public static let accentText = SynoraColorToken(
    red: 0x52 / 255, green: 0x68 / 255, blue: 0xC8 / 255)
  public static let accentSoft = SynoraColorToken(red: 0xEA / 255, green: 0xF0 / 255, blue: 1)
  public static let aiPrimary = SynoraColorToken(
    red: 0x76 / 255, green: 0x69 / 255, blue: 0xEF / 255)
  public static let journalHighlight = SynoraColorToken(
    red: 0xEF / 255, green: 0x7F / 255, blue: 0xB4 / 255)
  public static let warningInline = SynoraColorToken(
    red: 0xF3 / 255, green: 0xA5 / 255, blue: 0x1D / 255)
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
