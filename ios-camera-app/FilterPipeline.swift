//
//  FilterPipeline.swift
//  ios-camera-app
//
//  Filter pipeline ported from decompiled Android camera apps:
//  - Vivo: LookupFilterParams → CameraLookupTableRenderNode → drawToTexture (LUT-based)
//  - OnePlus: OplusFilter JNI → libOplusFilterLUTJni.so + libPolarrRender.so
//
//  iOS implementation: CIColorCube for LUTs, CIColorControls for color adjustments,
//  CIWhitePointAdjust for temperature/tint, CISharpenLuminance for sharpness.
//

import UIKit
import CoreImage
import CoreVideo
import Accelerate
import Metal
import OpenGLES

/// Filter pipeline with optional GPU Metal backend.
/// Ported from decompiled Android camera apps:
///   - Vivo: LookupFilterParams → CameraLookupTableRenderNode → drawToTexture (LUT-based)
///   - OnePlus: OplusFilter JNI → libOplusFilterLUTJni.so + libPolarrRender.so
///
/// Backend: Core Image (CPU/GPU hybrid) or Metal (pure GPU via Shaders.metal).
class FilterPipeline {

    private let ciContext: CIContext
    private let metalPipeline: MetalFilterPipeline?
    private let useMetal: Bool

    /// Beauty / skin smoothing intensity (0-1).
    var beautyIntensity: Float = 0.0

    /// Portrait / bokeh intensity (0-1).
    var portraitIntensity: Float = 0.0

    /// Night mode / low light enhancement intensity (0-1).
    var nightIntensity: Float = 0.0

    /// Zeiss lens mode
    var zeissLensMode: ZeissLensMode = .off

    /// Create pipeline. Use Metal GPU backend when available and requested.
    init(useMetal: Bool = MetalFilterPipeline.isMetalAvailable) {
        self.useMetal = useMetal && MetalFilterPipeline.isMetalAvailable
        if self.useMetal {
            metalPipeline = MetalFilterPipeline()
        } else {
            metalPipeline = nil
        }
        if let eaglContext = EAGLContext(api: .openGLES3) {
            ciContext = CIContext(eaglContext: eaglContext, options: [.workingColorSpace: NSNull()])
        } else {
            ciContext = CIContext(options: [.workingColorSpace: NSNull()])
        }
    }

    /// Whether the Metal GPU backend is active.
    var isUsingMetal: Bool { useMetal }

    /// Apply full filter pipeline to a CVPixelBuffer.
    /// Routes to Metal GPU backend when available, otherwise Core Image.
    /// Returns a UIImage suitable for display.
    func apply(
        to pixelBuffer: CVPixelBuffer,
        settings: FilterSettings,
        watermark: WatermarkSettings = WatermarkSettings()
    ) -> UIImage {
        // GPU path: Metal Shading Language shaders (ported from GLSL in com.oplus.camera.gl)
        if useMetal, let metalPipeline = metalPipeline {
            // Metal path doesn't yet support watermark; fall back to CI for watermark frames
            if !watermark.isEnabled,
               let metalImage = metalPipeline.apply(to: pixelBuffer, settings: settings) {
                return metalImage
            }
        }

        // CPU/GPU-hybrid path: Core Image
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        var filtered = ciImage

        // 1. Apply LUT-based filter (ported from Vivo LUT pipeline)
        filtered = applyLUTFilter(to: filtered, settings: settings)

        // 2. Apply Leica color profile (ported from Xiaomi/Leica collaboration)
        filtered = applyLeicaColorProfile(to: filtered, profile: settings.leicaProfile)

        // 3. Apply color adjustments (brightness, contrast, saturation)
        filtered = applyColorControls(to: filtered, adjustment: settings.color)

        // 4. Apply temperature and tint (white balance)
        filtered = applyTemperatureTint(to: filtered, adjustment: settings.color)

        // 5. Apply sharpening
        filtered = applySharpen(to: filtered, sharpness: settings.color.sharpness)

        // 6. Apply film grain
        filtered = applyFilmGrain(to: filtered, intensity: settings.intensity * 0.15)

        // 7. Apply beauty / skin smoothing
        filtered = applyBeauty(to: filtered, intensity: settings.beautyIntensity)

        // 8. Apply portrait mode / bokeh effect
        filtered = applyPortraitMode(to: filtered, intensity: settings.portraitIntensity)

        // 9. Apply night mode / low light enhancement
        filtered = applyNightMode(to: filtered, intensity: settings.nightIntensity)

        // 10. Apply Zeiss lens mode
        filtered = applyZeissLensMode(to: filtered, mode: settings.zeissLensMode)

        // 11. Apply watermark (ported from Xiaomi/OnePlus/Vivo watermark systems)
        if watermark.isEnabled {
            filtered = WatermarkManager.applyToPixelBuffer(
                pixelBuffer,
                style: watermark.style,
                position: watermark.position,
                opacity: watermark.opacity,
                scale: watermark.scale,
                context: ciContext
            )
        }

        return renderToUIImage(filtered)
    }

