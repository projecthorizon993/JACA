import SwiftUI
import Observation

@Observable
final class CameraModel {
    enum ControlMode {
        case a, m
        var glyph: String { self == .a ? "A" : "M" }
        var showsExposureRulers: Bool { self == .a }   // ASSUMPTION — see AGENT_BRIEF.md §6
    }
    enum FocusMode { case auto, manual }
    enum Zoom: String, CaseIterable {
        case x1 = "1x", x2 = "2x"
        var next: Zoom { self == .x1 ? .x2 : .x1 }
    }

    // Stops
    static let isoStops = [50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200]
    static let shutterStops = ["1/8000", "1/4000", "1/2000", "1/1000", "1/500", "1/250", "1/125", "1/60",
                               "1/30", "1/15", "1/8", "1/4", "1/2", "1s"]
    static let focusStops = 81            // 0.0 … 2.0 m in 0.025 m steps

    // State
    var controlMode: ControlMode = .a
    var focusMode: FocusMode = .auto
    var isoIndex = 3
    var speedIndex = 5
    var focusIndex = 18
    var zoom: Zoom = .x1
    var rawOn = false
    var flashOn = false
    var bracket: String? = nil            // "-1.0 | 0 | +1.0"
    var showGrid = true
    var showHistogram = false
    var showPeaking = false
    var showZebra = false
    var captureCount = 0
    var lastPhoto: Image? = nil

    /// The real camera engine (wires AVFoundation). Set by CameraViewController.
    weak var cameraEngine: (any CameraEngine)?

    func capture() {
        Task {
            do {
                let image = try await cameraEngine?.capture(raw: rawOn, bracket: bracket != nil) ?? Image(systemName: "photo")!
                await MainActor.run {
                    lastPhoto = image
                    captureCount += 1
                }
            } catch {
                print("Capture failed: \(error)")
            }
        }
    }
}

/// Seam for the real camera. The agent wires AVFoundation behind this in phase 2;
/// `CameraModel` stays the single source of truth for the UI.
protocol CameraEngine: AnyObject {
    var histogram: [Double] { get }                     // 0…1, ~48 bins, updated per frame
    func apply(isoIndex: Int, speedIndex: Int)
    func apply(focusDistance: Double?)                  // nil = continuous AF
    func setZoom(_ zoom: CameraModel.Zoom)
    func capture(raw: Bool, bracket: Bool) async throws -> Image
}

/// Fake histogram for previews/demo.
enum MockHistogram {
    static func bins(at t: TimeInterval, count: Int = 48) -> [Double] {
        (0..<count).map { i in
            let x = Double(i) / Double(count - 1)
            func g(_ m: Double, _ s: Double) -> Double { exp(-pow(x - m, 2) / (2 * s * s)) }
            let drift = 0.03 * sin(t * 1.3 + Double(i) * 0.4)
            let v = 0.05 + 0.55 * g(0.15, 0.06) + 0.38 * g(0.33, 0.07) + 0.2 * g(0.5, 0.12)
                  + 0.5 * g(0.78, 0.06) + 0.15 * g(0.9, 0.05) + drift
            return min(max(v, 0.02), 1)
        }
    }
}
