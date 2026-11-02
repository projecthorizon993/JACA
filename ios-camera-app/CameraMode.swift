//
//  CameraMode.swift
//  ios-camera-app
//
//  Camera modes ported from decompiled Android camera apps:
//  - Photo mode: still capture with filters
//  - Video mode: video recording
//  - Pro mode: manual controls (ISO, shutter, focus, white balance)
//

import Foundation
import UIKit

enum CameraMode: Int, CaseIterable {
    case photo = 0
    case video = 1
    case pro = 2

    var title: String {
        switch self {
        case .photo: return "Photo"
        case .video: return "Video"
        case .pro: return "Pro"
        }
    }

    var icon: String {
        switch self {
        case .photo: return "📷"
        case .video: return "🎥"
        case .pro: return "⚙️"
        }
    }
}

struct ColorAdjustment {
    var brightness: Float = 0.0    // -1.0 to 1.0
    var contrast: Float = 1.0      // 0.0 to 2.0
    var saturation: Float = 1.0    // 0.0 to 2.0
    var temperature: Float = 6500.0 // 2000 to 10000 Kelvin
    var tint: Float = 0.0          // -1.0 to 1.0 (green to magenta)
    var sharpness: Float = 0.0     // 0.0 to 1.0
}

struct ProSettings {
    var iso: Float = 100.0         // ISO sensitivity
    var shutterSpeed: Float = 1.0 / 30.0 // seconds
    var focusDistance: Float = 0.0  // 0.0 to 1.0 (macro to infinity)
    var whiteBalance: Float = 5500.0  // Kelvin
    var exposureCompensation: Float = 0.0 // -4.0 to 4.0 EV
}

struct FilterSettings {
    var lut: CGImage?
    var intensity: Float = 1.0
    var type: Int = 0  // filter segment index
    var color: ColorAdjustment = ColorAdjustment()
}