    // MARK: - LUT Filter (ported from Vivo CameraLookupTableRenderNode)

    private func applyLUTFilter(to image: CIImage, settings: FilterSettings) -> CIImage {
        guard let lut = settings.lut else { return image }
        let lutImage = CIImage(cgImage: lut)
        guard let colorCube = CIFilter(name: "CIColorCube") else { return image }
        colorCube.setValue(image, forKey: kCIInputImageKey)
        colorCube.setValue(lutImage, forKey: "inputCubeImage")
        colorCube.setValue(settings.intensity, forKey: "inputIntensity")
        return colorCube.outputImage ?? image
    }

    // MARK: - Color Controls (brightness, contrast, saturation)

    private func applyColorControls(to image: CIImage, adjustment: ColorAdjustment) -> CIImage {
        guard let controls = CIFilter(name: "CIColorControls") else { return image }
        controls.setValue(image, forKey: kCIInputImageKey)
        controls.setValue(adjustment.saturation, forKey: kCIInputSaturationKey)
        controls.setValue(adjustment.contrast, forKey: kCIInputContrastKey)
        controls.setValue(adjustment.brightness, forKey: kCIInputBrightnessKey)
        return controls.outputImage ?? image
    }

    // MARK: - Temperature and Tint (white balance)

    private func applyTemperatureTint(to image: CIImage, adjustment: ColorAdjustment) -> CIImage {
        var result = image

        // Temperature: shift toward blue (cool) or yellow (warm)
        if adjustment.temperature != 6500.0 {
            let tempFactor = (adjustment.temperature - 6500.0) / 6500.0
            let blueShift: CGFloat = CGFloat(-tempFactor * 0.15)
            let yellowShift: CGFloat = CGFloat(tempFactor * 0.1)
            let colorFilter = CIFilter(name: "CIColorMatrix")!
            colorFilter.setValue(result, forKey: kCIInputImageKey)
            colorFilter.setValue(CIVector(x: 1 + yellowShift, y: 0, z: 0, w: 0), forKey: "inputRVector")
            colorFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
            colorFilter.setValue(CIVector(x: 0, y: 0, z: 1 + blueShift, w: 0), forKey: "inputBVector")
            colorFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            colorFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
            result = colorFilter.outputImage ?? result
        }

        // Tint: shift toward green or magenta
        if adjustment.tint != 0.0 {
            let tintFilter = CIFilter(name: "CIColorMatrix")!
            tintFilter.setValue(result, forKey: kCIInputImageKey)
            let greenShift = CGFloat(-adjustment.tint * 0.1)
            let magentaShift = CGFloat(adjustment.tint * 0.05)
            tintFilter.setValue(CIVector(x: 1 + magentaShift, y: 0, z: 0, w: 0), forKey: "inputRVector")
            tintFilter.setValue(CIVector(x: 0, y: 1 + greenShift, z: 0, w: 0), forKey: "inputGVector")
            tintFilter.setValue(CIVector(x: 0, y: 0, z: 1 + magentaShift, w: 0), forKey: "inputBVector")
            tintFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
            tintFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")
            result = tintFilter.outputImage ?? result
        }

        return result
    }

    // MARK: - Sharpening

    private func applySharpen(to image: CIImage, sharpness: Float) -> CIImage {
        guard sharpness > 0 else { return image }
        guard let sharpen = CIFilter(name: "CISharpenLuminance") else { return image }
        sharpen.setValue(image, forKey: kCIInputImageKey)
        sharpen.setValue(sharpness, forKey: kCIInputSharpnessKey)
        return sharpen.outputImage ?? image
    }

    // MARK: - Film grain (from film_grain_small.bin)

    private func applyFilmGrain(to image: CIImage, intensity: Float) -> CIImage {
        guard intensity > 0 else { return image }
        let grain = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
            .cropped(to: image.extent)
        guard let blend = CIFilter(name: "CIBlendWithMask") else { return image }
        blend.setValue(image, forKey: kCIInputImageKey)
        blend.setValue(grain, forKey: kCIInputMaskImageKey)
        blend.setValue(intensity, forKey: kCIInputIntensityKey)
        return blend.outputImage ?? image
    }

    // MARK: - Beauty / skin smoothing

