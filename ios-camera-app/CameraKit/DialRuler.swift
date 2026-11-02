import SwiftUI

// MARK: - Pure math (unit-tested)

enum DialMath {
    /// Fractional position while dragging. Dragging right moves content right, so the position DEcreases.
    static func position(anchor: Int, translation: CGFloat, spacing: CGFloat, count: Int) -> Double {
        let raw = Double(anchor) - Double(translation / spacing)
        return min(max(raw, 0), Double(max(count - 1, 0)))
    }

    static func index(for position: Double, count: Int) -> Int {
        min(max(Int(position.rounded()), 0), max(count - 1, 0))
    }

    /// Ticks fade toward the edges, never below 0.16.
    static func opacity(distance: CGFloat, falloff: CGFloat) -> Double {
        max(0.16, 1 - Double(abs(distance) / falloff))
    }
}

// MARK: - Ruler

/// Horizontal dial: ticks scroll under a fixed red needle at centre. Snaps to stops with a spring,
/// ticks a selection haptic on every stop, supports VoiceOver increment/decrement.
struct DialRuler: View {
    let count: Int
    @Binding var index: Int
    var spacing: CGFloat = CKMetrics.tickSpacingExposure
    var majorEvery: Int = 4
    var majorHeight: CGFloat = 16
    var minorHeight: CGFloat = 11
    var needleHeight: CGFloat = 22
    var falloff: CGFloat = 110
    var labels: ((Int) -> String?)? = nil     // labels above major ticks (focus rail)
    var a11yName: String = "Dial"
    var a11yValue: String = ""

    @State private var live: Double?
    @State private var anchor: Int?

    private var position: Double { live ?? Double(index) }
    private var labelBand: CGFloat { labels == nil ? 0 : 20 }

    var body: some View {
        GeometryReader { geo in
            let visible = Int(geo.size.width / 2 / spacing) + 2
            let center = Int(position.rounded())
            let lo = max(0, center - visible)
            let hi = min(count - 1, center + visible)
            ZStack {
                if lo <= hi {
                    ForEach(lo...hi, id: \.self) { i in tick(i) }
                }
                Rectangle()
                    .fill(CKColor.marker)
                    .frame(width: 2.5, height: needleHeight)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .frame(height: needleHeight + labelBand)
        .contentShape(Rectangle())
        .gesture(drag)
        .sensoryFeedback(.selection, trigger: index)
        .accessibilityElement()
        .accessibilityLabel(a11yName)
        .accessibilityValue(a11yValue)
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: withAnimation(CKMotion.ruler) { index = min(index + 1, count - 1) }
            case .decrement: withAnimation(CKMotion.ruler) { index = max(index - 1, 0) }
            @unknown default: break
            }
        }
    }

    @ViewBuilder
    private func tick(_ i: Int) -> some View {
        let x = (CGFloat(i) - CGFloat(position)) * spacing
        let major = i % majorEvery == 0
        VStack(spacing: 4) {
            if labels != nil {
                if major, let t = labels?(i) {
                    Text(t).font(CKFont.scale).foregroundStyle(CKColor.textSecondary).fixedSize()
                } else {
                    Color.clear.frame(width: 1, height: 16)
                }
            }
            Rectangle()
                .fill(major ? CKColor.tickMajor : CKColor.tickMinor)
                .frame(width: major ? 2 : 1.5, height: major ? majorHeight : minorHeight)
        }
        .frame(maxHeight: .infinity, alignment: .bottom)
        .opacity(DialMath.opacity(distance: x, falloff: falloff))
        .offset(x: x)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                if anchor == nil { anchor = index }
                let p = DialMath.position(anchor: anchor ?? index, translation: v.translation.width,
                                          spacing: spacing, count: count)
                live = p
                let new = DialMath.index(for: p, count: count)
                if new != index { index = new }
            }
            .onEnded { v in
                // A light fling: 60% of the predicted travel.
                let p = DialMath.position(anchor: anchor ?? index,
                                          translation: v.predictedEndTranslation.width * 0.6,
                                          spacing: spacing, count: count)
                let target = DialMath.index(for: p, count: count)
                anchor = nil
                withAnimation(CKMotion.ruler) {
                    index = target
                    live = nil
                }
            }
    }
}

// MARK: - ISO + SPEED row

struct ExposureBar: View {
    @Bindable var m: CameraModel

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("ISO").font(CKFont.railLabel).tracking(0.4).foregroundStyle(CKColor.labelRail)
                Spacer(minLength: 0)
                Text("\(CameraModel.isoStops[m.isoIndex])")
                    .font(CKFont.value).foregroundStyle(CKColor.textPrimary)
                    .contentTransition(.numericText())
                    .animation(CKMotion.select, value: m.isoIndex)
                Spacer(minLength: 0)
                Text(CameraModel.shutterStops[m.speedIndex])
                    .font(CKFont.value).foregroundStyle(CKColor.textPrimary)
                    .contentTransition(.interpolate)
                    .animation(CKMotion.select, value: m.speedIndex)
                Spacer(minLength: 0)
                Text("SPEED").font(CKFont.railLabel).tracking(0.4).foregroundStyle(CKColor.labelRail)
            }
            .padding(.horizontal, 24)

            HStack(spacing: 0) {
                DialRuler(count: CameraModel.isoStops.count, index: $m.isoIndex, majorEvery: 3,
                          a11yName: "ISO", a11yValue: "\(CameraModel.isoStops[m.isoIndex])")
                    .frame(width: 112)
                Spacer(minLength: 0)
                DialRuler(count: CameraModel.shutterStops.count, index: $m.speedIndex, majorEvery: 5,
                          a11yName: "Shutter speed", a11yValue: CameraModel.shutterStops[m.speedIndex])
                    .frame(width: 144)
            }
            .padding(.horizontal, 24)
        }
        .frame(height: 64)
    }
}

// MARK: - Focus row (rail ⇄ MF stub)

struct FocusRow: View {
    @Bindable var m: CameraModel
    @Namespace private var ns

    var body: some View {
        ZStack {
            if m.focusMode == .auto {
                HStack(spacing: 8) {
                    macro
                    DialRuler(count: CameraModel.focusStops, index: $m.focusIndex,
                              spacing: CKMetrics.tickSpacingFocus, majorEvery: 4,
                              majorHeight: 14, minorHeight: 10, needleHeight: 25, falloff: 125,
                              labels: { String(format: "%.1f", Double($0) * 0.025) },
                              a11yName: "Focus distance",
                              a11yValue: String(format: "%.2f metres", Double(m.focusIndex) * 0.025))
                    RoundButton("AF", size: CKMetrics.compact, isSelected: true, a11y: "Autofocus on") {
                        withAnimation(CKMotion.panel) { m.focusMode = .manual }
                    }
                }
                .padding(.horizontal, 30)
                .transition(.railSwap)
            } else {
                HStack {
                    VStack(spacing: 8) {
                        RoundButton("MF", size: CKMetrics.compact, a11y: "Manual focus, tap for autofocus") {
                            withAnimation(CKMotion.panel) { m.focusMode = .auto }
                        }
                        macro
                    }
                    Spacer()
                }
                .padding(.leading, 30)
                .transition(.railSwap)
            }
        }
        .frame(height: 96, alignment: .top)
        .sensoryFeedback(.selection, trigger: m.focusMode)
    }

    private var macro: some View {
        RoundButton(symbol: "camera.macro", size: CKMetrics.compact, a11y: "Macro") {}
            .font(.system(size: 16))
            .foregroundStyle(CKColor.labelRail)
            .matchedGeometryEffect(id: "macro", in: ns)
    }
}
