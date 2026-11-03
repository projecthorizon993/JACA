//
//  CameraViewController.swift
//  ios-camera-app
//
//  Hosts the CameraKit SwiftUI CameraScreen with a real AVFoundation engine.
//  LUT filtering, watermarks, and capture formats (JPG/HEVC/DNG) from decompiled
//  Android camera APKs are applied during capture.
//

import UIKit
import SwiftUI
import AVFoundation
import CoreImage

class CameraViewController: UIViewController {

    private var hostingController: UIHostingController<CameraScreen>?
    private var screen: CameraScreen!
    private let cameraEngine = RealCameraEngine()
    private let filterPipeline = FilterPipeline()

    // MARK: - UI

    private let filteredPreviewView = UIImageView()
    private let lutSegmentedControl = UISegmentedControl()
    private let formatSegmentedControl = UISegmentedControl(items: ["JPG", "HEVC", "DNG"])
    private let watermarkStyleControl = UISegmentedControl()
    private let watermarkPositionControl = UISegmentedControl(items: ["BR", "BL", "TR", "TL", "C"])
    private let watermarkOpacitySlider = UISlider()
    private let watermarkScaleSlider = UISlider()
    private let watermarkToggle = UISwitch()
    private let leicaColorControl = UISegmentedControl(items: ["Off", "Classic", "Vivid", "B&W"])
    private let whiteBalanceControl = UISegmentedControl(items: WhiteBalanceMode.allCases.map { $0.rawValue })
    private let beautyIntensitySlider = UISlider()
    private let portraitIntensitySlider = UISlider()
    private let nightModeSlider = UISlider()
    private let aiSceneDetectionToggle = UISwitch()
    private let flipButton = UIButton(type: .system)
    private let cameraModeControl = UISegmentedControl(items: CameraMode.allCases.map { $0.rawValue })

    // MARK: - State

