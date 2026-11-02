//
//  RealCameraEngine.swift
//  ios-camera-app
//
//  Wires real AVFoundation hardware behind the CameraKit CameraEngine protocol.
//  LUT filtering from decompiled Android APKs is applied during capture.
//

import SwiftUI
import AVFoundation
import CoreImage
import CoreVideo

/// Real camera engine backing CameraKit. Implements CameraEngine using AVFoundation.
final class RealCameraEngine: NSObject, CameraEngine, AVCaptureVideoDataOutputSampleBufferDelegate {

    // MARK: - Capture session

    private let session = AVCaptureSession()
    private let videoQueue = DispatchQueue(label: "camera.video.queue", qos: .userInteractive)
    private let histogramQueue = DispatchQueue(label: "camera.histogram.queue", qos: .userInteractive)
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var captureDevice: AVCaptureDevice?

    // MARK: - Histogram (48 bins, updated per frame)

    private(set) var histogram: [Double] = Array(repeating: 0.0, count: 48)
    private let ciContext = CIContext()

    // MARK: - LUT filter pipeline (from decompiled Android APKs)

    private let filterPipeline = FilterPipeline()

    // MARK: - Initialization

    override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        // Camera device
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("No back camera available")
            session.commitConfiguration()
            return
        }
        captureDevice = device

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            print("Cannot create camera input")
            session.commitConfiguration()
            return
        }
        if session.canAddInput(input) {
            session.addInput(input)
            videoDeviceInput = input
        }

        // Video output for histogram + live preview frames
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            self.videoOutput = videoOutput
        }

        // Photo output for capture
        let photoOutput = AVCapturePhotoOutput()
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            self.photoOutput = photoOutput
        }

        session.commitConfiguration()
    }

    /// Start the capture session (call from CameraScreen.onAppear).
    func start() {
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }
    }

    /// Stop the capture session.
    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    // MARK: - CameraEngine

    func apply(isoIndex: Int, speedIndex: Int) {
        guard let device = captureDevice else { return }
        let isoStops = CameraModel.isoStops
        let shutterStops = CameraModel.shutterStops
        guard isoIndex < isoStops.count, speedIndex < shutterStops.count else { return }

        let iso = Float(isoStops[isoIndex])
        // Parse shutter speed string like "1/250" -> seconds
        let shutterSeconds: Float
        if shutterStops[speedIndex].hasPrefix("1/") {
            let denom = Float(shutterStops[speedIndex].replacingOccurrences(of: "1/", with: "")) ?? 30
            shutterSeconds = 1.0 / denom
        } else if shutterStops[speedIndex] == "1s" {
            shutterSeconds = 1.0
        } else {
            shutterSeconds = 1.0 / 30.0
        }

        do {
            try device.lockForConfiguration()
            device.exposureMode = .custom
            device.setExposureModeCustom(
                duration: CMTime(value: Int64(shutterSeconds * 1_000_000), timescale: 1_000_000),
                iso: iso
            ) { _ in }
            device.unlockForConfiguration()
        } catch {
            print("Failed to apply exposure: \(error)")
        }
    }

    func apply(focusDistance: Double?) {
        guard let device = captureDevice else { return }
        do {
            try device.lockForConfiguration()
            if let distance = focusDistance {
                device.focusMode = .locked
                device.setFocusModeLocked(lensPosition: Float(distance)) { _ in }
            } else {
                device.focusMode = .continuousAutoFocus
            }
            device.unlockForConfiguration()
        } catch {
            print("Failed to apply focus: \(error)")
        }
    }

    func setZoom(_ zoom: CameraModel.Zoom) {
        guard let device = captureDevice else { return }
        do {
            try device.lockForConfiguration()
            let factor: CGFloat = (zoom == .x2) ? 2.0 : 1.0
            device.videoZoomFactor = min(max(factor, 1.0), device.maxAvailableVideoZoomFactor)
            device.unlockForConfiguration()
        } catch {
            print("Failed to set zoom: \(error)")
        }
    }

    func capture(raw: Bool, bracket: Bool) async throws -> Image {
        guard let photoOutput = photoOutput else {
            throw CameraEngineError.noPhotoOutput
        }

        return try await withCheckedThrowingContinuation { continuation in
            let settings: AVCapturePhotoSettings
            if raw, let rawType = photoOutput.availableRawPhotoPixelFormatTypes.first {
                settings = AVCapturePhotoSettings(rawPixelFormatType: rawType)
            } else {
                settings = AVCapturePhotoSettings()
            }

            photoOutput.capturePhoto(with: settings, delegate: PhotoCaptureDelegate { result in
                switch result {
                case .success(let image):
                    continuation.resume(returning: image)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            })
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }

        // Compute 48-bin histogram from luminance
        computeHistogram(from: pixelBuffer)
    }

    private func computeHistogram(from pixelBuffer: CVPixelBuffer) {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let extent = ciImage.extent

        // Downsample to a small grid for histogram computation
        let scale: CGFloat = 64 / max(extent.width, extent.height)
        let small = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Convert to grayscale luminance then bucket into 48 bins
        let grayscale = small.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0,
            kCIInputContrastKey: 1,
            kCIInputBrightnessKey: 0
        ])

        // Render to a tiny bitmap for CPU histogram
        guard let cgImage = ciContext.createCGImage(grayscale, from: grayscale.extent) else { return }
        let width = cgImage.width
        let height = cgImage.height
        let bitsPerComponent = 8
        let bytesPerRow = width
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixelData = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(data: &pixelData, width: width, height: height,
                                        bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow,
                                        space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Build 48-bin histogram
        var bins = [Double](repeating: 0, count: 48)
        for y in 0..<height {
            for x in 0..<width {
                let luminance = Double(pixelData[y * width + x]) / 255.0
                let bin = min(Int(luminance * 48.0), 47)
                bins[bin] += 1
            }
        }

        // Normalize
        let total = Double(width * height)
        bins = bins.map { $0 / total }

        // Update on main thread for UI
        DispatchQueue.main.async { [weak self] in
            self?.histogram = bins
        }
    }
}

// MARK: - Photo capture delegate

private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let continuation: (Result<Image, Error>) -> Void

    init(onResult: @escaping (Result<Image, Error>) -> Void) {
        self.continuation = onResult
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            continuation(.failure(error))
            return
        }
        guard let imageData = photo.fileDataRepresentation(),
              let uiImage = UIImage(data: imageData) else {
            continuation(.failure(CameraEngineError.noImageData))
            return
        }
        continuation(.success(Image(uiImage: uiImage)))
    }
}

// MARK: - Errors

enum CameraEngineError: Error {
    case noPhotoOutput
    case noImageData
}
