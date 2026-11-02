import SwiftUI

// MARK: - Grid

struct GridOverlay: View {
    var body: some View {
        GeometryReader { g in
            Path { p in
                for f in [1.0 / 3, 2.0 / 3] {
                    p.move(to: CGPoint(x: g.size.width * f, y: 0))
                    p.addLine(to: CGPoint(x: g.size.width * f, y: g.size.height))
                    p.move(to: CGPoint(x: 0, y: g.size.height * f))
                    p.addLine(to: CGPoint(x: g.size.width, y: g.size.height * f))
                }
            }
            .stroke(CKColor.grid, lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Histogram

/// `bins` are 0...1. Panel floats at the top of the viewfinder.
struct HistogramPanel: View {
    var bins: [Double]

    var body: some View {
        GeometryReader { g in
            HStack(alignment: .bottom, spacing: 1) {
                ForEach(bins.indices, id: \.self) { i in
                    Rectangle()
                        .fill(CKColor.histogramBar)
                        .frame(height: max(1, (g.size.height - 12) * bins[i]))
                }
            }
            .padding(6)
            .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
            .animation(CKMotion.histogram, value: bins)
        }
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CKColor.histogramPanel))
        .frame(height: 140)
        .padding(.horizontal, 6)
        .padding(.top, 6)
        .accessibilityLabel("Histogram")
    }
}

// MARK: - Focus peaking
//
// Real peaking needs per-frame edge detection (Metal / Core Image on the video output).
// The engine should hand this view a tinted edge image; here it is only composited.
struct PeakingOverlay: View {
    var edges: Image?
    var body: some View {
        if let edges {
            edges.resizable().scaledToFill()
                .blendMode(.plusLighter)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Tool icons

struct DashedCircleIcon: View {
    var body: some View {
        Circle()
            .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [3.2, 3.2]))
            .frame(width: 18, height: 18)
    }
}

struct LayersIcon: View {
    var body: some View {
        ZStack {
            Circle().stroke(lineWidth: 1.6).frame(width: 13, height: 13).offset(x: -3, y: 3)
            Circle().stroke(lineWidth: 1.6).frame(width: 13, height: 13).offset(x: 3, y: -3)
        }
        .frame(width: 22, height: 22)
    }
}

// MARK: - Viewfinder tools (bottom-leading)

struct ViewfinderTools: View {
    @Bindable var m: CameraModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundButton(size: CKMetrics.round, style: .float, isSelected: m.showZebra,
                        a11y: "Zebra stripes", action: { m.showZebra.toggle() }) { DashedCircleIcon() }
                .foregroundStyle(CKColor.textPrimary)
            HStack(spacing: 12) {
                RoundButton(symbol: "magnifyingglass", style: .float, isSelected: m.showPeaking,
                            a11y: "Focus peaking") { m.showPeaking.toggle() }
                    .foregroundStyle(CKColor.textPrimary)
                RoundButton(size: CKMetrics.round, style: .float, isSelected: m.showHistogram,
                            a11y: "Histogram", action: {
                                withAnimation(CKMotion.panel) { m.showHistogram.toggle() }
                            }) { LayersIcon() }
                    .foregroundStyle(CKColor.textPrimary)
            }
        }
        .padding(12)
    }
}
