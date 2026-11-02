//
//  CameraViewController.swift
//  ios-camera-app
//
//  Ported from decompiled Android camera apps (OnePlus, Vivo, Xiaomi).
//  Capture pipeline: AVFoundation → CVPixelBuffer → FilterPipeline → UIImageView preview.
//

import UIKit
import AVFoundation
import CoreImage

class CameraViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - UI

    private let previewImageView = UIImageView()
    private let shutterButton = UIButton(type: .system)
    private let filterIntensitySlider = UISlider()
    private let filterSegmentedControl = UISegmentedControl(items: ["None", "Classic Film", "Cyberpunk", "Greenland", "Night Style"])

    // MARK: - Capture

    private let captureSession = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let videoQueue = DispatchQueue(label: "camera.video.queue", qos: .userInteractive)
    private var captureDevice: AVCaptureDevice?

    // MARK: - Filtering

    private let filterPipeline = FilterPipeline()
    private var currentLUT: CGImage?
    private var currentIntensity: Float = 1.0

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCaptureSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !captureSession.isRunning {
            captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession.stopRunning()
    }

    // MARK: - Setup

    private func setupUI() {
        view.backgroundColor = .black

        previewImageView.translatesAutoresizingMaskIntoConstraints = false
        previewImageView.contentMode = .scaleAspectFill
        previewImageView.clipsToBounds = true
        view.addSubview(previewImageView)

        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.setTitle("📷", for: .normal)
        shutterButton.titleLabel?.font = UIFont.systemFont(ofSize: 44)
        shutterButton.backgroundColor = .white
        shutterButton.layer.cornerRadius = 35
        shutterButton.addTarget(self, action: #selector(didTapShutter), for: .touchUpInside)
        view.addSubview(shutterButton)

        filterSegmentedControl.translatesAutoresizingMaskIntoConstraints = false
        filterSegmentedControl.selectedSegmentIndex = 0
        filterSegmentedControl.addTarget(self, action: #selector(filterChanged(_:)), for: .valueChanged)
        view.addSubview(filterSegmentedControl)

        filterIntensitySlider.translatesAutoresizingMaskIntoConstraints = false
        filterIntensitySlider.minimumValue = 0
        filterIntensitySlider.maximumValue = 1
        filterIntensitySlider.value = 1
        filterIntensitySlider.addTarget(self, action: #selector(intensityChanged(_:)), for: .valueChanged)
        view.addSubview(filterIntensitySlider)

        NSLayoutConstraint.activate([
            previewImageView.topAnchor.constraint(equalTo: view.topAnchor),
            previewImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            previewImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            previewImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -40),
            shutterButton.widthAnchor.constraint(equalToConstant: 70),
            shutterButton.heightAnchor.constraint(equalToConstant: 70),

            filterSegmentedControl.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            filterSegmentedControl.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            filterSegmentedControl.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -20),

            filterIntensitySlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 40),
            filterIntensitySlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -40),
            filterIntensitySlider.bottomAnchor.constraint(equalTo: filterSegmentedControl.topAnchor, constant: -16)
        ])
    }

    private func setupCaptureSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("No back camera available")
            captureSession.commitConfiguration()
            return
        }
        captureDevice = device

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            print("Cannot create camera input")
            captureSession.commitConfiguration()
            return
        }
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }

        captureSession.commitConfiguration()
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }

        let filtered = filterPipeline.apply(
            to: pixelBuffer,
            lut: currentLUT,
            intensity: currentIntensity,
            filterType: filterSegmentedControl.selectedSegmentIndex
        )

        DispatchQueue.main.async { [weak self] in
            self?.previewImageView.image = filtered
        }
    }

    @objc private func didTapShutter() {
        print("Shutter tapped")
    }

    @objc private func filterChanged(_ sender: UISegmentedControl) {
        switch sender.selectedSegmentIndex {
        case 1: currentLUT = LUTManager.loadLUT(named: "filter_classic_film")
        case 2: currentLUT = LUTManager.loadLUT(named: "new_filter_cyberpunk")
        case 3: currentLUT = LUTManager.loadLUT(named: "filter_greenland")
        case 4: currentLUT = LUTManager.loadLUT(named: "filter_night_style_cyberpunk")
        default: currentLUT = nil
        }
    }

    @objc private func intensityChanged(_ sender: UISlider) {
        currentIntensity = sender.value
    }
}