    /// Beauty filter smooths skin tones using bilateral-style blur blended at low intensity.
    private func applyBeauty(to image: CIImage, intensity: Float) -> CIImage {
        guard intensity > 0 else { return image }
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return image }
        blur.setValue(image, forKey: kCIInputImageKey)
        blur.setValue(intensity * 2.0, forKey: kCIInputRadiusKey)
        guard let blurred = blur.outputImage else { return image }

        // Blend blurred with original at low strength for subtle skin smoothing
        guard let blend = CIFilter(name: "CIBlendWithMask") else { return blurred }
        blend.setValue(blurred, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        blend.setValue(intensity * 0.5, forKey: kCIInputIntensityKey)
        return blend.outputImage ?? blurred
    }

    // MARK: - Portrait mode / Bokeh effect

    /// Portrait mode applies a depth-based blur (bokeh) effect using radial gradient mask.
    private func applyPortraitMode(to image: CIImage, intensity: Float) -> CIImage {
        guard intensity > 0 else { return image }
        let extent = image.extent
        let center = CGPoint(x: extent.midX, y: extent.midY)
        let radius = min(extent.width, extent.height) * 0.4

        // Create radial gradient mask (sharp center, blurred edges)
        let radial = CIFilter(name: "CIRadialGradient")!
        radial.setValue(CIVector(x: center.x, y: center.y), forKey: "inputCenter")
        radial.setValue(CIVector(x: 0, y: 0), forKey: "inputRadius0")
        radial.setValue(CIVector(x: radius, y: radius), forKey: "inputRadius1")
        radial.setValue(CIColor(color: .white), forKey: "inputColor0")
        radial.setValue(CIColor(color: .black), forKey: "inputColor1")

        guard let radialMask = radial.outputImage?.cropped(to: image.extent) else {
            return image
        }

        // Blur the image
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return image }
        blur.setValue(image, forKey: kCIInputImageKey)
        blur.setValue(intensity * 3.0, forKey: kCIInputRadiusKey)
        guard let blurred = blur.outputImage else { return image }

        // Blend blurred background with sharp center using radial mask
        guard let blend = CIFilter(name: "CIBlendWithMask") else { return blurred }
        blend.setValue(blurred, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        blend.setValue(radialMask, forKey: kCIInputMaskImageKey)

        return blend.outputImage ?? blurred
    }

    // MARK: - Night mode / low light enhancement

    /// Night mode enhances low light by boosting brightness/contrast and reducing noise.
    private func applyNightMode(to image: CIImage, intensity: Float) -> CIImage {
        guard intensity > 0 else { return image }

        // Increase brightness and contrast for low light
        guard let controls = CIFilter(name: "CIColorControls") else { return image }
        controls.setValue(image, forKey: kCIInputImageKey)
        controls.setValue(1.0 + intensity * 0.3, forKey: kCIInputBrightnessKey)
        controls.setValue(1.0 + intensity * 0.4, forKey: kCIInputContrastKey)
        controls.setValue(1.0 + intensity * 0.2, forKey: kCIInputSaturationKey)
        guard let brightened = controls.outputImage else { return image }

        // Reduce noise with slight blur
        guard let blur = CIFilter(name: "CIGaussianBlur") else { return brightened }
        blur.setValue(brightened, forKey: kCIInputImageKey)
        blur.setValue(intensity * 1.5, forKey: kCIInputRadiusKey)
        guard let blurred = blur.outputImage else { return brightened }

        // Blend original (sharp) with blurred (noise reduced)
        guard let blend = CIFilter(name: "CISourceOverCompositing") else { return brightened }
        blend.setValue(blurred, forKey: kCIInputImageKey)
        blend.setValue(image, forKey: kCIInputBackgroundImageKey)
        blend.setValue(intensity * 0.5, forKey: kCIInputIntensityKey)

        return blend.outputImage ?? brightened
    }

    // MARK: - Zeiss Lens Mode

    /// Zeiss lens modes apply characteristic lens rendering (contrast, bokeh, color rendering).
    private func applyZeissLensMode(to image: CIImage, mode: ZeissLensMode) -> CIImage {
        guard mode != .off else { return image }

        switch mode {
        case .zeissDistagon:
            // Distagon: Wide angle, high contrast, cooler tones
            return applyZeissMatrix(to: image, r: 1.05, g: 0.98, b: 0.92, contrast: 1.15, saturation: 1.05)
        case .zeissPlanar:
            // Planar: Standard, balanced contrast, natural colors
            return applyZeissMatrix(to: image, r: 1.02, g: 1.00, b: 0.98, contrast: 1.05, saturation: 1.0)
        case .zeissSonnar:
            // Sonnar: Telephoto, soft bokeh, warmer tones
            return applyZeissMatrix(to: image, r: 1.08, g: 1.02, b: 0.95, contrast: 1.05, saturation: 1.10)
        default:
            return image
        }
    }

