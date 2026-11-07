import SwiftUI
import UIKit

// Relay Everything's colors and type for the share card. The hex values copy BrandColors in lib/brand.dart, and
// test/brand_test.dart fails, naming the token, when one differs.

enum Brand {
  static let paper = color(light: 0xF7F8F4, dark: 0x0C110F)
  static let card = color(light: 0xFFFFFF, dark: 0x161D1A)
  static let line = color(light: 0xE3E6DF, dark: 0x26302B)
  static let ink = color(light: 0x121614, dark: 0xECF3EE)
  static let muted = color(light: 0x5E6660, dark: 0x9AA8A0)
  static let accent = color(light: 0x0E7A5A, dark: 0x4CC79A)
  static let onAccent = color(light: 0xFFFFFF, dark: 0x06281A)
  static let accentText = color(light: 0x0E7A5A, dark: 0x4CC79A)
  static let accentSoft = color(light: 0xE1F2EA, dark: 0x133328)
  static let spark = color(light: 0xF5A524, dark: 0xFFC24D)
  static let onSpark = color(light: 0x121614, dark: 0x121614)
  static let danger = color(light: 0xC9302C, dark: 0xFF8A80)
  static let onDanger = color(light: 0xFFFFFF, dark: 0x0C110F)

  // The font's own names are InterVariable and its named instances, not Inter: a wrong name falls back silently.
  static let body = Font.custom("InterVariable", size: 16, relativeTo: .body)
  static let title = Font.custom("InterVariable-SemiBold", size: 17, relativeTo: .headline)
  static let small = Font.custom("InterVariable", size: 13, relativeTo: .footnote)

  /// Corners: 12 on buttons and fields, 16 on cards.
  static let fieldCorners: CGFloat = 12
  static let cardCorners: CGFloat = 16

  private static func color(light: UInt32, dark: UInt32) -> UIColor {
    UIColor(dynamicProvider: { $0.userInterfaceStyle == .dark ? rgb(dark) : rgb(light) })
  }

  private static func rgb(_ hex: UInt32) -> UIColor {
    UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
  }
}

/// The one main action: an accent fill with on-accent text, quiet line and muted while it can not run.
struct BrandFilledButton: ButtonStyle {
  @Environment(\.isEnabled) private var enabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(Brand.title)
      .foregroundColor(Color(enabled ? Brand.onAccent : Brand.muted))
      .padding(.horizontal, 16).padding(.vertical, 8)
      .background(Color(enabled ? Brand.accent : Brand.line), in: RoundedRectangle(cornerRadius: Brand.fieldCorners))
      .opacity(configuration.isPressed ? 0.8 : 1)
  }
}
