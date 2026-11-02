//
//  CameraViewController.swift
//  ios-camera-app
//
//  Hosts the CameraKit SwiftUI CameraScreen with a real AVFoundation engine.
//  LUT filtering from decompiled Android APKs is applied during capture.
//

import UIKit
import SwiftUI
import AVFoundation
import CoreImage

class CameraViewController: UIViewController {

    private var hostingController: UIHostingController<CameraScreen>?
    private let cameraEngine = RealCameraEngine()
    private let filterPipeline = FilterPipeline()

    // MARK: - UI

    private let filteredPreviewView = UIImageView()
    private let lutSegmentedControl = UISegmentedControl()

    // MARK: - State

    private var currentLUTIndex: Int = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
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

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .black

        // Filtered preview — shows camera frames with LUT applied
        filteredPreviewView.translatesAutoresizingMaskIntoConstraints = false
        filteredPreviewView.contentMode = .scaleAspectFill
        filteredPreviewView.clipsToBounds = true
        filteredPreviewView.backgroundColor = .black
        view.addSubview(filteredPreviewView)

        // LUT filter selector
        lutSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        lutSegmentedControl.insertSegment(withTitle: "None", at: 0, animated: false)
        for (index, name) in LUTManager.availableLUTs.enumerated() {
            let displayName = name.replacingOccurrences(of: "_", with: " ").capitalized
            lutSegmentedControl.insertSegment(withTitle: displayName, at: index + 1, animated: false)
        }
        lutSegmentedControl.selectedSegmentIndex = 0
        lutSegmentedControl.addTarget(self, action: #selector(lutChanged(_:)), for: .valueChanged)
        view.addSubview(lutSegmentedControl)

        NSLayoutConstraint.activate([
            filteredPreviewView.topAnchor.constraint(equalTo: view.topAnchor),
            filteredPreviewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filteredPreviewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filteredPreviewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            lutSegmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            lutSegmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            lutSegmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            lutSegmentedControl.heightAnchor.constraint(equalToConstant: 32)
        ])
    }

    private func setupSwiftUICamera() {
        let screen = CameraScreen { PlaceholderScene() }
        screen.model.cameraEngine = cameraEngine

        // Wire filtered frame callback — displays LUT-applied preview
        cameraEngine.onFilteredFrame = { [weak self] image in
            self?.filteredPreviewView.image = image
        }

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

    // MARK: - LUT filter selection

    @objc private func lutChanged(_ sender: UISegmentedControl) {
        currentLUTIndex = sender.selectedSegmentIndex

        if currentLUTIndex == 0 {
            // "None" — no LUT
            cameraEngine.currentLUT = nil
            cameraEngine.currentFilterType = 0
        } else {
            let lutIndex = currentLUTIndex - 1
            let lutName = LUTManager.availableLUTs[lutIndex]
            cameraEngine.currentLUT = LUTManager.loadLUT(named: lutName)
            cameraEngine.currentFilterType = 1 // LUT-based filter
        }
        cameraEngine.currentLUTIntensity = 1.0
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
