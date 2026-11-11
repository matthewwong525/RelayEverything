import SwiftUI

// Relay Everything's dark colors and type on the watch, which is always dark. The hex values copy BrandColors.dark in
// lib/brand.dart; the amber spark matches the phone's voice-note ring.

enum WatchBrand {
  static let paper = rgb(0x0C110F)
  static let card = rgb(0x161D1A)
  static let ink = rgb(0xECF3EE)
  static let muted = rgb(0x9AA8A0)
  static let spark = rgb(0xFFC24D)
  static let onSpark = rgb(0x121614)

  // The font's own names are InterVariable and its named instances, not Inter: a wrong name falls back silently.
  static let body = Font.custom("InterVariable", size: 16, relativeTo: .body)
  static let title = Font.custom("InterVariable-SemiBold", size: 18, relativeTo: .headline)
  static let small = Font.custom("InterVariable", size: 13, relativeTo: .footnote)
  static let smallest = Font.custom("InterVariable", size: 12, relativeTo: .caption2)

  private static func rgb(_ hex: UInt32) -> Color {
    Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
  }
}
