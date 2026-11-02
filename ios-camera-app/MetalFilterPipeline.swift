//
//  MetalFilterPipeline.swift
//  ios-camera-app
//
//  GPU-accelerated filter pipeline ported from decompiled Android camera apps.
//  Uses Metal Shading Language (MSL) — ported from recovered GLSL shaders in
//  com.oplus.camera.gl (GLImageView.java, i.java).
//
//  Pipeline: LUT (CIColorCube via Metal texture) → ColorControls → Temperature/Tint → Sharpen → Film Grain
//

import UIKit
import CoreImage
import CoreVideo
import Metal
import MetalKit

/// GPU-accelerated filter pipeline using Metal.
/// Falls back to Core Image if Metal is unavailable.
class MetalFilterPipeline {

    private let device: MTLDevice?
    private let commandQueue: MTLCommandQueue?
    private let ciContext: CIContext
    private let mtkView: MTKView?

    // Metal pipeline states
    private var colorCubePSO: MTLRenderPipelineState?
    private var colorControlsPSO: MTLRenderPipelineState?
    private var temperatureTintPSO: MTLRenderPipelineState?
    private var sharpenPSO: MTLRenderPipelineState?
    private var filmGrainPSO: MTLRenderPipelineState?

    // Texture cache
    private var lutTextureCache: [String: MTLTexture] = [:]

    init?(device: MTLDevice? = MTLCreateSystemDefaultDevice()) {
        self.device = device
        self.commandQueue = device?.makeCommandQueue()
        self.ciContext = CIContext(mtlDevice: device, options: [.workingColorSpace: NSNull()])
        self.mtkView = nil

        guard device != nil, commandQueue != nil else {
            // Metal unavailable — caller should fall back to Core Image
            return
        }

        do {
            try buildPipelineStates()
        } catch {
            print("MetalFilterPipeline: failed to build pipeline states: \(error)")
            return nil
        }
    }

    private func buildPipelineStates() throws {
        guard let device = device else { return }
        let library = device.makeDefaultLibrary()

        // Vertex shader — full-screen quad
        let vertexFn = library?.makeFunction(name: "vertex_pass_through")

        // Fragment shaders
        let colorCubeFn = library?.makeFunction(name: "fragment_color_cube")
        let colorControlsFn = library?.makeFunction(name: "fragment_color_controls")
        let temperatureTintFn = library?.makeFunction(name: "fragment_temperature_tint")
        let sharpenFn = library?.makeFunction(name: "fragment_sharpen")
        let filmGrainFn = library?.makeFunction(name: "fragment_film_grain")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFn
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        pipelineDescriptor.fragmentFunction = colorCubeFn
        colorCubePSO = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)

