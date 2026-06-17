//
//  MetalBioView.swift
//  Echoelmusic — the GPU "Visual" dimension.
//
//  A real Metal renderer for the immersive bio-reactive visual: an MTKView driven
//  by its own CADisplayLink, with a dedicated MTLCommandQueue, rendering a
//  full-screen fragment shader whose look is shaped by the live body (heart rate →
//  pulse, coherence → hue, breath → spread). It reads the EngineBus snapshot only
//  (multi-reader-safe), never the audio thread.
//
//  Why Metal over the SwiftUI Canvas version (BioVisualView): the Canvas redraws on
//  the CPU on the main thread every frame, competing with the load-bearing beat
//  clock. Metal encodes a tiny command buffer on main and the GPU does the work —
//  far lighter on the main actor, and the correct foundation that projection-
//  mapping / video-overlay / holographic surfaces can later reuse.
//
//  Robustness: the shader is compiled at runtime; if compilation ever fails the
//  view degrades to a calm clear-colour pulse instead of crashing. Flash-safe: the
//  pulse frequency is clamped to ≤2 Hz (heart rate / 60, bounded) — under the 3 Hz
//  WCAG epilepsy limit — and honours Reduce Motion via a still frame.
//

#if canImport(MetalKit) && canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import MetalKit
import simd

/// Bio uniforms handed to the fragment shader. Layout must match `Uniforms` in the
/// MSL source below (6 contiguous floats).
private struct BioUniforms {
    var time: Float = 0
    var hr: Float = 60
    var coherence: Float = 0.5
    var breath: Float = 0.5
    var aspect: Float = 1
    /// The currently sounding musical fundamental (Hz). The shader transposes it up
    /// by whole octaves into visible light and renders its physically TRUE colour.
    var toneHz: Float = 261.63
}

/// SwiftUI host for the Metal bio visual. iPhone-only surface.
@MainActor
struct MetalBioView: UIViewRepresentable {

    @Environment(EngineBus.self) private var bus
    var reduceMotion: Bool = false
    /// The instrument's current fundamental (Hz) — its colour is the physical
    /// octave-transposition of this pitch into visible light.
    var toneHz: Double = 261.63

    func makeCoordinator() -> MetalBioRenderer { MetalBioRenderer() }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        if let device = MTLCreateSystemDefaultDevice() {
            view.device = device
            context.coordinator.configure(device: device)
        }
        view.delegate = context.coordinator
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.isOpaque = true
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        // Push the freshest bio snapshot into the renderer on the main actor; the
        // draw loop reads these atomically. Stale frames expire via freshBio().
        let bio = bus.freshBio()
        context.coordinator.update(
            hr: bio?.heartRateBPM ?? 60,
            coherence: bio?.coherence ?? 0.5,
            breath: bio?.breathPhase ?? 0.5,
            toneHz: toneHz,
            reduceMotion: reduceMotion
        )
    }
}

/// Owns the Metal device/queue/pipeline and renders each frame. The draw callback
/// runs on the main thread (MTKView's CADisplayLink); uniform fields are plain
/// Floats updated from the main actor, so no cross-thread state races.
final class MetalBioRenderer: NSObject, MTKViewDelegate {

    private var commandQueue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    private var uniforms = BioUniforms()
    private var reduceMotion = false
    private let startTime = CFAbsoluteTimeGetCurrent()

    func configure(device: MTLDevice) {
        commandQueue = device.makeCommandQueue()
        // Compile the shader at runtime; on failure leave `pipeline` nil → the draw
        // loop falls back to a calm clear-colour pulse (never a crash).
        guard let library = try? device.makeLibrary(source: Self.shaderSource, options: nil),
              let vfn = library.makeFunction(name: "echoel_bio_vertex"),
              let ffn = library.makeFunction(name: "echoel_bio_fragment") else { return }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try? device.makeRenderPipelineState(descriptor: desc)
    }

