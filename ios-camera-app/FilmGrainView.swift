//
//  FilmGrainView.swift
//  ios-camera-app
//
//  Film grain overlay ported from film_grain_small.bin (4MB) extracted from
//  oneplus-camera-3.102.28.apk assets/.
//
//  Staged at: C:\Users\Admin\AppData\Local\Temp\opencode\ios-camera-assets\grain\
//

import UIKit

class FilmGrainView: UIView {

    private let grainImage: UIImage?

    init() {
        // Load film grain from asset bundle. The .bin would need to be converted
        // to a PNG texture before being added to Assets.xcassets.
        grainImage = UIImage(named: "film_grain")
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        alpha = 0.15 // subtle grain intensity
    }

    required init?(coder: NSCoder) {
        grainImage = UIImage(named: "film_grain")
        super.init(coder: coder)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        alpha = 0.15
    }

    override class var layerClass: AnyClass { return CALayer.self }

    override func layoutSubviews() {
        super.layoutSubviews()
        if let grainImage = grainImage {
            layer.contents = grainImage.cgImage
            layer.contentsGravity = .resizeAspectFill
        }
    }
}
