import SwiftUI

// MARK: - Shutter

/// 70 pt ring + 60 pt core. Pressed: ring lightens, core shrinks to 54.
/// On tap: a short keyframe "squeeze" + medium haptic.
struct ShutterButton: View {
    var caption: String = "SET"
    var action: () -> Void
    @State private var taps = 0

    var body: some View {
        VStack(spacing: 6) {
            Button {
                taps += 1
                action()
            } label: {
                Color.clear.frame(width: CKMetrics.shutterRing, height: CKMetrics.shutterRing)
            }
            .buttonStyle(ShutterStyle(trigger: taps))
            .accessibilityLabel("Shutter")

            Text(caption)
                .font(CKFont.caption).tracking(0.56)
                .foregroundStyle(CKColor.textSecondary)
        }
    }
}

struct ShutterStyle: ButtonStyle {
    let trigger: Int

    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        return ZStack {
            Circle().strokeBorder(pressed ? CKColor.ringPressed : CKColor.ring, lineWidth: 2)
            Circle()
                .fill(pressed ? CKColor.shutterCorePressed : CKColor.shutterCore)
                .padding((CKMetrics.shutterRing - CKMetrics.shutterCore) / 2)
                .scaleEffect(pressed ? 0.9 : 1)       // 60 -> 54
        }
        .frame(width: CKMetrics.shutterRing, height: CKMetrics.shutterRing)
        .animation(CKMotion.press, value: pressed)
        .keyframeAnimator(initialValue: 1.0, trigger: trigger) { content, scale in
            content.scaleEffect(scale)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(0.94, duration: 0.08)
                CubicKeyframe(1.03, duration: 0.14)
                CubicKeyframe(1.00, duration: 0.20)
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: trigger)
        .contentShape(Circle())
    }
}

// MARK: - Round button (zoom, flip, tools, MF, AF, macro)

struct RoundButton<Label: View>: View {
    enum Style { case solid, float }

    var size: CGFloat = CKMetrics.round
    var style: Style = .solid
    var isSelected = false
    var a11y: String
    var action: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: size, height: size)
                .background(Circle().fill(isSelected ? CKColor.activeFill
                                           : (style == .solid ? CKColor.control : CKColor.float)))
                .overlay(Circle().strokeBorder(isSelected ? CKColor.activeLine : .clear, lineWidth: 1))
                // Visual is 36–40 pt, hit area is 44 pt.
                .contentShape(Circle().inset(by: -max(0, (CKMetrics.hit - size) / 2)))
        }
        .buttonStyle(PressScaleStyle())
        .animation(CKMotion.select, value: isSelected)
        .accessibilityLabel(a11y)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension RoundButton where Label == Text {
    init(_ text: String, size: CGFloat = CKMetrics.round, style: Style = .solid,
         isSelected: Bool = false, a11y: String? = nil, action: @escaping () -> Void) {
        self.size = size
        self.style = style
        self.isSelected = isSelected
        self.a11y = a11y ?? text
        self.action = action
        self.label = {
            Text(text)
                .font(size < 40 ? Font.system(size: 13, weight: .medium) : CKFont.button)
                .foregroundStyle(isSelected ? CKColor.textPrimary : CKColor.labelRail)
                .contentTransition(.interpolate)
        }
    }
}

extension RoundButton where Label == Image {
    init(symbol: String, size: CGFloat = CKMetrics.round, style: Style = .solid,
         isSelected: Bool = false, a11y: String, action: @escaping () -> Void) {
        self.size = size
        self.style = style
        self.isSelected = isSelected
        self.a11y = a11y
        self.action = action
        self.label = { Image(systemName: symbol) }
    }
}

// MARK: - RAW chip