        pipelineDescriptor.fragmentFunction = colorControlsFn
        colorControlsPSO = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)

        pipelineDescriptor.fragmentFunction = temperatureTintFn
        temperatureTintPSO = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)

        pipelineDescriptor.fragmentFunction = sharpenFn
        sharpenPSO = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)

        pipelineDescriptor.fragmentFunction = filmGrainFn
        filmGrainPSO = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    /// Apply the full Metal filter pipeline to a CVPixelBuffer.
    /// Returns a UIImage with LUT + color adjustments applied on the GPU.
    func apply(
        to pixelBuffer: CVPixelBuffer,
        settings: FilterSettings
    ) -> UIImage? {
        guard let device = device,
              let commandQueue = commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return nil
        }

        var texture: MTLTexture?

        // 1. Upload CVPixelBuffer to Metal texture
        let cvTexture = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil)!,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            CVPixelBufferGetWidth(pixelBuffer),
            CVPixelBufferGetHeight(pixelBuffer),
            0
        )
        texture = CVMetalTextureGetTexture(cvTexture!)

        // 2. Apply LUT (ColorCube)
        if let lut = settings.lut {
            texture = applyColorCube(to: texture!, lut: lut, intensity: settings.intensity, commandBuffer: commandBuffer)
        }

        // 3. Color controls (brightness, contrast, saturation)
        texture = applyColorControls(to: texture!, adjustment: settings.color, commandBuffer: commandBuffer)

        // 4. Temperature + Tint
        texture = applyTemperatureTint(to: texture!, adjustment: settings.color, commandBuffer: commandBuffer)

        // 5. Sharpen
        texture = applySharpen(to: texture!, sharpness: settings.color.sharpness, commandBuffer: commandBuffer)

        // 6. Film grain
        texture = applyFilmGrain(to: texture!, intensity: settings.intensity * 0.15, commandBuffer: commandBuffer)

        // Commit and present
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // Convert Metal texture back to UIImage
        guard let finalTexture = texture else { return nil }
        return textureToUIImage(texture: finalTexture, device: device)
    }

    // MARK: - Individual Metal Passes

    private func applyColorCube(to texture: MTLTexture, lut: CGImage, intensity: Float, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let device = device,
              let pso = colorCubePSO,
              let commandEncoder = commandBuffer.makeRenderCommandEncoder() else {
            return texture
        }

        let lutTex = loadLUTTexture(lut: lut, device: device)

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = device.makeDefaultLibrary()?.makeFunction(name: "vertex_pass_through")
        descriptor.fragmentFunction = device.makeDefaultLibrary()?.makeFunction(name: "fragment_color_cube")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pso2 = try? device.makeRenderPipelineState(descriptor: descriptor) else {
            commandEncoder.endEncoding()
            return texture
        }

        let outputTex = createTexture(matching: texture, device: device)

        commandEncoder.setRenderPipelineState(pso2)
        commandEncoder.setFragmentTexture(texture, index: 0)
        commandEncoder.setFragmentTexture(lutTex, index: 1)
        commandEncoder.setFragmentBytes([intensity], length: MemoryLayout<Float>.stride, index: 0)
        commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        commandEncoder.endEncoding()

        return outputTex
    }

    private func applyColorControls(to texture: MTLTexture, adjustment: ColorAdjustment, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let device = device,
              let pso = colorControlsPSO,
              let commandEncoder = commandBuffer.makeRenderCommandEncoder() else {
            return texture
        }

        let outputTex = createTexture(matching: texture, device: device)

        commandEncoder.setRenderPipelineState(pso)
        commandEncoder.setFragmentTexture(texture, index: 0)
        commandEncoder.setFragmentBytes([
            adjustment.brightness,
            adjustment.contrast,
            adjustment.saturation
        ], length: MemoryLayout<Float>.stride * 3, index: 0)
        commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        commandEncoder.endEncoding()

        return outputTex
    }

    private func applyTemperatureTint(to texture: MTLTexture, adjustment: ColorAdjustment, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard let device = device,
              let pso = temperatureTintPSO,
              let commandEncoder = commandBuffer.makeRenderCommandEncoder() else {
            return texture
        }

        let outputTex = createTexture(matching: texture, device: device)

        commandEncoder.setRenderPipelineState(pso)
        commandEncoder.setFragmentTexture(texture, index: 0)
        commandEncoder.setFragmentBytes([
            (adjustment.temperature - 6500.0) / 6500.0,
            adjustment.tint
        ], length: MemoryLayout<Float>.stride * 2, index: 0)
        commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        commandEncoder.endEncoding()

        return outputTex
    }

    private func applySharpen(to texture: MTLTexture, sharpness: Float, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard sharpness > 0,
              let device = device,
              let pso = sharpenPSO,
              let commandEncoder = commandBuffer.makeRenderCommandEncoder() else {
            return texture
        }

        let outputTex = createTexture(matching: texture, device: device)

        commandEncoder.setRenderPipelineState(pso)
        commandEncoder.setFragmentTexture(texture, index: 0)
        commandEncoder.setFragmentBytes([sharpness], length: MemoryLayout<Float>.stride, index: 0)
        commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        commandEncoder.endEncoding()

        return outputTex
    }

    private func applyFilmGrain(to texture: MTLTexture, intensity: Float, commandBuffer: MTLCommandBuffer) -> MTLTexture? {
        guard intensity > 0,
              let device = device,
              let pso = filmGrainPSO,
              let commandEncoder = commandBuffer.makeRenderCommandEncoder() else {
            return texture
        }

        let outputTex = createTexture(matching: texture, device: device)

        commandEncoder.setRenderPipelineState(pso)
        commandEncoder.setFragmentTexture(texture, index: 0)
        commandEncoder.setFragmentBytes([intensity], length: MemoryLayout<Float>.stride, index: 0)
        commandEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        commandEncoder.endEncoding()

        return outputTex
    }

    // MARK: - Helpers

    private func createTexture(matching source: MTLTexture, device: MTLDevice) -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: source.pixelFormat,
            width: source.width,
            height: source.height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]
        return device.makeTexture(descriptor: descriptor)!
    }

    private func loadLUTTexture(lut: CGImage, device: MTLDevice) -> MTLTexture {
        let key = "lut_\(lut.width)x\(lut.height)"
        if let cached = lutTextureCache[key] {
            return cached
        }

        let loader = MTKTextureLoader(device: device)
        let uiImage = UIImage(cgImage: lut)
        guard let texture = try? loader.newTexture(image: uiImage, options: [.SRGB: false]) else {
            // Fallback: create a 1x1 neutral texture
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
            let tex = device.makeTexture(descriptor: descriptor)!
            lutTextureCache[key] = tex
            return tex
        }

        lutTextureCache[key] = texture
        return texture
    }

    private func textureToUIImage(texture: MTLTexture, device: MTLDevice) -> UIImage? {
        let width = texture.width
        let height = texture.height
        let rowBytes = width * 4
        let bytesPerRow = rowBytes
        let totalBytes = height * bytesPerRow

        var pixelData = [UInt8](repeating: 0, count: totalBytes)
        let region = MTLRegionMake2D(0, 0, width, height)
        texture.getBytes(&pixelData, bytesPerRow: bytesPerRow, from: region, mipmapLevel: 0)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let context = CGContext(data: &pixelData, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                      space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }

        guard let cgImage = context.makeImage() else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Whether Metal GPU acceleration is available.
    static var isMetalAvailable: Bool {
        return MTLCreateSystemDefaultDevice() != nil
    }
}
