//
//  LUTManager.swift
//  ios-camera-app
//
//  Loads LUT textures extracted from decompiled Android camera APKs
//  (OnePlus, Vivo). LUTs are stored in Assets.xcassets/LUTs.lutcollection/.
//
//  Source assets:
//    - lut_all_points.png          (OnePlus filters_res)
//    - cartoon1_lut.png            (Vivo cartoon1)
//    - dv_record_lut.png           (Vivo DVFilter)
//    - dv_screen_lut.png           (Vivo DVFilter)
//    - aifilter_beach.png          (Vivo aifilter)
//    - aifilter_cyberpunk.png      (Vivo aifilter)
//    - aifilter_night.png          (Vivo aifilter)
//    - aifilter_portrait.png       (Vivo aifilter)
//    - aifilter_sunset.png         (Vivo aifilter)
//

import UIKit
import CoreImage

class LUTManager {

    private static var lutCache: [String: CGImage] = [:]

    /// All LUT names available in Assets.xcassets/LUTs.lutcollection/
    static let availableLUTs: [String] = [
        "lut_all_points",
        "cartoon1_lut",
        "dv_record_lut",
        "dv_screen_lut",
        "aifilter_beach",
        "aifilter_cyberpunk",
        "aifilter_night",
        "aifilter_portrait",
        "aifilter_sunset"
    ]

    /// Load a LUT PNG from the app bundle asset catalog.
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
        for name in availableLUTs {
            _ = loadLUT(named: name)
        }
    }

    static func clearCache() {
        lutCache.removeAll()
    }
}
