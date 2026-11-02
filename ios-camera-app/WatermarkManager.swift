//
//  WatermarkManager.swift
//  ios-camera-app
//
//  Watermark system ported from decompiled Android camera apps:
//  - Xiaomi: assets/watermarks/leica/* (Leica signature + logo watermarks)
//  - Xiaomi: assets/watermarks/classic/17/* (brand logo + EXIF watermarks)
//  - OnePlus: com.oplus.camera.watermark.OplusWatermark (JNI-based watermark processing)
//  - Vivo: assets/vlogeffect/tail/* (video end-screen watermarks)
//
//  Watermark assets are stored in Assets.xcassets/Watermarks.imageset/
//  "Shot on iPhone" watermark is generated programmatically (Apple branding).
//

import UIKit
import CoreImage

/// Watermark style options ported from decompiled APKs
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

enum WatermarkPosition: String, CaseIterable {
    case bottomRight = "Bottom Right"
    case bottomLeft = "Bottom Left"
    case topRight = "Top Right"
    case topLeft = "Top Left"
    case center = "Center"
}

/// Manages loading and applying watermark overlays to camera frames.
class WatermarkManager {

    private static var cache: [String: CGImage] = [:]

    /// Load a watermark image from the asset catalog.
    static func loadWatermark(named name: String) -> CGImage? {
        if let cached = cache[name] {
            return cached
        }
        guard let uiImage = UIImage(named: name) else {
            print("Watermark not found: \(name)")
            return nil
        }
        guard let cgImage = uiImage.cgImage else { return nil }
        cache[name] = cgImage
        return cgImage
    }

    /// Generate a "Shot on iPhone" text watermark image programmatically.
    static func generateShotOnIPhoneWatermark(size: CGSize) -> CGImage? {
        let text = "Shot on iPhone"
        let fontSize: CGFloat = min(size.width, size.height) * 0.12
        let font = UIFont.systemFont(ofSize: fontSize, weight: .medium)

        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .strokeColor: UIColor.black,
            .strokeWidth: -2.0
        ]

        let textSize = text.size(withAttributes: textAttributes)
        let bgSize = CGSize(width: textSize.width + 20, height: textSize.height + 10)

        UIGraphicsBeginImageContextWithOptions(bgSize, false, 0.0)
        defer { UIGraphicsEndImageContext() }

        guard let context = UIGraphicsGetCurrentContext() else { return nil }

        // Draw semi-transparent black rounded background
        let bgRect = CGRect(origin: .zero, size: bgSize)
        context.setFillColor(UIColor.black.cgColor)
        context.setAlpha(0.5)
        context.fill(bgRect)

        // Draw text
        let textRect = CGRect(
            x: (bgSize.width - textSize.width) / 2,
            y: (bgSize.height - textSize.height) / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: textAttributes)