    private var currentLUTIndex: Int = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupSwiftUICamera()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        cameraEngine.start { [weak self] success in
            if !success {
                DispatchQueue.main.async {
                    self?.showCameraUnavailableAlert()
                }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        cameraEngine.stop()
    }

    private func showCameraUnavailableAlert() {
        let alert = UIAlertController(title: "Camera Unavailable",
                                      message: "No camera device found on this device.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .black

        // Filtered preview — shows camera frames with LUT + watermark applied
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

        // Capture format selector
        formatSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        formatSegmentedControl.selectedSegmentIndex = 0
        formatSegmentedControl.addTarget(self, action: #selector(formatChanged(_:)), for: .valueChanged)
        view.addSubview(formatSegmentedControl)

        // Watermark style selector
        watermarkStyleControl.translatesAutoresizingMaskIntoConstraints = false
        watermarkStyleControl.insertSegment(withTitle: "Off", at: 0, animated: false)
        for (index, style) in WatermarkStyle.allCases.enumerated() where style != .off {
            watermarkStyleControl.insertSegment(withTitle: style.rawValue, at: index, animated: false)
        }
        watermarkStyleControl.selectedSegmentIndex = 0
        watermarkStyleControl.addTarget(self, action: #selector(watermarkStyleChanged(_:)), for: .valueChanged)
        view.addSubview(watermarkStyleControl)

        // Leica color profile selector
        leicaColorControl.translatesAutoresizingMaskIntoConstraints = false
        leicaColorControl.selectedSegmentIndex = 0
        leicaColorControl.addTarget(self, action: #selector(leicaColorChanged(_:)), for: .valueChanged)
        view.addSubview(leicaColorControl)

        // White balance selector
        whiteBalanceControl.translatesAutoresizingMaskIntoConstraints = false
        whiteBalanceControl.selectedSegmentIndex = WhiteBalanceMode.allCases.firstIndex(of: screen.model.whiteBalanceMode) ?? 0
        whiteBalanceControl.addTarget(self, action: #selector(whiteBalanceChanged(_:)), for: .valueChanged)
        view.addSubview(whiteBalanceControl)

        // Beauty intensity slider
        beautyIntensitySlider.translatesAutoresizingMaskIntoConstraints = false
        beautyIntensitySlider.minimumValue = 0
        beautyIntensitySlider.maximumValue = 1
        beautyIntensitySlider.value = 0
        beautyIntensitySlider.addTarget(self, action: #selector(beautyIntensityChanged(_:)), for: .valueChanged)
        view.addSubview(beautyIntensitySlider)

        // Portrait intensity slider
        portraitIntensitySlider.translatesAutoresizingMaskIntoConstraints = false
        portraitIntensitySlider.minimumValue = 0
        portraitIntensitySlider.maximumValue = 1
        portraitIntensitySlider.value = 0
        portraitIntensitySlider.addTarget(self, action: #selector(portraitIntensityChanged(_:)), for: .valueChanged)
        view.addSubview(portraitIntensitySlider)

        // Night mode intensity slider
        nightModeSlider.translatesAutoresizingMaskIntoConstraints = false
        nightModeSlider.minimumValue = 0
        nightModeSlider.maximumValue = 1
        nightModeSlider.value = 0
        nightModeSlider.addTarget(self, action: #selector(nightIntensityChanged(_:)), for: .valueChanged)
        view.addSubview(nightModeSlider)

        // AI scene detection toggle
        aiSceneDetectionToggle.translatesAutoresizingMaskIntoConstraints = false
        aiSceneDetectionToggle.addTarget(self, action: #selector(aiSceneDetectionToggled(_:)), for: .valueChanged)
        view.addSubview(aiSceneDetectionToggle)

        // Flip camera button
        flipButton.translatesAutoresizingMaskIntoConstraints = false
        flipButton.setImage(UIImage(systemName: "camera.rotate"), for: .normal)
        flipButton.tintColor = .white
        flipButton.addTarget(self, action: #selector(flipCamera(_:)), for: .touchUpInside)
        view.addSubview(flipButton)

        // Camera mode selector (Photo/Video/Pro)
        cameraModeControl.translatesAutoresizingMaskIntoConstraints = false
        cameraModeControl.selectedSegmentIndex = CameraMode.allCases.firstIndex(of: screen.model.cameraMode) ?? 0
        cameraModeControl.addTarget(self, action: #selector(cameraModeChanged(_:)), for: .valueChanged)
        view.addSubview(cameraModeControl)

        // Watermark position selector
        watermarkPositionControl.translatesAutoresizingMaskIntoConstraints = false
        watermarkPositionControl.selectedSegmentIndex = 1 // Bottom Right
        watermarkPositionControl.addTarget(self, action: #selector(watermarkPositionChanged(_:)), for: .valueChanged)
        view.addSubview(watermarkPositionControl)

        // Watermark opacity slider
        watermarkOpacitySlider.translatesAutoresizingMaskIntoConstraints = false
        watermarkOpacitySlider.minimumValue = 0
        watermarkOpacitySlider.maximumValue = 1
        watermarkOpacitySlider.value = 0.8
        watermarkOpacitySlider.addTarget(self, action: #selector(watermarkOpacityChanged(_:)), for: .valueChanged)
        view.addSubview(watermarkOpacitySlider)

        // Watermark scale slider
        watermarkScaleSlider.translatesAutoresizingMaskIntoConstraints = false
        watermarkScaleSlider.minimumValue = 0.05
        watermarkScaleSlider.maximumValue = 0.5
        watermarkScaleSlider.value = 0.15
        watermarkScaleSlider.addTarget(self, action: #selector(watermarkScaleChanged(_:)), for: .valueChanged)
        view.addSubview(watermarkScaleSlider)

        // Watermark toggle
        watermarkToggle.translatesAutoresizingMaskIntoConstraints = false
        watermarkToggle.addTarget(self, action: #selector(watermarkToggled(_:)), for: .valueChanged)
        view.addSubview(watermarkToggle)

        NSLayoutConstraint.activate([
            filteredPreviewView.topAnchor.constraint(equalTo: view.topAnchor),
            filteredPreviewView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            filteredPreviewView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            filteredPreviewView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            lutSegmentedControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
            lutSegmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            lutSegmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            lutSegmentedControl.heightAnchor.constraint(equalToConstant: 32),

            formatSegmentedControl.topAnchor.constraint(equalTo: lutSegmentedControl.bottomAnchor, constant: 8),
            formatSegmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            formatSegmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            formatSegmentedControl.heightAnchor.constraint(equalToConstant: 32),

            watermarkStyleControl.topAnchor.constraint(equalTo: formatSegmentedControl.bottomAnchor, constant: 8),
            watermarkStyleControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            watermarkStyleControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            watermarkStyleControl.heightAnchor.constraint(equalToConstant: 32),

            leicaColorControl.topAnchor.constraint(equalTo: watermarkStyleControl.bottomAnchor, constant: 6),
            leicaColorControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            leicaColorControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            leicaColorControl.heightAnchor.constraint(equalToConstant: 32),

            whiteBalanceControl.topAnchor.constraint(equalTo: leicaColorControl.bottomAnchor, constant: 6),
            whiteBalanceControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            whiteBalanceControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            whiteBalanceControl.heightAnchor.constraint(equalToConstant: 32),

            flipButton.topAnchor.constraint(equalTo: whiteBalanceControl.bottomAnchor, constant: 6),
            flipButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            flipButton.widthAnchor.constraint(equalToConstant: 32),
            flipButton.heightAnchor.constraint(equalToConstant: 32),

            cameraModeControl.topAnchor.constraint(equalTo: flipButton.bottomAnchor, constant: 6),
            cameraModeControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            cameraModeControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            cameraModeControl.heightAnchor.constraint(equalToConstant: 32),

            watermarkPositionControl.topAnchor.constraint(equalTo: cameraModeControl.bottomAnchor, constant: 6),
            watermarkPositionControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            watermarkPositionControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            watermarkPositionControl.heightAnchor.constraint(equalToConstant: 30),

            watermarkOpacitySlider.topAnchor.constraint(equalTo: watermarkPositionControl.bottomAnchor, constant: 6),
            watermarkOpacitySlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            watermarkOpacitySlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            watermarkScaleSlider.topAnchor.constraint(equalTo: watermarkOpacitySlider.bottomAnchor, constant: 6),
            watermarkScaleSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            watermarkScaleSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            watermarkToggle.centerYAnchor.constraint(equalTo: watermarkScaleSlider.centerYAnchor),
            watermarkToggle.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            beautyIntensitySlider.topAnchor.constraint(equalTo: watermarkScaleSlider.bottomAnchor, constant: 6),
            beautyIntensitySlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            beautyIntensitySlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            portraitIntensitySlider.topAnchor.constraint(equalTo: beautyIntensitySlider.bottomAnchor, constant: 6),
            portraitIntensitySlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            portraitIntensitySlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            nightModeSlider.topAnchor.constraint(equalTo: portraitIntensitySlider.bottomAnchor, constant: 6),
            nightModeSlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            nightModeSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            aiSceneDetectionToggle.topAnchor.constraint(equalTo: nightModeSlider.bottomAnchor, constant: 6),
            aiSceneDetectionToggle.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            aiSceneDetectionToggle.widthAnchor.constraint(equalToConstant: 50),
        ])
    }

    private func setupSwiftUICamera() {
        self.screen = CameraScreen { PlaceholderScene() }
        self.screen.model.cameraEngine = cameraEngine
        cameraEngine.cameraModel = screen.model

        // Wire filtered frame callback — displays LUT + watermark applied preview
        cameraEngine.onFilteredFrame = { [weak self] image in
            self?.filteredPreviewView.image = image
        }

        // Wire histogram updates from camera engine to model
        cameraEngine.histogram // access to trigger KVO-like observation
        // We poll the histogram on a timer since @Observable doesn't auto-publish
        // from a non-Observable object
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.screen.model.updateHistogram(self.cameraEngine.histogram)
        }

        // Wire face bounds from camera engine to model
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.screen.model.faceBounds = self.cameraEngine.faceBounds
        }

        // Wire bracketed photos from camera engine to model
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if !self.cameraEngine.bracketedPhotos.isEmpty {
                self.screen.model.bracketedPhotos = self.cameraEngine.bracketedPhotos.map { Image(uiImage: $0) }
                self.cameraEngine.bracketedPhotos = [] // clear after reading
            }
        }

        // Wire level degrees from camera engine to model
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.screen.model.levelDegrees = self.cameraEngine.levelDegrees
        }
        formatSegmentedControl.addTarget(self, action: #selector(formatChanged(_:)), for: .valueChanged)

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
        let index = sender.selectedSegmentIndex

        if index == 0 {
            cameraEngine.currentLUT = nil
            cameraEngine.currentFilterType = 0
        } else {
            let lutIndex = index - 1
            let lutName = LUTManager.availableLUTs[lutIndex]
            cameraEngine.currentLUT = LUTManager.loadLUT(named: lutName)
            cameraEngine.currentFilterType = 1 // LUT-based filter
        }
        cameraEngine.currentLUTIntensity = 1.0
    }

    @objc private func formatChanged(_ sender: UISegmentedControl) {
        screen.model.captureFormat = CameraModel.CaptureFormat.allCases[sender.selectedSegmentIndex]
    }

    // MARK: - Watermark controls

    @objc private func watermarkStyleChanged(_ sender: UISegmentedControl) {
        let styles = WatermarkStyle.allCases
        let style = styles[sender.selectedSegmentIndex]
        screen.model.watermarkStyle = style
        screen.model.watermarkEnabled = style != .off
        watermarkToggle.isOn = style != .off

        // Sync to camera engine for preview
        syncWatermarkToEngine()
    }

    @objc private func leicaColorChanged(_ sender: UISegmentedControl) {
        let profiles = LeicaColorProfile.allCases
        screen.model.leicaColorProfile = profiles[sender.selectedSegmentIndex]
        cameraEngine.currentLeicaProfile = profiles[sender.selectedSegmentIndex]
    }

    @objc private func whiteBalanceChanged(_ sender: UISegmentedControl) {
        let modes = WhiteBalanceMode.allCases
        let mode = modes[sender.selectedSegmentIndex]
        screen.model.whiteBalanceMode = mode
        cameraEngine.applyWhiteBalance(mode)
    }

    @objc private func flipCamera(_ sender: UIButton) {
        cameraEngine.switchCamera()
    }

    @objc private func beautyIntensityChanged(_ sender: UISlider) {
        cameraEngine.filterPipeline.beautyIntensity = sender.value
        screen.model.beautyIntensity = sender.value
    }

    @objc private func portraitIntensityChanged(_ sender: UISlider) {
        cameraEngine.filterPipeline.portraitIntensity = sender.value
        screen.model.portraitIntensity = sender.value
    }

    @objc private func nightIntensityChanged(_ sender: UISlider) {
        cameraEngine.filterPipeline.nightIntensity = sender.value
        screen.model.nightIntensity = sender.value
    }

    @objc private func aiSceneDetectionToggled(_ sender: UISwitch) {
        screen.model.aiSceneDetectionEnabled = sender.isOn
        cameraEngine.cameraModel = screen.model
    }

    @objc private func cameraModeChanged(_ sender: UISegmentedControl) {
        let modes = CameraMode.allCases
        screen.model.cameraMode = modes[sender.selectedSegmentIndex]
    }

    @objc private func watermarkPositionChanged(_ sender: UISegmentedControl) {
        let positions = WatermarkPosition.allCases
        screen.model.watermarkPosition = positions[sender.selectedSegmentIndex]
        syncWatermarkToEngine()
    }

    @objc private func watermarkOpacityChanged(_ sender: UISlider) {
        screen.model.watermarkOpacity = sender.value
        syncWatermarkToEngine()
    }

    @objc private func watermarkScaleChanged(_ sender: UISlider) {
        screen.model.watermarkScale = sender.value
        syncWatermarkToEngine()
    }

    @objc private func watermarkToggled(_ sender: UISwitch) {
        screen.model.watermarkEnabled = sender.isOn
        if sender.isOn && screen.model.watermarkStyle == .off {
            screen.model.watermarkStyle = .leicaSignature
            watermarkStyleControl.selectedSegmentIndex = WatermarkStyle.allCases.firstIndex(of: .leicaSignature) ?? 1
        }
        syncWatermarkToEngine()
    }

    private func syncWatermarkToEngine() {
        cameraEngine.currentWatermark = WatermarkSettings(
            style: screen.model.watermarkStyle,
            position: screen.model.watermarkPosition,
            opacity: screen.model.watermarkOpacity,
            scale: screen.model.watermarkScale,
            isEnabled: screen.model.watermarkEnabled,
            leicaProfile: screen.model.leicaColorProfile
        )
        cameraEngine.currentLeicaProfile = screen.model.leicaColorProfile
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
