import Foundation
import MetalKit
import SwiftUI

/// Metal-based Cymatics Renderer
/// Renders real-time audio-reactive cymatics patterns using GPU shaders
@MainActor
class CymaticsRenderer: NSObject, MTKViewDelegate {

    // MARK: - Metal Components

    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!
    private var pipelineState: MTLRenderPipelineState!
    private var vertexBuffer: MTLBuffer!


    // MARK: - Uniforms

    private struct CymaticsUniforms {
        var time: Float = 0.0
        var audioLevel: Float = 0.0
        var frequency: Float = 0.0
        var hrvCoherence: Float = 0.5
        var heartRate: Float = 60.0
        var resolution: SIMD2<Float> = SIMD2<Float>(1920, 1080)
        var waveSpeed: Float = 1.0
        var waveAmplitude: Float = 1.0
    }

    private var uniforms = CymaticsUniforms()
    private var startTime: Date = Date()


    // MARK: - Input Data

    var audioLevel: Float = 0.0 {
        didSet { uniforms.audioLevel = audioLevel }
    }

    var frequency: Float = 0.0 {
        didSet { uniforms.frequency = frequency }
    }

    var hrvCoherence: Double = 0.5 {
        didSet { uniforms.hrvCoherence = Float(hrvCoherence / 100.0) }  // Normalize 0-100 to 0-1
    }

    var heartRate: Double = 60.0 {
        didSet { uniforms.heartRate = Float(heartRate) }
    }


    // MARK: - Configuration

    var waveSpeed: Float = 1.0 {
        didSet { uniforms.waveSpeed = waveSpeed }
    }

    var waveAmplitude: Float = 1.0 {
        didSet { uniforms.waveAmplitude = waveAmplitude }
    }


    // MARK: - Initialization

    override init() {
        super.init()
        setupMetal()
    }

    private func setupMetal() {
        // Get default Metal device
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("❌ Metal is not supported on this device")
            return
        }

        self.device = device
        self.commandQueue = device.makeCommandQueue()

        // Create pipeline
        do {
            try createPipeline()
            createVertexBuffer()
            print("✅ Metal Cymatics Renderer initialized")
        } catch {
            print("❌ Failed to setup Metal pipeline: \(error)")
        }
    }


    // MARK: - Pipeline Setup

    private func createPipeline() throws {
        // Load Metal library
        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.libraryCreationFailed
        }

        // Load shader functions
        guard let vertexFunction = library.makeFunction(name: "cymatics_vertex"),
              let fragmentFunction = library.makeFunction(name: "cymatics_fragment") else {
            throw RendererError.shaderLoadFailed
        }

        // Create pipeline descriptor
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Create pipeline state
        pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    private func createVertexBuffer() {
        // Full-screen quad vertices
        let vertices: [Float] = [
            // Position (x, y)  TexCoord (u, v)
            -1.0, -1.0,         0.0, 1.0,  // Bottom-left
             1.0, -1.0,         1.0, 1.0,  // Bottom-right
            -1.0,  1.0,         0.0, 0.0,  // Top-left
             1.0,  1.0,         1.0, 0.0,  // Top-right
        ]

        let dataSize = vertices.count * MemoryLayout<Float>.stride
        vertexBuffer = device.makeBuffer(bytes: vertices, length: dataSize, options: [])
    }


    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Update resolution uniform
        uniforms.resolution = SIMD2<Float>(Float(size.width), Float(size.height))
    }

    func draw(in view: MTKView) {
        // Update time
        uniforms.time = Float(Date().timeIntervalSince(startTime))

        // Get drawable and render pass descriptor
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        // Create render command encoder
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }

        // Set pipeline and buffers
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        // Set uniforms
        var uniformsCopy = uniforms
        renderEncoder.setFragmentBytes(
            &uniformsCopy,
            length: MemoryLayout<CymaticsUniforms>.stride,
            index: 0
        )

        // Draw full-screen quad (triangle strip)
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

        // End encoding
        renderEncoder.endEncoding()

        // Present drawable
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }


    // MARK: - Errors

    enum RendererError: Error {
        case libraryCreationFailed
        case shaderLoadFailed
        case pipelineCreationFailed
    }
}


// MARK: - SwiftUI Integration

/// SwiftUI view wrapper for Metal Cymatics Renderer
struct CymaticsView: UIViewRepresentable {

    /// Audio level (0.0 - 1.0)
    var audioLevel: Float

    /// Dominant frequency (Hz)
    var frequency: Float

    /// HRV coherence (0-100)
    var hrvCoherence: Double

    /// Heart rate (BPM)
    var heartRate: Double


    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MTKView {
        let mtkView = MTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.delegate = context.coordinator.renderer
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false  // Continuous rendering
        mtkView.isPaused = false
        mtkView.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 1.0)

        return mtkView
    }

    func updateUIView(_ mtkView: MTKView, context: Context) {
        // Update renderer with current values
        context.coordinator.renderer.audioLevel = audioLevel
        context.coordinator.renderer.frequency = frequency
        context.coordinator.renderer.hrvCoherence = hrvCoherence
        context.coordinator.renderer.heartRate = heartRate
    }


    // MARK: - Coordinator

    class Coordinator {
        let renderer = CymaticsRenderer()
    }
}


// MARK: - Preview

#if DEBUG
struct CymaticsView_Previews: PreviewProvider {
    static var previews: some View {
        CymaticsView(
            audioLevel: 0.5,
            frequency: 440.0,
            hrvCoherence: 75.0,
            heartRate: 72.0
        )
        .frame(height: 400)
        .preferredColorScheme(.dark)
    }
}
#endif
