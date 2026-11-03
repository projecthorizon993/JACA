import SwiftUI
import Observation

@Observable
final class CameraModel {
    enum ControlMode {
        case a, m
        var glyph: String { self == .a ? "A" : "M" }
        var showsExposureRulers: Bool { self == .a }
    }
    enum FocusMode { case auto, manual }
    enum Zoom: String, CaseIterable {
        case x1 = "1x", x2 = "2x"
        var next: Zoom { self == .x1 ? .x2 : .x1 }
    }

    enum CameraPosition: String, CaseIterable {
        case back = "Back"
        case front = "Front"
        var avPosition: AVCaptureDevice.Position {
            switch self {
            case .back: return .back
            case .front: return .front
            }
        }
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
    var flashMode: FlashMode = .off
    var whiteBalanceMode: WhiteBalanceMode = .auto
    var cameraPosition: CameraPosition = .back
    var cameraMode: CameraMode = .photo
    var bracket: String? = nil            // "-1.0 | 0 | +1.0"
    var bracketedPhotos: [Image] = []     // bracketed exposure captures
    var doubleExposureFirst: UIImage? = nil   // first exposure for double exposure mode
    var isDoubleExposureMode: Bool = false   // double exposure mode active
    var showGrid = true
    var showHistogram = false
    var showPeaking = false
    var showZebra = false
    var captureCount = 0
    var lastPhoto: Image? = nil
    var faceBounds: [CGRect] = []
    var nightModeEnabled: Bool = false   // Night mode - enhanced low light
    var aiSceneDetectionEnabled: Bool = false   // AI scene detection filter
    var levelDegrees: Double = 0.0       // Device roll angle in degrees
    var zeissLensMode: ZeissLensMode = .off   // Zeiss lens mode
    var zebraMask: CIImage? = nil       // Zebra stripes mask for overexposure
    var zebraMask: CIImage? = nil       // Zebra stripes mask for overexposure performance

    // Real-time histogram from camera engine (48 bins, 0…1)
    var histogram: [Double] = Array(repeating: 0.0, count: 48)

    /// Capture format: JPG, HEVC, or DNG (RAW)
    enum CaptureFormat: String, CaseIterable {
        case jpg   = "JPG"
        case hevc  = "HEVC"
        case dng   = "DNG (RAW)"
        case hdr   = "HDR"
    }

    var captureFormat: CaptureFormat = .jpg

    /// Watermark settings (ported from Xiaomi/OnePlus/Vivo watermark systems)
    var watermarkStyle: WatermarkStyle = .off
    var watermarkPosition: WatermarkPosition = .bottomRight
    var watermarkOpacity: Float = 0.8
    var watermarkScale: Float = 0.15
    var watermarkEnabled: Bool = false

    /// Leica color profile (Leica color science from Xiaomi/Leica collaboration)
    var leicaColorProfile: LeicaColorProfile = .off

    /// The real camera engine (wires AVFoundation). Set by CameraViewController.
    weak var cameraEngine: (any CameraEngine)?

    /// Update histogram from camera engine (called on main thread).
    func updateHistogram(_ bins: [Double]) {
        histogram = bins
    }

