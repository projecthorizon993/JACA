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