struct RawChip: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Text("RAW")
                .font(CKFont.chip).tracking(0.3)
                .foregroundStyle(isOn ? CKColor.textPrimary : CKColor.labelRail)
                .frame(width: CKMetrics.chip.width, height: CKMetrics.chip.height)
                .background(RoundedRectangle(cornerRadius: CKMetrics.chipRadius, style: .continuous)
                    .fill(isOn ? CKColor.activeFill : CKColor.chipFill))
                .overlay(RoundedRectangle(cornerRadius: CKMetrics.chipRadius, style: .continuous)
                    .strokeBorder(isOn ? CKColor.activeLine : CKColor.strokeIdle, lineWidth: 1))
                .contentShape(Rectangle().inset(by: -8))
        }
        .buttonStyle(PressScaleStyle())
        .animation(CKMotion.select, value: isOn)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityLabel("RAW capture")
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

// MARK: - Mode key (A / M)

struct ModeKey: View {
    var glyph: String
    var isActive: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(glyph)
                    .id(glyph)
                    .font(CKFont.glyph)
                    .foregroundStyle(CKColor.textPrimary)
                    .transition(.glyphSwap)
            }
            .frame(width: CKMetrics.modeKey.width, height: CKMetrics.modeKey.height)
            .background(CKShape.modeKey.fill(isActive ? CKColor.activeFill : CKColor.modeKeyFill))
            .overlay(CKShape.modeKey.strokeBorder(isActive ? CKColor.activeLine : CKColor.strokeIdle, lineWidth: 1))
            .contentShape(CKShape.modeKey)
        }
        .buttonStyle(PressScaleStyle())
        .animation(CKMotion.select, value: glyph)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: glyph)
        .accessibilityLabel("Control mode \(glyph)")
    }
}

// MARK: - Gallery thumbnail

struct ThumbnailButton: View {
    var image: Image?
    var bumpTrigger: Int          // increments on every capture
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Group {
                if let image {
                    image.resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Color(hex: 0xC9C4DE), Color(hex: 0xE6C3B4), Color(hex: 0x6B5A63)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: CKMetrics.thumbnail.width, height: CKMetrics.thumbnail.height)
            .clipShape(CKShape.thumbnail)
            .overlay(CKShape.thumbnail.strokeBorder(.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(PressScaleStyle())
        // Little "photo landed" bounce on capture.
        .keyframeAnimator(initialValue: 1.0, trigger: bumpTrigger) { content, s in
            content.scaleEffect(s)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1.0, duration: 0.12)
                CubicKeyframe(1.08, duration: 0.10)
                CubicKeyframe(1.0, duration: 0.22)
            }
        }
        .accessibilityLabel("Last photo")
    }
}

// MARK: - Top bar

struct TopBar: View {
    var bracket: String?          // e.g. "-1.0 | 0 | +1.0"; nil hides the badge
    @Binding var flashMode: CameraModel.FlashMode

    var body: some View {
        HStack(alignment: .top) {
            ZStack(alignment: .leading) {
                if let bracket {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("BKT").font(CKFont.badge).foregroundStyle(Color(hex: 0xC8C8C8))
                        Text(bracket).font(CKFont.badgeSub).foregroundStyle(CKColor.tickMinor)
                    }
                    .transition(.badgeSlide)
                }
            }
            .animation(CKMotion.panel, value: bracket)
            .frame(minWidth: 120, alignment: .leading)

            Spacer()

            let symbol: String
            let a11y: String
            switch flashMode {
            case .off:   (symbol, a11y) = ("bolt.slash", "Flash off")
            case .on:    (symbol, a11y) = ("bolt.fill", "Flash on")
            case .auto:  (symbol, a11y) = ("bolt.badge.automatic", "Flash auto")
            }
            RoundButton(symbol: symbol, size: CKMetrics.compact,
                        a11y: a11y) {
                flashMode = flashMode.next
            }
                .foregroundStyle(CKColor.textSecondary)
                .font(.system(size: 18, weight: .regular))
                .background(.clear)
        }
        .padding(.horizontal, 20)
        .frame(height: 48)
    }
}