        return UIGraphicsGetImageFromCurrentImageContext()?.cgImage
    }

    /// Apply a watermark to a UIImage. Returns the composited image.
    static func applyWatermark(
        to image: UIImage,
        style: WatermarkStyle,
        position: WatermarkPosition,
        opacity: Float = 0.8,
        scale: Float = 0.15
    ) -> UIImage {
        guard style != .off else { return image }

        // "Shot on iPhone" is generated programmatically (not an image asset)
        if style == .shotOnIPhone {
            return applyTextWatermark(
                to: image,
                text: "Shot on iPhone",
                position: position,
                opacity: opacity,
                scale: scale
            )
        }

        let watermarkName: String
        switch style {
        case .leicaSignature:
            watermarkName = "wm_leica_signature_white"
        case .leicaLogo:
            watermarkName = "wm_leica_logo"
        case .xiaomiBrand:
            watermarkName = "wm_xiaomi_white"
        case .pocoBrand:
            watermarkName = "wm_poco_white"
        case .redmiBrand:
            watermarkName = "wm_redmi_white"
        case .vivoTail:
            watermarkName = "wm_vivo_tail"
        case .off:
            return image
        case .shotOnIPhone:
            return image // handled above
        }

        guard let watermarkCG = loadWatermark(named: watermarkName) else {
            print("Failed to load watermark: \(watermarkName)")
            return image
        }

        let watermark = UIImage(cgImage: watermarkCG)

        // Calculate watermark size relative to image
        let wmSize = CGSize(
            width: image.size.width * CGFloat(scale),
            height: image.size.height * (watermark.size.height / watermark.size.width) * CGFloat(scale)
        )

        // Calculate position
        let positionRect: CGRect
        switch position {
        case .bottomRight:
            positionRect = CGRect(
                x: image.size.width - wmSize.width - 20,
                y: image.size.height - wmSize.height - 20,
                width: wmSize.width,
                height: wmSize.height
            )
        case .bottomLeft:
            positionRect = CGRect(x: 20, y: image.size.height - wmSize.height - 20, width: wmSize.width, height: wmSize.height)
        case .topRight:
            positionRect = CGRect(x: image.size.width - wmSize.width - 20, y: 20, width: wmSize.width, height: wmSize.height)
        case .topLeft:
            positionRect = CGRect(x: 20, y: 20, width: wmSize.width, height: wmSize.height)
        case .center:
            positionRect = CGRect(
                x: (image.size.width - wmSize.width) / 2,
                y: (image.size.height - wmSize.height) / 2,
                width: wmSize.width,
                height: wmSize.height
            )
        }

        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }

        image.draw(in: CGRect(origin: .zero, size: image.size))

        // Draw watermark with opacity
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.setAlpha(CGFloat(opacity))
        watermark.draw(in: positionRect)
        context?.restoreGState()

        let result = UIGraphicsGetImageFromCurrentImageContext() ?? image
        return result
    }

    /// Apply a text-based watermark (e.g. "Shot on iPhone") to a UIImage.
    private static func applyTextWatermark(
        to image: UIImage,
        text: String,
        position: WatermarkPosition,
        opacity: Float,
        scale: Float
    ) -> UIImage {
        let fontSize: CGFloat = min(image.size.width, image.size.height) * CGFloat(scale) * 0.08
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)

        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .strokeColor: UIColor.black,
            .strokeWidth: -2.0
        ]

        let textSize = text.size(withAttributes: textAttributes)
        let bgSize = CGSize(width: textSize.width + 20, height: textSize.height + 10)

        // Calculate position
        let positionRect: CGRect
        switch position {
        case .bottomRight:
            positionRect = CGRect(
                x: image.size.width - bgSize.width - 20,
                y: image.size.height - bgSize.height - 20,
                width: bgSize.width,
                height: bgSize.height
            )
        case .bottomLeft:
            positionRect = CGRect(x: 20, y: image.size.height - bgSize.height - 20, width: bgSize.width, height: bgSize.height)
        case .topRight:
            positionRect = CGRect(x: image.size.width - bgSize.width - 20, y: 20, width: bgSize.width, height: bgSize.height)
        case .topLeft:
            positionRect = CGRect(x: 20, y: 20, width: bgSize.width, height: bgSize.height)
        case .center:
            positionRect = CGRect(
                x: (image.size.width - bgSize.width) / 2,
                y: (image.size.height - bgSize.height) / 2,
                width: bgSize.width,
                height: bgSize.height
            )
        }

        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        defer { UIGraphicsEndImageContext() }

        image.draw(in: CGRect(origin: .zero, size: image.size))

        // Draw semi-transparent black background
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.setFillColor(UIColor.black.cgColor)
        context?.setAlpha(0.4 * CGFloat(opacity))
        context?.fill(positionRect)

        // Draw text with white color and black outline
        let textRect = CGRect(
            x: positionRect.origin.x + 10,
            y: positionRect.origin.y + 5,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: textAttributes)
        context?.restoreGState()

        let result = UIGraphicsGetImageFromCurrentImageContext() ?? image
        return result
    }

    /// Apply watermark to a CVPixelBuffer (used during capture).
    static func applyToPixelBuffer(
        _ pixelBuffer: CVPixelBuffer,
        style: WatermarkStyle,
        position: WatermarkPosition,
        opacity: Float,
        scale: Float,
        context: CIContext
    ) -> CIImage {
        guard style != .off else { return CIImage(cvPixelBuffer: pixelBuffer) }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // "Shot on iPhone" text watermark - render as CIImage overlay
        if style == .shotOnIPhone {
            let uiImage = UIImage(cvPixelBuffer: pixelBuffer)
            let watermarked = applyTextWatermark(
                to: uiImage,
                text: "Shot on iPhone",
                position: position,
                opacity: opacity,
                scale: scale
            )
            guard let cgImage = watermarked.cgImage else { return ciImage }
            return CIImage(cgImage: cgImage)
        }

        let watermarkName: String
        switch style {
        case .leicaSignature: watermarkName = "wm_leica_signature_white"
        case .leicaLogo: watermarkName = "wm_leica_logo"
        case .xiaomiBrand: watermarkName = "wm_xiaomi_white"
        case .pocoBrand: watermarkName = "wm_poco_white"
        case .redmiBrand: watermarkName = "wm_redmi_white"
        case .vivoTail: watermarkName = "wm_vivo_tail"
        case .off: return ciImage
        case .shotOnIPhone: return ciImage // handled above
        }

        guard let watermarkCG = loadWatermark(named: watermarkName) else {
            return ciImage
        }
        let watermarkCIImage = CIImage(cgImage: watermarkCG)

        // Scale watermark relative to image
        let wmScale = CGFloat(scale) * ciImage.extent.width / watermarkCIImage.extent.width
        let scaledWM = watermarkCIImage.transformed(by: CGAffineTransform(scaleX: wmScale, y: wmScale))

        // Position
        let imgExtent = ciImage.extent
        let wmExtent = scaledWM.extent
        var offsetX: CGFloat = 20
        var offsetY: CGFloat = 20

        switch position {
        case .bottomRight:
            offsetX = imgExtent.width - wmExtent.width - 20
            offsetY = imgExtent.height - wmExtent.height - 20
        case .bottomLeft:
            offsetX = 20
            offsetY = imgExtent.height - wmExtent.height - 20
        case .topRight:
            offsetX = imgExtent.width - wmExtent.width - 20
            offsetY = 20
        case .topLeft:
            offsetX = 20
            offsetY = 20
        case .center:
            offsetX = (imgExtent.width - wmExtent.width) / 2
            offsetY = (imgExtent.height - wmExtent.height) / 2
        }

        let positionedWM = scaledWM.transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

        // Composite with opacity
        let alphaFilter = CIFilter(name: "CIColorMatrix")!
        alphaFilter.setValue(positionedWM, forKey: kCIInputImageKey)
        alphaFilter.setValue(CIVector(x: 1, y: 0, z: 0, w: 0), forKey: "inputRVector")
        alphaFilter.setValue(CIVector(x: 0, y: 1, z: 0, w: 0), forKey: "inputGVector")
        alphaFilter.setValue(CIVector(x: 0, y: 0, z: 1, w: 0), forKey: "inputBVector")
        alphaFilter.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity)), forKey: "inputAVector")

        let compositeFilter = CIFilter(name: "CISourceOverCompositing")!
        compositeFilter.setValue(alphaFilter.outputImage ?? positionedWM, forKey: kCIInputImageKey)
        compositeFilter.setValue(ciImage, forKey: kCIInputBackgroundImageKey)

        return compositeFilter.outputImage ?? ciImage
    }
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
