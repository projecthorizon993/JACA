//
//  RealCameraEngine.swift
//  ios-camera-app
//
//  Wires real AVFoundation hardware behind the CameraKit CameraEngine protocol.
//  LUT filtering from decompiled Android APKs is applied during capture.
//  Captured photos are saved to the device photo library.
//

import SwiftUI
import AVFoundation
import CoreImage
import CoreVideo
import Photos

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

    // MARK: - Frame callback for filtered preview

    /// Called on main thread with each filtered frame (LUT applied).
    var onFilteredFrame: ((UIImage) -> Void)?

    /// Current LUT settings applied to the preview pipeline.
    var currentLUT: CGImage? = nil
    var currentLUTIntensity: Float = 1.0
    var currentFilterType: Int = 0

    /// Current watermark settings applied to preview and capture.
    var currentWatermark: WatermarkSettings = WatermarkSettings()

    // MARK: - Initialization

    override init() {
        super.init()
        setupSession()
    }

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Camera device - prefer back wide angle camera
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
        photoOutput.isHighResolutionCaptureEnabled = true
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            self.photoOutput = photoOutput
        }

        session.commitConfiguration()
    }

    /// Start the capture session with completion handler.
    func start(completion: ((Bool) -> Void)? = nil) {
        if session.isRunning {
            completion?(true)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async {
                completion?(self?.session.isRunning ?? false)
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

    func capture(raw: Bool, hevc: Bool, bracket: Bool, watermark: WatermarkSettings) async throws -> Image {
        guard let photoOutput = photoOutput else {
            throw CameraEngineError.noPhotoOutput
        }

        return try await withCheckedThrowingContinuation { continuation in
            let settings: AVCapturePhotoSettings

            if raw {
                // DNG (RAW) capture — use Bayer RAW pixel format
                if let rawType = photoOutput.availableRawPhotoPixelFormatTypes.first {
                    settings = AVCapturePhotoSettings(rawPixelFormatType: rawType)
                } else {
                    // Fallback: JPEG if RAW not supported
                    settings = AVCapturePhotoSettings()
                    settings.isHighResolutionCaptureEnabled = true
                    settings.jpegQuality = 1.0
                }
            } else if hevc {
                // HEVC capture — HEIF/HEVC compressed format
                settings = AVCapturePhotoSettings()
                settings.isHighResolutionCaptureEnabled = true
                if #available(iOS 11.0, *) {
                    settings.isHEVCPhotoQualityPrioritizationEnabled = true
                }
                settings.jpegQuality = 1.0
            } else {
                // Standard JPEG capture
                settings = AVCapturePhotoSettings()
                settings.isHighResolutionCaptureEnabled = true
                settings.jpegQuality = 1.0
            }

            photoOutput.capturePhoto(with: settings, delegate: PhotoCaptureDelegate { [weak self] result in
                switch result {
                case .success(let image):
                    // Apply watermark to captured photo if enabled
                    var finalImage = image
                    if watermark.isEnabled {
                        let uiImage = UIImage(image: image)
                        let watermarked = WatermarkManager.applyWatermark(
                            to: uiImage,
                            style: watermark.style,
                            position: watermark.position,
                            opacity: watermark.opacity,
                            scale: watermark.scale
                        )
                        finalImage = Image(uiImage: watermarked)
                    }

                    // Save to photo library
                    self?.saveToPhotoLibrary(image: finalImage) { saveResult in
                        switch saveResult {
                        case .success:
                            continuation(.success(finalImage))
                        case .failure(let error):
                            print("Failed to save to photo library: \(error)")
                            continuation(.success(finalImage)) // Still return image even if save fails
                        }
                    }
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            })
        }
    }

    /// Save a SwiftUI Image to the device photo library.
    private func saveToPhotoLibrary(image: Image, completion: @escaping (Result<Void, Error>) -> Void) {
        let uiImage = UIImage(image: image)
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized || status == .limited else {
                completion(.failure(CameraEngineError.photoLibraryAccessDenied))
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
            }) { success, error in
                if let error = error {
                    completion(.failure(error))
                } else if success {
                    completion(.success(()))
                } else {
                    completion(.failure(CameraEngineError.photoLibrarySaveFailed))
                }
            }
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }

        // Compute 48-bin histogram from luminance
        computeHistogram(from: pixelBuffer)

        // Apply LUT filter pipeline with watermark and dispatch filtered frame to main thread
        let settings = FilterSettings(
            lut: currentLUT,
            intensity: currentLUTIntensity,
            type: currentFilterType,
            color: ColorAdjustment()
        )
        let filtered = filterPipeline.apply(
            to: pixelBuffer,
            settings: settings,
            watermark: currentWatermark
        )

        DispatchQueue.main.async { [weak self] in
            self?.onFilteredFrame?(filtered)
        }
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
    case photoLibraryAccessDenied
    case photoLibrarySaveFailed
}
