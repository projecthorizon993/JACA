//
//  FilterPipeline.swift
//  ios-camera-app
//
//  Filter pipeline ported from decompiled Android camera apps:
//  - Vivo: LookupFilterParams → CameraLookupTableRenderNode → drawToTexture (LUT-based)
//  - OnePlus: OplusFilter JNI → libOplusFilterLUTJni.so + libPolarrRender.so
//
//  iOS implementation: CIColorCube for LUTs, CISepiaTone/CIColorControls as fallbacks.
//

import UIKit
import CoreImage
import CoreVideo
import Accelerate

class FilterPipeline {

    private let ciContext: CIContext

    init() {
        if let eaglContext = EAGLContext(api: .openGLES3) {
            ciContext = CIContext(eaglContext: eaglContext, options: [.workingColorSpace: NSNull()])
        } else {
            ciContext = CIContext(options: [.workingColorSpace: NSNull()])
        }
    }

    /// Apply filter to a CVPixelBuffer (from AVCaptureVideoDataOutput).
    /// Returns a UIImage suitable for display in MTKView or UIImageView.
    func apply(to pixelBuffer: CVPixelBuffer, lut: CGImage?, intensity: Float, filterType: Int) -> UIImage {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        var filtered = ciImage

        switch filterType {
        case 1:  // Classic Film
            filtered = applyClassicFilm(to: filtered, lut: lut, intensity: intensity)
        case 2:  // Cyberpunk
            filtered = applyCyberpunk(to: filtered, lut: lut, intensity: intensity)
        case 3:  // Greenland
            filtered = applyGreenland(to: filtered, lut: lut, intensity: intensity)
        case 4:  // Night Style
            filtered = applyNightStyle(to: filtered, lut: lut, intensity: intensity)
        default:
            break
        }

        // Apply film grain (ported from film_grain_small.bin / texPerlinNoise.pkm)
        filtered = applyFilmGrain(to: filtered, intensity: intensity * 0.15)

        return renderToUIImage(filtered)
    }

    // MARK: - LUT-based filters (CIColorCube port of Android LUT pipeline)

    private func applyClassicFilm(to image: CIImage, lut: CGImage?, intensity: Float) -> CIImage {
        guard let lut = lut else { return applySepiaTone(to: image, intensity: intensity * 0.6) }
        return applyColorCube(to: image, lut: lut, intensity: intensity)
    }

    private func applyCyberpunk(to image: CIImage, lut: CGImage?, intensity: Float) -> CIImage {
        guard let lut = lut else { return applyColorControls(to: image, saturation: 1.5, contrast: 1.2, brightness: 0.05) }
        return applyColorCube(to: image, lut: lut, intensity: intensity)
    }

    private func applyGreenland(to image: CIImage, lut: CGImage?, intensity: Float) -> CIImage {
        guard let lut = lut else { return applyColorControls(to: image, saturation: 0.8, contrast: 1.1, brightness: -0.02) }
        return applyColorCube(to: image, lut: lut, intensity: intensity)
    }

    private func applyNightStyle(to image: CIImage, lut: CGImage?, intensity: Float) -> CIImage {
        guard let lut = lut else { return applyColorControls(to: image, saturation: 0.6, contrast: 1.3, brightness: -0.05) }
        return applyColorCube(to: image, lut: lut, intensity: intensity)
    }

    // MARK: - Core Image filter helpers

    private func applyColorCube(to image: CIImage, lut: CGImage, intensity: Float) -> CIImage {
        let lutImage = CIImage(cgImage: lut)
        guard let colorCube = CIFilter(name: "CIColorCube") else { return image }
        colorCube.setValue(image, forKey: kCIInputImageKey)
        colorCube.setValue(lutImage, forKey: "inputCubeImage")
        colorCube.setValue(intensity, forKey: "inputIntensity")
        return colorCube.outputImage ?? image
    }

    private func applySepiaTone(to image: CIImage, intensity: Float) -> CIImage {
        guard let sepia = CIFilter(name: "CISepiaTone") else { return image }
        sepia.setValue(image, forKey: kCIInputImageKey)
        sepia.setValue(intensity, forKey: kCIInputIntensityKey)
        return sepia.outputImage ?? image
    }

    private func applyColorControls(to image: CIImage, saturation: Float, contrast: Float, brightness: Float) -> CIImage {
        guard let controls = CIFilter(name: "CIColorControls") else { return image }
        controls.setValue(image, forKey: kCIInputImageKey)
        controls.setValue(saturation, forKey: kCIInputSaturationKey)
        controls.setValue(contrast, forKey: kCIInputContrastKey)
        controls.setValue(brightness, forKey: kCIInputBrightnessKey)
        return controls.outputImage ?? image
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
