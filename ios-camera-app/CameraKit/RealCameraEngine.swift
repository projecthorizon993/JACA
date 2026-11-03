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
import CoreLocation
import Photos
import Vision

/// Real camera engine backing CameraKit. Implements CameraEngine using AVFoundation.
final class RealCameraEngine: NSObject, CameraEngine, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate {

    // MARK: - Capture session

    private let session = AVCaptureSession()
    private let videoQueue = DispatchQueue(label: "camera.video.queue", qos: .userInteractive)
    private let histogramQueue = DispatchQueue(label: "camera.histogram.queue", qos: .userInteractive)
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var photoOutput: AVCapturePhotoOutput?
    private var videoOutput: AVCaptureVideoDataOutput?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var captureDevice: AVCaptureDevice?
    private let locationManager = CLLocationManager()
    private var currentBeautyIntensity: Float = 0.0
    weak var cameraModel: CameraModel?

    // MARK: - Video recording

    private var videoRecordingURL: URL?
    private(set) var isRecording: Bool = false
    /// Called on main thread when a video recording finishes and is saved.
    var onVideoRecorded: ((URL) -> Void)?

    // MARK: - Histogram (48 bins, updated per frame)

    private(set) var histogram: [Double] = Array(repeating: 0.0, count: 48)
    private let ciContext = CIContext()

    // MARK: - Face detection

    private(set) var faceBounds: [CGRect] = []
    private let faceRequest = VNDetectFaceRectanglesRequest()
    private let visionQueue = DispatchQueue(label: "camera.vision.queue", qos: .userInteractive)

    /// Bracketed exposure capture results (-1EV, 0EV, +1EV)
    private(set) var bracketedPhotos: [UIImage] = []

    /// Double exposure: first exposure stored for blending
    private var doubleExposureFirst: UIImage? = nil

    /// Current device roll angle in degrees (for level indicator)
    var levelDegrees: Double = 0.0

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

    /// Current Leica color profile applied to preview and capture.
    var currentLeicaProfile: LeicaColorProfile = .off

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

        // Movie file output for video recording
        let movieFileOutput = AVCaptureMovieFileOutput()
        if session.canAddOutput(movieFileOutput) {
            session.addOutput(movieFileOutput)
            self.movieFileOutput = movieFileOutput
        }

        session.commitConfiguration()

