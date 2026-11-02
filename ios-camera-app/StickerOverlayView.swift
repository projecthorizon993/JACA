//
//  StickerOverlayView.swift
//  ios-camera-app
//
//  Sticker overlays ported from decompiled Android camera apps.
//  Source: sticker/material/* PNGs + ZIP bundles from OnePlus and Vivo APKs.
//

import UIKit

class StickerOverlayView: UIView {

    private var stickers: [Sticker] = []

    struct Sticker {
        let image: UIImage
        var frame: CGRect
        var scale: CGFloat = 1.0
        var rotation: CGFloat = 0
        var isUserPlaced: Bool = false
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    /// Add a sticker from a UIImage loaded from bundle assets.
    func addSticker(named name: String, at position: CGPoint, size: CGSize) {
        guard let image = UIImage(named: name) else {
            print("Sticker not found: \(name)")
            return
        }
        let sticker = Sticker(
            image: image,
            frame: CGRect(x: position.x - size.width / 2, y: position.y - size.height / 2, width: size.width, height: size.height),
            isUserPlaced: false
        )
        stickers.append(sticker)
        setNeedsDisplay()
    }

    func clearStickers() {
        stickers.removeAll()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        for sticker in stickers {
            context.saveGState()
            context.translateBy(x: sticker.frame.midX, y: sticker.frame.midY)
            context.scaleBy(x: sticker.scale, y: sticker.scale)
            context.rotate(by: sticker.rotation)
            sticker.image.draw(in: CGRect(
                x: -sticker.frame.size.width / 2,
                y: -sticker.frame.size.height / 2,
                width: sticker.frame.size.width,
                height: sticker.frame.size.height
            ))
            context.restoreGState()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        if let index = stickers.firstIndex(where: { $0.frame.contains(point) }) {
            stickers[index].isUserPlaced = true
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        for i in stickers.indices where stickers[i].isUserPlaced {
            stickers[i].frame.origin = CGPoint(x: point.x - stickers[i].frame.width / 2, y: point.y - stickers[i].frame.height / 2)
        }
        setNeedsDisplay()
    }
}
