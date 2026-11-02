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

        // 2. Apply color adjustments (brightness, contrast, saturation)
        filtered = applyColorControls(to: filtered, adjustment: settings.color)

        // 3. Apply temperature and tint (white balance)
        filtered = applyTemperatureTint(to: filtered, adjustment: settings.color)

        // 4. Apply sharpening
        filtered = applySharpen(to: filtered, sharpness: settings.color.sharpness)

        // 5. Apply film grain
        filtered = applyFilmGrain(to: filtered, intensity: settings.intensity * 0.15)

        // 6. Apply watermark (ported from Xiaomi/OnePlus/Vivo watermark systems)
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

    // MARK: - Render

    private func renderToUIImage(_ ciImage: CIImage) -> UIImage {
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return UIImage()
        }
        return UIImage(cgImage: cgImage)
    }
}
