#if canImport(Metal) && canImport(MetalKit)
import Metal
import MetalKit
import Observation

// Must match VisualParams in VisualRendererKernels.metal (40 bytes)
struct VisualParamsCPU {
    var time: Float = 0
    var coherence: Float = 0.5
    var heartRate: Float = 72
    var frequency: Float = 110
    var amplitude: Float = 0.5
    var rotation: Float = 0
    var symmetry: Int32 = 6
    var bands: Int32 = 8
    var resolutionX: Float = 1080
    var resolutionY: Float = 1920
}

enum VisualKernel: Int, CaseIterable {
    case cymatics = 0, mandala, particles, waveform, spectral

    var functionName: String {
        switch self {
        case .cymatics:  return "cymaticsKernel"
        case .mandala:   return "mandalaKernel"
        case .particles: return "particlesKernel"
        case .waveform:  return "waveformKernel"
        case .spectral:  return "spectralKernel"
        }
    }
}

@MainActor @Observable
final class BioVisualRenderer: NSObject {

    private(set) var activeKernel: VisualKernel = .cymatics
    private(set) var isReady: Bool = false

    @ObservationIgnored private let device: MTLDevice
    @ObservationIgnored private let commandQueue: MTLCommandQueue
    @ObservationIgnored private var pipelines: [VisualKernel: MTLComputePipelineState] = [:]
    @ObservationIgnored private var audioBuffer: MTLBuffer?
    @ObservationIgnored private let audioBufferSize = 512
    @ObservationIgnored private var startTime: Date = Date()
    @ObservationIgnored private var params = VisualParamsCPU()

    // Bio source — weak ref to avoid retain cycles
    @ObservationIgnored weak var soundscape: SoundscapeEngine?

    init?(soundscape: SoundscapeEngine) {
        guard let dev = MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue() else { return nil }
        device = dev
        commandQueue = queue
        self.soundscape = soundscape
        super.init()
        buildPipelines()
        buildAudioBuffer()
    }

    func setKernel(_ kernel: VisualKernel) {
        activeKernel = kernel
    }

    // MARK: - Build

    private func buildPipelines() {
        guard let library = device.makeDefaultLibrary() else {
            log.audio("BioVisualRenderer: no default Metal library", level: .error)
            return
        }
        for kernel in VisualKernel.allCases {
            guard let fn = library.makeFunction(name: kernel.functionName) else {
                log.audio("BioVisualRenderer: missing kernel \(kernel.functionName)", level: .warning)
                continue
            }
            do {
                pipelines[kernel] = try device.makeComputePipelineState(function: fn)
            } catch {
                log.audio("BioVisualRenderer: pipeline build failed \(kernel.functionName): \(error)", level: .error)
            }
        }
        isReady = !pipelines.isEmpty
        log.audio("BioVisualRenderer: \(pipelines.count)/\(VisualKernel.allCases.count) kernels ready")
    }

    private func buildAudioBuffer() {
        audioBuffer = device.makeBuffer(
            length: audioBufferSize * MemoryLayout<Float>.stride,
            options: .storageModeShared
        )
    }

    // MARK: - Params update (called on draw)

    private func updateParams(size: CGSize) {
        let t = Float(Date().timeIntervalSince(startTime))
        let coherence = Float(soundscape?.state.coherence ?? 0.5)
        let hr = Float(soundscape?.state.heartRate ?? 72)
        let freq = soundscape?.voiceRoot.frequency ?? 110

        params.time = t
        params.coherence = coherence
        params.heartRate = hr
        params.frequency = freq
        params.amplitude = Float(soundscape?.mixRoot ?? 0.5)
        params.rotation = t * 0.03
        params.symmetry = Int32(max(3, Int(coherence * 10)))
        params.bands = 8
        params.resolutionX = Float(size.width)
        params.resolutionY = Float(size.height)
    }
}

// MARK: - MTKViewDelegate

extension BioVisualRenderer: MTKViewDelegate {

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    nonisolated func draw(in view: MTKView) {
        // Hop to MainActor for param access, dispatch command encoding
        MainActor.assumeIsolated {
            guard isReady,
                  let pipeline = pipelines[activeKernel],
                  let drawable = view.currentDrawable,
                  let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

            updateParams(size: view.drawableSize)

            encoder.setComputePipelineState(pipeline)
            encoder.setTexture(drawable.texture, index: 0)

            var p = params
            encoder.setBytes(&p, length: MemoryLayout<VisualParamsCPU>.stride, index: 0)

            // Zeroed audio data (real audio feed can be wired in later)
            if let ab = audioBuffer {
                encoder.setBuffer(ab, offset: 0, index: 1)
            }

            let w = pipeline.threadExecutionWidth
            let h = pipeline.maxTotalThreadsPerThreadgroup / w
            let threadsPerGroup = MTLSize(width: w, height: h, depth: 1)
            let gridSize = MTLSize(
                width: Int(view.drawableSize.width),
                height: Int(view.drawableSize.height),
                depth: 1
            )
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadsPerGroup)
            encoder.endEncoding()

            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
#endif
