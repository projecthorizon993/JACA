//
//  CameraViewController.swift
//  ios-camera-app
//
//  Hosts the CameraKit SwiftUI CameraScreen with a real AVFoundation engine.
//  LUT filtering from decompiled Android APKs is applied during capture.
//

import UIKit
import SwiftUI

class CameraViewController: UIViewController {

    private var hostingController: UIHostingController<CameraScreen>?
    private let cameraEngine = RealCameraEngine()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSwiftUICamera()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        cameraEngine.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraEngine.stop()
    }

    private func setupSwiftUICamera() {
        let screen = CameraScreen { PlaceholderScene() }
        screen.model.cameraEngine = cameraEngine

        let hosting = UIHostingController(rootView: screen)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        hosting.view.backgroundColor = .clear

        addChild(hosting)
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hostingController = hosting
    }
}

// MARK: - Placeholder scene (replaced by AVCaptureVideoPreviewLayer in phase 2)

struct PlaceholderScene: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0x3F56A0), Color(hex: 0x6483C9), Color(hex: 0xE3B08A),
                                Color(hex: 0x33457F), Color(hex: 0x233466)],
                       startPoint: .top, endPoint: .bottom)
    }
}