    func update(hr: Float, coherence: Float, breath: Float, toneHz: Double, reduceMotion: Bool) {
        uniforms.hr = min(max(hr.isFinite ? hr : 60, 40), 200)
        uniforms.coherence = min(max(coherence.isFinite ? coherence : 0.5, 0), 1)
        uniforms.breath = min(max(breath.isFinite ? breath : 0.5, 0), 1)
        let t = Float(toneHz)
        uniforms.toneHz = min(max(t.isFinite ? t : 261.63, 20), 20000)
        self.reduceMotion = reduceMotion
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        uniforms.aspect = size.height > 0 ? Float(size.width / size.height) : 1
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let queue = commandQueue,
              let buffer = queue.makeCommandBuffer() else { return }

        // Reduce Motion → freeze the animation clock at 0 (a still frame).
        uniforms.time = reduceMotion ? 0 : Float(CFAbsoluteTimeGetCurrent() - startTime)

        if let pipeline,
           let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) {
            encoder.setRenderPipelineState(pipeline)
            var u = uniforms
            encoder.setVertexBytes(&u, length: MemoryLayout<BioUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&u, length: MemoryLayout<BioUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        } else {
            // Fallback: gentle clear-colour pulse from the heart rate (shader absent).
            let pulseHz = min(max(Double(uniforms.hr) / 60.0, 0.5), 2.0)
            let t = reduceMotion ? 0 : (CFAbsoluteTimeGetCurrent() - startTime)
            let beat = 0.15 + 0.12 * (0.5 + 0.5 * sin(2 * .pi * t * pulseHz))
            pass.colorAttachments[0].clearColor =
                MTLClearColor(red: beat * 0.4, green: beat * 0.2, blue: beat, alpha: 1)
            buffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
        }

        buffer.present(drawable)
        buffer.commit()
    }

    // MARK: - Shader (Metal Shading Language, compiled at runtime)

    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VOut { float4 pos [[position]]; float2 uv; };
    struct Uniforms { float time; float hr; float coherence; float breath; float aspect; float toneHz; };

    // Map a light wavelength (nm) to linear-ish RGB (Bruton's classic approximation),
    // with an intensity roll-off near the limits of human vision.
    float3 wavelengthToRGB(float wl) {
        float3 c = float3(0.0);
        if      (wl < 440.0) { c = float3(-(wl - 440.0) / 60.0, 0.0, 1.0); }
        else if (wl < 490.0) { c = float3(0.0, (wl - 440.0) / 50.0, 1.0); }
        else if (wl < 510.0) { c = float3(0.0, 1.0, -(wl - 510.0) / 20.0); }
        else if (wl < 580.0) { c = float3((wl - 510.0) / 70.0, 1.0, 0.0); }
        else if (wl < 645.0) { c = float3(1.0, -(wl - 645.0) / 65.0, 0.0); }
        else                 { c = float3(1.0, 0.0, 0.0); }
        float f = 1.0;
        if      (wl < 420.0) f = 0.3 + 0.7 * (wl - 380.0) / 40.0;
        else if (wl > 700.0) f = 0.3 + 0.7 * (780.0 - wl) / 80.0;
        return clamp(c, 0.0, 1.0) * clamp(f, 0.0, 1.0);
    }

    // Physically transpose an audible tone up by WHOLE octaves into visible light,
    // then return its true colour. c = 2.998e17 nm/s, so wavelength = c / f_light.
    float3 toneColour(float toneHz) {
        float f = max(toneHz, 1.0);
        float n = round(log2(5.4e14 / f));         // octaves up to ~555 nm (green centre)
        float fLight = f * exp2(n);                 // now in the ~400–790 THz visible band
        float wl = 2.998e17 / fLight;              // nanometres
        return wavelengthToRGB(clamp(wl, 380.0, 780.0));
    }

    // Full-screen triangle generated from the vertex id — no vertex buffer needed.
    vertex VOut echoel_bio_vertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);   // (0,0) (2,0) (0,2)
        VOut o;
        o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0);
        o.uv = p;
        return o;
    }

    fragment float4 echoel_bio_fragment(VOut in [[stage_in]],
                                        constant Uniforms& u [[buffer(0)]]) {
        float2 uv = in.uv;
        uv.x *= u.aspect;
        float2 c = float2(0.5 * u.aspect, 0.5);
        float d = distance(uv, c);

        // Heart rate → ring pulse, clamped to <= 2 Hz (WCAG flash safety).
        float pulseHz = clamp(u.hr / 60.0, 0.5, 2.0);
        float rings = 0.5 + 0.5 * sin(d * 40.0 - u.time * pulseHz * 6.2831853);
        // Breath → how far the field spreads from the centre.
        float spread = 0.85 + u.breath * 0.35;
        float field = rings * smoothstep(0.62 * spread, 0.0, d);

        // Colour = the heard tone transposed into light (physically correct), so the
        // pitch you hear is the colour you see. Coherence lifts the saturation/glow.
        float3 col = toneColour(u.toneHz);
        col = mix(col, col * 1.15 + 0.05, u.coherence);
        return float4(col * field, 1.0);
    }
    """
}
#endif