    func capture() {
        Task {
            do {
                let isRaw = captureFormat == .dng
                let isHEVC = captureFormat == .hevc
                let isHDR = captureFormat == .hdr
                let image = try await cameraEngine?.capture(
                    raw: isRaw,
                    hevc: isHEVC,
                    hdr: isHDR,
                    bracket: bracket != nil,
                    watermark: WatermarkSettings(
                        style: watermarkStyle,
                        position: watermarkPosition,
                        opacity: watermarkOpacity,
                        scale: watermarkScale,
                        isEnabled: watermarkEnabled,
                        leicaProfile: leicaColorProfile
                    )
                ) ?? Image(systemName: "photo")!
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
    func applyWhiteBalance(_ mode: WhiteBalanceMode)
    func setFlashMode(_ mode: FlashMode)
    func switchCamera()                                 // toggles front/back camera
    func capture(raw: Bool, hevc: Bool, hdr: Bool, bracket: Bool, watermark: WatermarkSettings) async throws -> Image
}

/// Watermark style options ported from decompiled Android camera apps
enum WatermarkStyle: String, CaseIterable {
    case off = "Off"
    case leicaSignature = "Leica Signature"
    case leicaLogo = "Leica Logo"
    case xiaomiBrand = "Xiaomi Brand"
    case pocoBrand = "POCO Brand"
    case redmiBrand = "Redmi Brand"
    case vivoTail = "Vivo Tail"
    case shotOnIPhone = "Shot on iPhone"
}

/// Leica color profile (Leica color science ported from Xiaomi/Leica collaboration)
enum LeicaColorProfile: String, CaseIterable {
    case off = "Off"
    case leicaClassic = "Leica Classic"
    case leicaVivid = "Leica Vivid"
    case leicaBw = "Leica B&W"
}

/// Zeiss lens modes (Zeiss lens science ported from Vivo Zeiss partnership)
enum ZeissLensMode: String, CaseIterable {
    case off = "Off"
    case zeissDistagon = "Zeiss Distagon"
    case zeissPlanar = "Zeiss Planar"
    case zeissSonnar = "Zeiss Sonnar"
}

/// Watermark position options
enum WatermarkPosition: String, CaseIterable {
    case bottomRight = "Bottom Right"
    case bottomLeft = "Bottom Left"
    case topRight = "Top Right"
    case topLeft = "Top Left"
    case center = "Center"
}

/// Data model for watermark settings
struct WatermarkSettings {
    var style: WatermarkStyle = .off
    var position: WatermarkPosition = .bottomRight
    var opacity: Float = 0.8
    var scale: Float = 0.15
    var isEnabled: Bool = false
    var leicaProfile: LeicaColorProfile = .off
}

/// Filter settings for the filter pipeline
struct FilterSettings {
    var lut: CGImage?
    var intensity: Float = 1.0
    var beautyIntensity: Float = 0.0    // beauty/skin smoothing 0-1
    var portraitIntensity: Float = 0.0  // portrait/bokeh 0-1
    var nightIntensity: Float = 0.0     // night mode/Low light enhancement 0-1
    var zeissLensMode: ZeissLensMode = .off   // Zeiss lens mode
    var type: Int = 0  // filter segment index
    var color: ColorAdjustment = ColorAdjustment()
    var leicaProfile: LeicaColorProfile = .off
}

/// Color adjustment parameters
struct ColorAdjustment {
    var brightness: Float = 0.0    // -1.0 to 1.0
    var contrast: Float = 1.0      // 0.0 to 2.0
    var saturation: Float = 1.0    // 0.0 to 2.0
    var temperature: Float = 6500.0 // 2000 to 10000 Kelvin
    var tint: Float = 0.0          // -1.0 to 1.0 (green to magenta)
    var sharpness: Float = 0.0     // 0.0 to 1.0
}

/// Pro camera settings
struct ProSettings {
    var iso: Float = 100.0         // ISO sensitivity
    var shutterSpeed: Float = 1.0 / 30.0 // seconds
    var focusDistance: Float = 0.0  // 0.0 to 1.0 (macro to infinity)
    var whiteBalance: Float = 5500.0  // Kelvin
    var exposureCompensation: Float = 0.0 // -4.0 to 4.0 EV
}

/// White balance mode for manual camera control
enum WhiteBalanceMode: String, CaseIterable {
    case auto = "Auto"
    case daylight = "Daylight"
    case cloudy = "Cloudy"
    case tungsten = "Tungsten"
    case fluorescent = "Fluorescent"
    case flash = "Flash"
    var kelvin: Float {
        switch self {
        case .auto: return 6500.0
        case .daylight: return 5500.0
        case .cloudy: return 6500.0
        case .tungsten: return 3200.0
        case .fluorescent: return 4000.0
        case .flash: return 5500.0
        }
    }
}

/// Flash mode for manual camera control
enum FlashMode: String, CaseIterable {
    case off = "Off"
    case on = "On"
    case auto = "Auto"
    var next: FlashMode {
        switch self {
        case .off: return .on
        case .on: return .auto
        case .auto: return .off
        }
    }
}
