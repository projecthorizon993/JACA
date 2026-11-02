//
//  LUTManager.swift
//  ios-camera-app
//
//  Loads LUT textures extracted from decompiled Android camera APKs.
//  Source assets: lut_all_points.png, filter_*.png, new_filter_*.png, lut1.png.bin, daily_lut.png.bin
//  Staged at: C:\Users\Admin\AppData\Local\Temp\opencode\ios-camera-assets\lut\
//

import UIKit
import CoreImage

class LUTManager {

    private static var lutCache: [String: CGImage] = [:]

    /// Load a LUT PNG from the app bundle. The asset must be added to Assets.xcassets.
    /// Returns nil if not found — caller should fall back to CIColorControls.
    static func loadLUT(named name: String) -> CGImage? {
        if let cached = lutCache[name] {
            return cached
        }

        guard let uiImage = UIImage(named: name) else {
            print("LUT not found in bundle: \(name)")
            return nil
        }

        guard let cgImage = uiImage.cgImage else { return nil }
        lutCache[name] = cgImage
        return cgImage
    }

    /// Preload all LUTs at launch so filter switching is instant.
    static func preloadAll() {
        let names = [
            "lut_all_points",
            "filter_classic_film",
            "filter_greenland",
            "filter_retro_film",
            "filter_rosa",
            "new_filter_blackcurrant",
            "new_filter_cyberpunk",
            "new_filter_equanimity",
            "filter_night_style_cyberpunk",
            "filter_night_style_dream_light",
            "filter_night_style_blue_ice",
            "lut1",
            "daily_lut"
        ]
        for name in names {
            _ = loadLUT(named: name)
        }
    }

    static func clearCache() {
        lutCache.removeAll()
    }
}
