import SwiftUI

// VitalLine brand palette. Change a value here and the whole app updates.
extension Color {
    static let midnight     = Color(hex: 0x0B1220)   // screen background
    static let surface      = Color(hex: 0x172338)   // cards / panels
    static let brandPrimary = Color(hex: 0x20D6E8)   // routes / actions
    static let success      = Color(hex: 0x22C55E)   // Verified
    static let caution      = Color(hex: 0xF5B544)   // alerts, road work, hazards
    static let critical     = Color(hex: 0xF15B62)   // blocked / issue, elevator out
    static let textPrimary  = Color(hex: 0xF8FAFC)   // primary text
    static let textSecondary = Color(hex: 0xF8FAFC, opacity: 0.65) // captions, sources

    // Older names from the first Theme.swift, kept so nothing breaks.
    static let brand     = brandPrimary
    static let alert     = critical
    static let warning   = caution
    static let synthetic = caution
    static let cardBackground   = surface
    static let screenBackground = midnight

    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// Short form for modifiers: .foregroundStyle(.textSecondary), .tint(.critical)
extension ShapeStyle where Self == Color {
    static var midnight: Color { Color.midnight }
    static var surface: Color { Color.surface }
    static var brandPrimary: Color { Color.brandPrimary }
    static var success: Color { Color.success }
    static var caution: Color { Color.caution }
    static var critical: Color { Color.critical }
    static var textPrimary: Color { Color.textPrimary }
    static var textSecondary: Color { Color.textSecondary }
    static var brand: Color { Color.brand }
    static var alert: Color { Color.alert }
    static var warning: Color { Color.warning }
    static var synthetic: Color { Color.synthetic }
    static var cardBackground: Color { Color.cardBackground }
    static var screenBackground: Color { Color.screenBackground }
}