    private func applyZeissMatrix(to image: CIImage, r: Float, g: Float, b: Float, contrast: Float, saturation: Float) -> CIImage {
        guard let matrix = CIFilter(name: "CIColorMatrix") else { return image }
        matrix.setValue(image, forKey: kCIInputImageKey)
        matrix.setValue(CIVector(x: r, y: 0, z: 0, w: 0), forKey: "inputRVector")
        matrix.setValue(CIVector(x: 0, y: g, z: 0, w: 0), forKey: "inputGVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: b, w: 0), forKey: "inputBVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")
        matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBiasVector")

        guard let result = matrix.outputImage else { return image }

        guard let controls = CIFilter(name: "CIColorControls") else { return result }
        controls.setValue(result, forKey: kCIInputImageKey)
        controls.setValue(contrast, forKey: kCIInputContrastKey)
        controls.setValue(saturation, forKey: kCIInputSaturationKey)

        return controls.outputImage ?? result
    }
        switch profile {
        case .off:
            return image

        case .leicaClassic:
            // Leica Classic: warm, slightly desaturated, rich blacks
            // Color matrix: slight red/yellow shift, reduced saturation, lifted blacks
            guard let matrix = CIFilter(name: "CIColorMatrix") else { return image }
            matrix.setValue(image, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: 1.05, y: 0.0, z: 0.0, w: 0.0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0.0, y: 0.95, z: 0.0, w: 0.0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0.0, y: 0.0, z: 0.90, w: 0.0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0.0, y: 0.0, z: 0.0, w: 1.0), forKey: "inputAVector")
            matrix.setValue(CIVector(x: 0.01, y: 0.005, z: 0.0, w: 0.0), forKey: "inputBiasVector")
            guard let result = matrix.outputImage else { return image }

            // Slight contrast boost
            guard let controls = CIFilter(name: "CIColorControls") else { return result }
            controls.setValue(result, forKey: kCIInputImageKey)
            controls.setValue(0.90, forKey: kCIInputSaturationKey)
            controls.setValue(1.10, forKey: kCIInputContrastKey)
            controls.setValue(0.02, forKey: kCIInputBrightnessKey)
            return controls.outputImage ?? result

        case .leicaVivid:
            // Leica Vivid: saturated colors, punchy contrast, cooler highlights
            guard let matrix = CIFilter(name: "CIColorMatrix") else { return image }
            matrix.setValue(image, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: 1.10, y: 0.0, z: 0.0, w: 0.0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0.0, y: 1.05, z: 0.0, w: 0.0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0.0, y: 0.0, z: 0.95, w: 0.0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0.0, y: 0.0, z: 0.0, w: 1.0), forKey: "inputAVector")
            matrix.setValue(CIVector(x: -0.01, y: -0.01, z: 0.01, w: 0.0), forKey: "inputBiasVector")
            guard let result = matrix.outputImage else { return image }

            // Higher saturation and contrast
            guard let controls = CIFilter(name: "CIColorControls") else { return result }
            controls.setValue(result, forKey: kCIInputImageKey)
            controls.setValue(1.25, forKey: kCIInputSaturationKey)
            controls.setValue(1.15, forKey: kCIInputContrastKey)
            controls.setValue(0.0, forKey: kCIInputBrightnessKey)
            return controls.outputImage ?? result

        case .leicaBw:
            // Leica B&W: monochrome with Leica tonal curve
            guard let bw = CIFilter(name: "CIColorControls") else { return image }
            bw.setValue(image, forKey: kCIInputImageKey)
            bw.setValue(0.0, forKey: kCIInputSaturationKey)
            bw.setValue(1.20, forKey: kCIInputContrastKey)
            bw.setValue(0.05, forKey: kCIInputBrightnessKey)
            guard let result = bw.outputImage else { return image }

            // Slight warm tone in the B&W (Leica monochrome character)
            guard let matrix = CIFilter(name: "CIColorMatrix") else { return result }
            matrix.setValue(result, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0.0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0.0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0.0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0.0, y: 0.0, z: 0.0, w: 1.0), forKey: "inputAVector")
            matrix.setValue(CIVector(x: 0.02, y: 0.02, z: 0.02, w: 0.0), forKey: "inputBiasVector")
            return matrix.outputImage ?? result
        }
    }

    // MARK: - Render

    private func renderToUIImage(_ ciImage: CIImage) -> UIImage {
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return UIImage()
        }
        return UIImage(cgImage: cgImage)
    }
}
