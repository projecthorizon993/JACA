import SwiftUI

/// Full capture screen. Layout follows the 393 × 852 anatomy:
/// top bar 48 · viewfinder 3:4 · exposure 64 · focus 96 · capture row.
struct CameraScreen<Viewfinder: View>: View {
    @State private var model = CameraModel()
    @ViewBuilder var viewfinder: () -> Viewfinder

    var body: some View {
        ZStack {
            CKColor.base.ignoresSafeArea()

            VStack(spacing: 0) {
                TopBar(bracket: model.bracket, flashOn: $model.flashOn)

                // Viewfinder
                ZStack(alignment: .top) {
                    viewfinder()
                    if model.showGrid { GridOverlay() }
                    if model.showPeaking { PeakingOverlay(edges: nil) }
                    if model.showHistogram {
                        TimelineView(.periodic(from: .now, by: 0.12)) { ctx in
                            HistogramPanel(bins: MockHistogram.bins(at: ctx.date.timeIntervalSinceReferenceDate))
                        }
                        .transition(.panelPop)
                    }
                    ViewfinderTools(m: model)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)

                    // Shutter blink
                    Color.black.opacity(0)
                        .keyframeAnimator(initialValue: 0.0, trigger: model.captureCount) { c, o in
                            c.opacity(o)
                        } keyframes: { _ in
                            KeyframeTrack {
                                LinearKeyframe(0.85, duration: 0.04)
                                CubicKeyframe(0.0, duration: 0.22)
                            }
                        }
                        .allowsHitTesting(false)
                }
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: CKMetrics.viewfinderRadius, style: .continuous))
                .animation(CKMotion.panel, value: model.showHistogram)

                // Exposure rulers (A mode) — dim + non-interactive otherwise
                ExposureBar(m: model)
                    .opacity(model.controlMode.showsExposureRulers ? 1 : 0)
                    .allowsHitTesting(model.controlMode.showsExposureRulers)
                    .animation(CKMotion.fade, value: model.controlMode)
                    .padding(.top, 8)

                FocusRow(m: model)
                    .padding(.top, 4)

                captureRow
                Spacer(minLength: 0)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var captureRow: some View {
        ZStack {
            ShutterButton { model.capture() }

            HStack(alignment: .bottom, spacing: 12) {
                ThumbnailButton(image: model.lastPhoto, bumpTrigger: model.captureCount)
                Spacer()
                VStack(spacing: 10) {
                    RoundButton(model.zoom.rawValue, isSelected: model.zoom == .x2, a11y: "Zoom") {
                        withAnimation(CKMotion.select) { model.zoom = model.zoom.next }
                    }
                    RoundButton(symbol: "arrow.triangle.2.circlepath", a11y: "Flip camera") {}
                        .foregroundStyle(CKColor.textPrimary)
                }
                VStack(spacing: 10) {
                    RawChip(isOn: $model.rawOn)
                    ModeKey(glyph: model.controlMode.glyph, isActive: model.controlMode == .m) {
                        withAnimation(CKMotion.select) {
                            model.controlMode = model.controlMode == .a ? .m : .a
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 8)
    }
}

// MARK: - Placeholder scene + previews

struct PlaceholderScene: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0x3F56A0), Color(hex: 0x6483C9), Color(hex: 0xE3B08A),
                                Color(hex: 0x33457F), Color(hex: 0x233466)],
                       startPoint: .top, endPoint: .bottom)
    }
}

#Preview("Camera") {
    CameraScreen { PlaceholderScene() }
}

#Preview("Controls") {
    @Previewable @State var iso = 3
    @Previewable @State var raw = true
    VStack(spacing: 24) {
        DialRuler(count: CameraModel.isoStops.count, index: $iso, majorEvery: 3).frame(width: 160)
        RawChip(isOn: $raw)
        ShutterButton {}
    }
    .padding()
    .background(CKColor.base)
}
