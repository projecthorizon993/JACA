import SwiftUI

// MARK: - Color helper

extension Color {
    /// 0xRRGGBB
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Colors (names match the "Foundations" board in the design canvas)

enum CKColor {
    // Surfaces
    static let base               = Color(hex: 0x050505)            // app + capture zone
    static let control            = Color(hex: 0x262626)            // round buttons, MF/AF
    static let float              = Color(hex: 0x262626, opacity: 0.7) // tools over viewfinder
    static let chipFill           = Color(hex: 0x0F0F0F)
    static let modeKeyFill        = Color(hex: 0x1A1A1A)
    static let shutterCore        = Color(hex: 0x1C1B1A)
    static let shutterCorePressed = Color(hex: 0x2A2826)

    // Strokes
    static let ring        = Color(hex: 0x5A5A5A)
    static let ringPressed = Color(hex: 0x8A8A8A)
    static let strokeIdle  = Color(hex: 0x4D4D4D)

    // Accent
    static let marker     = Color(hex: 0xE8503E)   // ruler needle
    static let activeLine = Color(hex: 0xA03A2E)   // outline on engaged control
    static let activeFill = Color(hex: 0x1A1312)

    // Rulers
    static let tickMajor = Color(hex: 0xE8E8E8)
    static let tickMinor = Color(hex: 0xB5B5B5)

    // Text
    static let textPrimary   = Color(hex: 0xD6D6D6)
    static let textSecondary = Color(hex: 0x9A9A9A)
    static let labelRail     = Color(hex: 0xBDBDBD)

    // Overlays
    static let grid           = Color.white.opacity(0.7)
    static let peaking        = Color(hex: 0x7CF5D1)
    static let histogramPanel = Color(hex: 0x46382D, opacity: 0.72)
    static let histogramBar   = Color.white.opacity(0.85)

    // Status
    static let live = Color(hex: 0x5FD068)
}

// MARK: - Type
// The concept board uses Inter; on device use SF (system) which is visually equivalent.
// Tracking is applied at the call site with `.tracking(_:)`.

enum CKFont {
    static let value    = Font.system(size: 15, weight: .medium).monospacedDigit()
    static let railLabel = Font.system(size: 13, weight: .medium)       // tracking 0.4
    static let scale    = Font.system(size: 12, weight: .medium).monospacedDigit()
    static let button   = Font.system(size: 15, weight: .medium)
    static let chip     = Font.system(size: 14, weight: .medium)        // tracking 0.3
    static let caption  = Font.system(size: 14, weight: .medium)        // tracking 0.56
    static let glyph    = Font.system(size: 24, weight: .regular)
    static let badge    = Font.system(size: 15, weight: .bold)
    static let badgeSub = Font.system(size: 9, weight: .semibold)
}

// MARK: - Metrics (pt)

enum CKMetrics {
    static let shutterRing: CGFloat = 70
    static let shutterCore: CGFloat = 60
    static let round: CGFloat = 40
    static let compact: CGFloat = 36
    static let hit: CGFloat = 44               // minimum tap target
    static let chip = CGSize(width: 54, height: 28)
    static let chipRadius: CGFloat = 6
    static let modeKey = CGSize(width: 54, height: 53)
    static let thumbnail = CGSize(width: 87, height: 88)
    static let edge: CGFloat = 8
    static let viewfinderRadius: CGFloat = 8
    static let tickSpacingExposure: CGFloat = 16
    static let tickSpacingFocus: CGFloat = 10
}

// MARK: - Corner shapes

enum CKShape {
    /// Mode key: large top-trailing radius.
    static let modeKey = UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 8,
                                                bottomTrailingRadius: 14, topTrailingRadius: 28,
                                                style: .continuous)
    /// Gallery thumbnail: large bottom-leading radius (mirror of the mode key).
    static let thumbnail = UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 28,
                                                  bottomTrailingRadius: 14, topTrailingRadius: 14,
                                                  style: .continuous)
}