        // Request location permission for geotagging
        locationManager.requestWhenInUseAuthorization()
    }

    /// Start video recording to a temporary file. Returns the output URL.
    func startVideoRecording() -> URL? {
        guard let movieFileOutput = movieFileOutput, !movieFileOutput.isRecording else { return nil }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documents.appendingPathComponent("video_\(Date().timeIntervalSince1970).mp4")
        videoRecordingURL = url
        movieFileOutput.startRecording(to: url, recordingDelegate: self)
        isRecording = true
        return url
    }

    /// Stop video recording. The saved URL is delivered via onVideoRecorded.
    func stopVideoRecording() {
        guard let movieFileOutput = movieFileOutput, movieFileOutput.isRecording else { return }
        movieFileOutput.stopRecording()
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

    func applyWhiteBalance(_ mode: CameraModel.WhiteBalanceMode) {
        guard let device = captureDevice else { return }
        do {
            try device.lockForConfiguration()
            if device.isWhiteBalanceModeLockedSupported {
                device.whiteBalanceMode = .locked
                device.setWhiteBalanceModeLocked(withDeviceWhiteBalanceGains: AVCaptureDevice.WhiteBalanceGains(
                    redGain: 1.0, greenGain: 1.0, blueGain: 1.0
                )) { _ in }
            } else {
                device.whiteBalanceMode = .autoWhiteBalance
            }
            device.unlockForConfiguration()
        } catch {
            print("Failed to apply white balance: \(error)")
        }
    }

    func switchCamera() {
        session.beginConfiguration()

        // Remove existing input
        if let input = videoDeviceInput {
            session.removeInput(input)
        }

        // Determine new position from current device
        let currentPos = captureDevice?.position ?? .back
        let newPosition: AVCaptureDevice.Position = (currentPos == .back) ? .front : .back

        // Add new input from opposite camera
        guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition),
              let newInput = try? AVCaptureDeviceInput(device: newDevice) else {
            // Re-add original input if switch fails
            if let input = videoDeviceInput {
                session.addInput(input)
            }
            session.commitConfiguration()
            return
        }

        if session.canAddInput(newInput) {
            session.addInput(newInput)
            videoDeviceInput = newInput
            captureDevice = newDevice
        } else {
            // Re-add original input if switch fails
            if let input = videoDeviceInput {
                session.addInput(input)
            }
        }

        session.commitConfiguration()
    }

    func setFlashMode(_ mode: CameraModel.FlashMode) {
        guard let device = captureDevice else { return }
        do {
            try device.lockForConfiguration()
            switch mode {
            case .off:
                device.torchMode = .off
                device.flashMode = .off
            case .on:
                if device.isTorchModeSupported(.on) {
                    device.torchMode = .on
                }
                device.flashMode = .on
            case .auto:
                device.torchMode = .auto
                device.flashMode = .auto
            }
            device.unlockForConfiguration()
        } catch {
            print("Failed to set flash mode: \(error)")
        }
    }

    func capture(raw: Bool, hevc: Bool, hdr: Bool, bracket: Bool, watermark: WatermarkSettings) async throws -> Image {
        guard let photoOutput = photoOutput else {
            throw CameraEngineError.noPhotoOutput
        }

        // Double exposure mode: capture two photos and blend them
        if let model = cameraModel, model.isDoubleExposureMode {
            if doubleExposureFirst == nil {
                // First exposure — capture and store
                return try await captureSingleDoubleExposure(watermark: watermark)
            } else {
                // Second exposure — capture and blend with first
                return try await captureSecondDoubleExposure(watermark: watermark)
            }
        }

        if bracket {
            return try await captureBracketed(settings: WatermarkSettings(
                style: watermark.style,
                position: watermark.position,
                opacity: watermark.opacity,
                scale: watermark.scale,
                isEnabled: watermark.isEnabled,
                leicaProfile: watermark.leicaProfile
            ))
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
            } else if hdr {
                // HDR capture — auto HDR enabled
                settings = AVCapturePhotoSettings()
                settings.isHighResolutionCaptureEnabled = true
                if #available(iOS 13.0, *) {
                    settings.isAutoHighDynamicRangePhotoEnabled = true
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
                    // Apply Leica color profile + watermark to captured photo
                    let uiImage = UIImage(image: image)
                    var processedImage = uiImage

                    // Apply Leica color profile via CIFilter (ported from Xiaomi/Leica color science)
                    if let ciImage = CIImage(image: uiImage) {
                        let leicaProfile = watermark.leicaProfile ?? .off
                        if leicaProfile != .off {
                            processedImage = self?.applyLeicaColorProfile(to: ciImage, profile: leicaProfile) ?? uiImage
                        }
                    }

                    // Apply watermark if enabled
                    if watermark.isEnabled {
                        processedImage = WatermarkManager.applyWatermark(
                            to: processedImage,
                            style: watermark.style,
                            position: watermark.position,
                            opacity: watermark.opacity,
                            scale: watermark.scale
                        )
                    }

                    let finalImage = Image(uiImage: processedImage)

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

    /// Capture bracketed exposure sequence (-1EV, 0EV, +1EV) and return all images.
    private func captureBracketed(settings: WatermarkSettings) async throws -> Image {
        let evValues: [Float] = [-1.0, 0.0, 1.0]
        var bracketedImages: [UIImage] = []

        for ev in evValues {
            let image = try await captureSingleExposure(ev: ev, watermark: settings)
            bracketedImages.append(image)
        }

        // Store bracketed images for access by CameraModel
        self.bracketedPhotos = bracketedImages

        // Return middle (0EV) as primary result
        return Image(uiImage: bracketedImages[1])
    }

    /// Capture a single exposure at the given EV bias.
    private func captureSingleExposure(ev: Float, watermark: WatermarkSettings) async throws -> UIImage {
        return try await withCheckedThrowingContinuation { continuation in
            let settings = AVCapturePhotoSettings()
            settings.isHighResolutionCaptureEnabled = true
            settings.exposureTargetBias = ev
            settings.jpegQuality = 1.0

            photoOutput.capturePhoto(with: settings, delegate: PhotoCaptureDelegate { [weak self] result in
                switch result {
                case .success(let image):
                    let uiImage = UIImage(image: image)
                    var processedImage = uiImage

                    if let ciImage = CIImage(image: uiImage) {
                        let leicaProfile = watermark.leicaProfile ?? .off
                        if leicaProfile != .off {
                            processedImage = self?.applyLeicaColorProfile(to: ciImage, profile: leicaProfile) ?? uiImage
                        }
                    }

                    if watermark.isEnabled {
                        processedImage = WatermarkManager.applyWatermark(
                            to: processedImage,
                            style: watermark.style,
                            position: watermark.position,
                            opacity: watermark.opacity,
                            scale: watermark.scale
                        )
                    }

                    continuation(.success(processedImage))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            })
        }
    }

    /// Capture first exposure for double exposure mode.
    private func captureSingleDoubleExposure(watermark: WatermarkSettings) async throws -> Image {
        return try await captureSingleExposure(ev: 0.0, watermark: watermark)
    }

    /// Capture second exposure and blend with first for double exposure mode.
    private func captureSecondDoubleExposure(watermark: WatermarkSettings) async throws -> Image {
        let secondImage = try await captureSingleExposure(ev: 0.0, watermark: watermark)

        // Blend first and second exposure using CIBlendWithMask at 50% opacity
        guard let firstImage = doubleExposureFirst,
              let firstCIImage = CIImage(image: firstImage),
              let secondCIImage = CIImage(image: secondImage) else {
            return Image(uiImage: secondImage)
        }

        guard let blend = CIFilter(name: "CISourceOverCompositing") else {
            return Image(uiImage: secondImage)
        }
        blend.setValue(secondCIImage, forKey: kCIInputImageKey)
        blend.setValue(firstCIImage, forKey: kCIInputBackgroundImageKey)
        blend.setValue(0.5, forKey: kCIInputIntensityKey)

        guard let blendedCIImage = blend.outputImage,
              let blendedCGImage = ciContext.createCGImage(blendedCIImage, from: blendedCIImage.extent) else {
            return Image(uiImage: secondImage)
        }

        let blendedImage = Image(uiImage: UIImage(cgImage: blendedCGImage))

        // Reset double exposure state
        doubleExposureFirst = nil

        // Save blended photo to photo library
        let finalImage = Image(uiImage: UIImage(cgImage: blendedCGImage))
        saveToPhotoLibrary(image: finalImage) { saveResult in
            switch saveResult {
            case .success:
                break
            case .failure(let error):
                print("Failed to save double exposure to photo library: \(error)")
            }
        }

        return blendedImage
    }
    private func applyLeicaColorProfile(to ciImage: CIImage, profile: LeicaColorProfile) -> UIImage {
        var result = ciImage

        switch profile {
        case .leicaClassic:
            // Leica Classic: warm, slightly desaturated, rich blacks
            guard let matrix = CIFilter(name: "CIColorMatrix") else { return UIImage(ciImage: result) }
            matrix.setValue(result, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: 1.05, y: 0.0, z: 0.0, w: 0.0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0.0, y: 0.95, z: 0.0, w: 0.0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0.0, y: 0.0, z: 0.90, w: 0.0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0.0, y: 0.0, z: 0.0, w: 1.0), forKey: "inputAVector")
            matrix.setValue(CIVector(x: 0.01, y: 0.005, z: 0.0, w: 0.0), forKey: "inputBiasVector")
            guard let mResult = matrix.outputImage else { return UIImage(ciImage: result) }

            guard let controls = CIFilter(name: "CIColorControls") else { return UIImage(ciImage: mResult) }
            controls.setValue(mResult, forKey: kCIInputImageKey)
            controls.setValue(0.90, forKey: kCIInputSaturationKey)
            controls.setValue(1.10, forKey: kCIInputContrastKey)
            controls.setValue(0.02, forKey: kCIInputBrightnessKey)
            result = controls.outputImage ?? mResult

        case .leicaVivid:
            // Leica Vivid: saturated colors, punchy contrast, cooler highlights
            guard let matrix = CIFilter(name: "CIColorMatrix") else { return UIImage(ciImage: result) }
            matrix.setValue(result, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: 1.10, y: 0.0, z: 0.0, w: 0.0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0.0, y: 1.05, z: 0.0, w: 0.0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0.0, y: 0.0, z: 0.95, w: 0.0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0.0, y: 0.0, z: 0.0, w: 1.0), forKey: "inputAVector")
            matrix.setValue(CIVector(x: -0.01, y: -0.01, z: 0.01, w: 0.0), forKey: "inputBiasVector")
            guard let mResult = matrix.outputImage else { return UIImage(ciImage: result) }

            guard let controls = CIFilter(name: "CIColorControls") else { return UIImage(ciImage: mResult) }
            controls.setValue(mResult, forKey: kCIInputImageKey)
            controls.setValue(1.25, forKey: kCIInputSaturationKey)
            controls.setValue(1.15, forKey: kCIInputContrastKey)
            controls.setValue(0.0, forKey: kCIInputBrightnessKey)
            result = controls.outputImage ?? mResult

        case .leicaBw:
            // Leica B&W: monochrome with Leica tonal curve
            guard let bw = CIFilter(name: "CIColorControls") else { return UIImage(ciImage: result) }
            bw.setValue(result, forKey: kCIInputImageKey)
            bw.setValue(0.0, forKey: kCIInputSaturationKey)
            bw.setValue(1.20, forKey: kCIInputContrastKey)
            bw.setValue(0.05, forKey: kCIInputBrightnessKey)
            guard let mResult = bw.outputImage else { return UIImage(ciImage: result) }

            guard let matrix = CIFilter(name: "CIColorMatrix") else { return UIImage(ciImage: mResult) }
            matrix.setValue(mResult, forKey: kCIInputImageKey)
            matrix.setValue(CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0.0), forKey: "inputRVector")
            matrix.setValue(CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0.0), forKey: "inputGVector")
            matrix.setValue(CIVector(x: 0.33, y: 0.33, z: 0.33, w: 0.0), forKey: "inputBVector")
            matrix.setValue(CIVector(x: 0.0, y: 0.0, z: 0.0, w: 1.0), forKey: "inputAVector")
            matrix.setValue(CIVector(x: 0.02, y: 0.02, z: 0.02, w: 0.0), forKey: "inputBiasVector")
            result = matrix.outputImage ?? mResult

        case .off:
            break
        }

        return UIImage(ciImage: result)
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

        // Detect faces from pixel buffer
        computeFaces(from: pixelBuffer)

        // Apply LUT filter pipeline with Leica color + watermark and dispatch filtered frame to main thread
        let settings = FilterSettings(
            lut: currentLUT,
            intensity: currentLUTIntensity,
            type: currentFilterType,
            color: ColorAdjustment(),
            leicaProfile: currentLeicaProfile,
            beautyIntensity: currentBeautyIntensity
        )
        filterPipeline.beautyIntensity = currentBeautyIntensity
        let filtered = filterPipeline.apply(
            to: pixelBuffer,
            settings: settings,
            watermark: currentWatermark
        )

        DispatchQueue.main.async { [weak self] in
            self?.onFilteredFrame?(filtered)
        }
    }

    // MARK: - AVCaptureFileOutputRecordingDelegate

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        isRecording = false
        if let error = error {
            print("Video recording failed: \(error)")
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.onVideoRecorded?(outputFileURL)
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

    /// Detect faces in a pixel buffer using Vision framework face detection.
    private func computeFaces(from pixelBuffer: CVPixelBuffer) {
        visionQueue.async { [weak self] in
            let requestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try requestHandler.perform([self.faceRequest])
                guard let observations = self.faceRequest.results else { return }
                let faceBounds = observations.map { $0.boundingBox }
                DispatchQueue.main.async { [weak self] in
                    self?.faceBounds = faceBounds
                }
            } catch {
                print("Face detection failed: \(error)")
            }
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
