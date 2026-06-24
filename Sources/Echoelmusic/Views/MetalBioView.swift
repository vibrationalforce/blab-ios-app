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
    var intensity: Float = 1.0
    var ringDensity: Float = 40
    var motion: Float = 1.0
    var spread: Float = 1.0
    /// Heartbeat pulse frequency (Hz), already flash-clamped by `BioVisualParams`/
    /// `FlashGuard` on the Swift side — the single source of WCAG flash-safety truth.
    var pulseHz: Float = 1.0
    /// VJ hue rotation in turns [0…1]. 0 = the physically-correct tone→light colour
    /// (the science-first default); >0 rotates the palette for performance.
    var hueShift: Float = 0
    /// VJ saturation [0…2]. 1 = neutral (unchanged), 0 = greyscale, >1 = punchier.
    var saturation: Float = 1
    /// ACCUMULATED pulse phase (turns). The ring animation reads this, NOT
    /// `time × pulseHz`: with the old form, any change in the HR-derived frequency
    /// multiplied the (large, ever-growing) time → the whole pattern snapped by many
    /// cycles at once (the "ruckeln hin und her"). Integrating phase per frame means
    /// a frequency change alters only the RATE, never the position. Continuous.
    var pulsePhase: Float = 0
    /// Visual STYLE selector (discrete, snapped — not eased): 0 = interference rings,
    /// 1 = Chladni nodal eigenmodes (tone → plate modes), 2 = plasma wave field,
    /// 3 = water caustics (rippling light net).
    var style: Float = 0
    /// SECONDARY style to blend with `style` (same index space). Discrete/snapped.
    var styleB: Float = 0
    /// Blend (Mix) ratio between `style` (0) and `styleB` (1) — the overlapping/
    /// "mischend" control. EASED so changing the mix or B morphs smoothly. 0 = pure A.
    var blend: Float = 0
}

/// SwiftUI host for the Metal bio visual. iPhone-only surface.
@MainActor
struct MetalBioView: UIViewRepresentable {

    @Environment(EngineBus.self) private var bus
    @Environment(ResourceGovernor.self) private var governor
    var reduceMotion: Bool = false
    /// The instrument's current fundamental (Hz) — its colour is the physical
    /// octave-transposition of this pitch into visible light.
    var toneHz: Double = 261.63
    // User look controls (all clamped in the renderer; motion is flash-capped).
    var intensity: Float = 1.0
    var ringDensity: Float = 40
    var motion: Float = 1.0
    var spread: Float = 1.0
    /// VJ palette controls (see BioUniforms). Defaults keep the physical colour.
    var hueShift: Float = 0
    var saturation: Float = 1
    /// Visual style: 0 rings · 1 Chladni · 2 plasma · 3 water (see `BioUniforms.style`).
    var style: Int = 0
    /// Secondary style to blend with `style` (same index space). 0 rings · 1 Chladni · 2 plasma · 3 water.
    var styleB: Int = 0
    /// Mix ratio A↔B [0…1] — 0 = pure `style`, 1 = pure `styleB`. The "mischend" control.
    var blend: Float = 0

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
        // Resource conservation: the governor decides the frame rate, the visual
        // detail and whether to freeze motion, from live thermal/battery/FPS. Apply
        // before pushing bio so this frame already honours the current tier.
        let q = governor.settings
        view.preferredFramesPerSecond = q.targetFPS
        context.coordinator.governor = governor
        let effectiveReduceMotion = reduceMotion || q.reduceMotion
        let scaledRingDensity = ringDensity * q.visualDetailScale
        // Push the freshest bio snapshot into the renderer on the main actor; the
        // draw loop reads these atomically. Stale frames expire via freshBio().
        let bio = bus.freshBio()
        // Derive the flash-safe heartbeat pulse from the shared, unit-tested
        // BioVisualParams so WCAG flash-safety lives in ONE place (FlashGuard),
        // not duplicated in the shader. The look is unchanged (same hr/60 mapping).
        let vp = BioVisualParams.from(bio, reduceMotion: effectiveReduceMotion)
        // Colour follows the MUSIC when it's sounding: use the loudest live note from
        // the published MusicalFrame so the immersive visual tracks the melody, not a
        // static tonic. Falls back to the instrument's tonic (`toneHz`) when silent.
        let liveTone = bus.freshMusical(maxAge: 1.5)
            .flatMap { $0.notes.max(by: { $0.amplitude < $1.amplitude })?.frequencyHz }
            ?? toneHz
        context.coordinator.update(
            hr: bio?.heartRateBPM ?? 60,
            coherence: bio?.coherence ?? 0.5,
            breath: bio?.breathPhase ?? 0.5,
            toneHz: liveTone,
            intensity: intensity, ringDensity: scaledRingDensity, motion: motion, spread: spread,
            pulseHz: Float(vp.pulseHz),
            hueShift: hueShift, saturation: saturation,
            style: style, styleB: styleB, blend: blend,
            reduceMotion: effectiveReduceMotion
        )
    }
}

/// Owns the Metal device/queue/pipeline and renders each frame. The draw callback
/// runs on the main thread (MTKView's CADisplayLink); uniform fields are plain
/// Floats updated from the main actor, so no cross-thread state races.
final class MetalBioRenderer: NSObject, MTKViewDelegate {

    private var commandQueue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?
    /// `uniforms` are what the GPU sees THIS frame; `target` is what the latest bio /
    /// look update asked for. Every draw eases `uniforms` toward `target` (time-based
    /// exponential smoothing) so discrete updates — a stepped HR, a new note's colour,
    /// a governor detail change — GLIDE instead of snapping. This is the felt
    /// "smoothness/Wirkung": the body modulates the look continuously, never in jerks.
    private var uniforms = BioUniforms()
    private var target = BioUniforms()
    private var hasTarget = false
    private var reduceMotion = false
    private let startTime = CFAbsoluteTimeGetCurrent()
    private var lastFrameTime = CFAbsoluteTimeGetCurrent()
    /// The resource governor receives each frame's timestamp so a sustained FPS drop
    /// can demote the visual tier. The MTKView draw callback runs on the main thread
    /// (default CADisplayLink), so the @MainActor hop below is a safe no-op assertion.
    weak var governor: ResourceGovernor?

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

    func update(hr: Float, coherence: Float, breath: Float, toneHz: Double,
                intensity: Float, ringDensity: Float, motion: Float, spread: Float,
                pulseHz: Float, hueShift: Float, saturation: Float,
                style: Int, styleB: Int, blend: Float, reduceMotion: Bool) {
        // Writes the TARGET; draw() eases the live uniforms toward it. Same clamps as
        // before (the GPU never sees an out-of-range / non-finite value).
        // Styles are DISCRETE — snap them on both live and target (no cross-fade between
        // modes). The BLEND between them is what eases (a smooth A↔B morph).
        let s = Float(min(max(style, 0), 3))
        target.style = s
        uniforms.style = s
        let sb = Float(min(max(styleB, 0), 3))
        target.styleB = sb
        uniforms.styleB = sb
        target.blend = min(max(blend.isFinite ? blend : 0, 0), 1)
        target.hr = min(max(hr.isFinite ? hr : 60, 40), 200)
        target.coherence = min(max(coherence.isFinite ? coherence : 0.5, 0), 1)
        target.breath = min(max(breath.isFinite ? breath : 0.5, 0), 1)
        let t = Float(toneHz)
        target.toneHz = min(max(t.isFinite ? t : 261.63, 20), 20000)
        target.intensity = min(max(intensity.isFinite ? intensity : 1, 0), 1.5)
        target.ringDensity = min(max(ringDensity.isFinite ? ringDensity : 40, 4), 120)
        target.motion = min(max(motion.isFinite ? motion : 1, 0), 1.5)
        target.spread = min(max(spread.isFinite ? spread : 1, 0.4), 1.6)
        // Already flash-clamped upstream (BioVisualParams/FlashGuard); guard finite
        // and hard-cap at the WCAG ceiling as defense in depth.
        target.pulseHz = min(max(pulseHz.isFinite ? pulseHz : 1, 0), 3)
        // VJ palette: hue wraps to [0,1); saturation clamped [0,2]. Defaults (0,1)
        // leave the physically-correct tone colour untouched.
        var hs = hueShift.isFinite ? hueShift : 0
        hs = hs - floor(hs)
        target.hueShift = hs
        target.saturation = min(max(saturation.isFinite ? saturation : 1, 0), 2)
        self.reduceMotion = reduceMotion
        // First update: snap (no glide from defaults), so the opening frame is correct.
        if !hasTarget {
            let phase = uniforms.pulsePhase
            uniforms = target
            uniforms.pulsePhase = phase
            hasTarget = true
        }
    }

    /// Exponential glide of `a` toward `b` over time-constant `tau` (seconds) for the
    /// elapsed `dt`. Frame-rate independent: the same easing whether the governor runs
    /// the view at 30 or 120 fps, so a tier change never shows as a speed change.
    private static func ease(_ a: Float, _ b: Float, tau: Float, dt: Float) -> Float {
        guard tau > 0, dt > 0 else { return b }
        let k = 1 - exp(-dt / tau)
        return a + (b - a) * k
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        uniforms.aspect = size.height > 0 ? Float(size.width / size.height) : 1
    }

    func draw(in view: MTKView) {
        // Feed the render cadence back to the governor (main thread → safe isolation
        // assertion). Lets it back off detail/FPS if the GPU can't keep up.
        if let governor {
            let now = CFAbsoluteTimeGetCurrent()
            MainActor.assumeIsolated { governor.recordFrame(timestamp: now) }
        }
        guard let drawable = view.currentDrawable,
              let pass = view.currentRenderPassDescriptor,
              let queue = commandQueue,
              let buffer = queue.makeCommandBuffer() else { return }

        // Real elapsed time since the last drawn frame — drives both the smoothing and
        // the phase integration, so everything is frame-rate independent.
        let nowT = CFAbsoluteTimeGetCurrent()
        let dt = Float(min(max(nowT - lastFrameTime, 0), 0.1))   // clamp after a stall
        lastFrameTime = nowT

        // Glide the live uniforms toward the latest target. Per-parameter time
        // constants: breath/coherence track quickly (they ARE slow signals), HR and
        // colour glide more so residual rPPG jitter and note changes feel musical,
        // VJ palette is snappy (it's a live performance control).
        if hasTarget {
            uniforms.hr        = Self.ease(uniforms.hr,        target.hr,        tau: 1.2,  dt: dt)
            uniforms.coherence = Self.ease(uniforms.coherence, target.coherence, tau: 0.6,  dt: dt)
            uniforms.breath    = Self.ease(uniforms.breath,    target.breath,    tau: 0.35, dt: dt)
            uniforms.toneHz    = Self.ease(uniforms.toneHz,    target.toneHz,    tau: 0.45, dt: dt)
            uniforms.intensity = Self.ease(uniforms.intensity, target.intensity, tau: 0.4,  dt: dt)
            uniforms.ringDensity = Self.ease(uniforms.ringDensity, target.ringDensity, tau: 0.7, dt: dt)
            uniforms.motion    = Self.ease(uniforms.motion,    target.motion,    tau: 0.4,  dt: dt)
            uniforms.spread    = Self.ease(uniforms.spread,    target.spread,    tau: 0.5,  dt: dt)
            uniforms.pulseHz   = Self.ease(uniforms.pulseHz,   target.pulseHz,   tau: 1.2,  dt: dt)
            // Hue wraps, so glide along the SHORTEST arc on the colour wheel.
            var dHue = target.hueShift - uniforms.hueShift
            dHue -= round(dHue)
            uniforms.hueShift = (uniforms.hueShift + dHue * (dt > 0 ? (1 - exp(-dt / 0.15)) : 1))
            uniforms.hueShift -= floor(uniforms.hueShift)
            uniforms.saturation = Self.ease(uniforms.saturation, target.saturation, tau: 0.2, dt: dt)
            // The A↔B mix morphs smoothly (snappy — it's a live performance control).
            uniforms.blend = Self.ease(uniforms.blend, target.blend, tau: 0.3, dt: dt)
        }

        // Integrate the flash-safe pulse phase from the SMOOTHED frequency. flashHz =
        // pulseHz × motion, hard-capped at 2.5 Hz (< WCAG 3 Hz) as on the shader side.
        // Reduce Motion → freeze (no advance).
        if !reduceMotion {
            let flashHz = min(uniforms.pulseHz * uniforms.motion, 2.5)
            uniforms.pulsePhase += dt * flashHz
            if uniforms.pulsePhase > 1e6 { uniforms.pulsePhase -= 1e6 }   // keep it bounded
        }
        // Keep `time` as a free-running clock for the secondary motion in the shader.
        uniforms.time = reduceMotion ? 0 : Float(nowT - startTime)

        if let pipeline,
           let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) {
            encoder.setRenderPipelineState(pipeline)
            var u = uniforms
            encoder.setVertexBytes(&u, length: MemoryLayout<BioUniforms>.stride, index: 0)
            encoder.setFragmentBytes(&u, length: MemoryLayout<BioUniforms>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        } else {
            // Fallback: gentle clear-colour pulse (shader absent). Same flash-safe
            // pulse the main path uses, sourced from BioVisualParams/FlashGuard.
            let pulseHz = Double(uniforms.pulseHz)
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
    struct Uniforms { float time; float hr; float coherence; float breath; float aspect;
                      float toneHz; float intensity; float ringDensity; float motion; float spread;
                      float pulseHz; float hueShift; float saturation; float pulsePhase; float style;
                      float styleB; float blend; };

    // VJ palette: luma-preserving saturation, then a hue rotation in the YIQ space
    // (explicit dot products to avoid any column/row matrix ambiguity). Both are
    // no-ops at the defaults (saturation 1, hueShift 0) so the physical colour holds.
    float3 echoelSaturate(float3 c, float s) {
        float l = dot(c, float3(0.2126, 0.7152, 0.0722));
        return mix(float3(l), c, s);
    }
    float3 echoelHue(float3 c, float shiftTurns) {
        float a = shiftTurns * 6.2831853;
        float ca = cos(a), sa = sin(a);
        float y = dot(c, float3(0.299,  0.587,  0.114));
        float i = dot(c, float3(0.596, -0.274, -0.322));
        float q = dot(c, float3(0.211, -0.523,  0.312));
        float i2 = i * ca - q * sa;
        float q2 = i * sa + q * ca;
        float3 rgb = float3(y + 0.956 * i2 + 0.621 * q2,
                            y - 0.272 * i2 - 0.647 * q2,
                            y - 1.106 * i2 + 1.703 * q2);
        return clamp(rgb, 0.0, 1.0);
    }

    // Wavelength (nm) → linear sRGB, COLORIMETRICALLY via the CIE 1931 colour-matching
    // functions (Wyman/Sloan/Shirley 2013 analytic fit) → XYZ → linear sRGB (D65). This
    // is the exact same fit as the Swift SpectralColor.wavelengthToLinearRGB, so the
    // immersive visual and the spectral donut agree. The CMFs' own falloff dims the
    // deep-red/violet ends (physically correct eye sensitivity).
    float cieLobe(float x, float mu, float s1, float s2) {
        float t = (x - mu) * (x < mu ? 1.0 / s1 : 1.0 / s2);
        return exp(-0.5 * t * t);
    }
    float3 wavelengthToRGB(float wl) {
        float X = 1.056 * cieLobe(wl, 599.8, 37.9, 31.0)
                + 0.362 * cieLobe(wl, 442.0, 16.0, 26.7)
                - 0.065 * cieLobe(wl, 501.1, 20.4, 26.2);
        float Y = 0.821 * cieLobe(wl, 568.8, 46.9, 40.5)
                + 0.286 * cieLobe(wl, 530.9, 16.3, 31.1);
        float Z = 1.217 * cieLobe(wl, 437.0, 11.8, 36.0)
                + 0.681 * cieLobe(wl, 459.0, 26.0, 13.8);
        X = max(0.0, X); Y = max(0.0, Y); Z = max(0.0, Z);
        float3 c = float3( 3.2406 * X - 1.5372 * Y - 0.4986 * Z,
                          -0.9689 * X + 1.8758 * Y + 0.0415 * Z,
                           0.0557 * X - 0.2040 * Y + 1.0570 * Z);
        c = max(c, 0.0);
        float m = max(c.r, max(c.g, c.b));
        if (m > 1.0) c /= m;
        return clamp(c, 0.0, 1.0);
    }

    // Physically transpose an audible tone up by WHOLE octaves into visible light and
    // return the resulting WAVELENGTH (nm, unclamped — the caller clamps). c = 2.998e17
    // nm/s, so wavelength = c / f_light.
    float toneWavelengthNm(float toneHz) {
        float f = max(toneHz, 1.0);
        float n = round(log2(5.4e14 / f));         // octaves up to ~555 nm (green centre)
        float fLight = f * exp2(n);                 // now in the ~400–790 THz visible band
        return 2.998e17 / fLight;                   // nanometres
    }
    float3 toneColour(float toneHz) {
        return wavelengthToRGB(clamp(toneWavelengthNm(toneHz), 380.0, 780.0));
    }

    // ── Visual styles — each returns a scalar field in ~[0,1] ───────────────────
    // STYLE 0 — wave INTERFERENCE rings: a second ring system detuned by coherence
    // (high = aligned/constructive, low = turbulent moiré) beats against the first.
    float fieldRings(float d, float density, float phase, float coh) {
        float rings  = 0.5 + 0.5 * sin(d * density - phase);
        float detune = mix(1.6, 1.04, coh);
        float rings2 = 0.5 + 0.5 * sin(d * density * detune - phase * 0.5);
        return mix(rings, rings * rings2, 0.5);
    }
    // STYLE 1 — CHLADNI nodal figures: eigenmodes of a vibrating square plate,
    // s = cos(mπx)cos(nπy) − cos(nπx)cos(mπy); sand gathers on the nodal lines (s≈0).
    // The mode numbers m,n come from the sounding TONE, so a higher pitch shows a
    // finer figure — a real physical pitch→pattern mapping. Coherence sharpens the
    // lines; the (slow, flash-safe) pulse phase makes them breathe.
    float fieldChladni(float2 p, float toneHz, float phase, float coh) {
        float b = log2(max(toneHz, 1.0));
        float m = 2.0 + floor(fract(b * 0.50) * 5.0);          // 2..6
        float n = 2.0 + floor(fract(b * 0.37 + 0.3) * 5.0);    // 2..6
        float a1 = 3.14159265 * m;
        float a2 = 3.14159265 * n;
        float s = cos(a1 * p.x) * cos(a2 * p.y) - cos(a2 * p.x) * cos(a1 * p.y);
        float amp = 0.7 + 0.3 * sin(phase * 0.5);              // gentle breathing
        float w = mix(0.14, 0.04, coh);                        // coherence sharpens lines
        return 1.0 - smoothstep(0.0, w, abs(s) * amp);
    }
    // STYLE 2 — PLASMA: superposed travelling plane waves (a classic interference
    // field). Drifts slowly via the flash-safe phase; coherence raises the contrast
    // (ordered banding) vs a soft wash. Organic motion with no fast flashing.
    float fieldPlasma(float2 p, float phase, float coh) {
        float t = phase * 0.5;                                 // slow drift (≤ flashHz)
        float v = sin(p.x * 3.0 + t)
                + sin(p.y * 3.0 - t * 0.8)
                + sin((p.x + p.y) * 2.5 + t * 0.6)
                + sin(length(p) * 5.0 - t);
        v = 0.5 + 0.125 * v;                                   // → ~[0,1]
        return pow(clamp(v, 0.0, 1.0), mix(1.0, 2.2, coh));
    }
    // STYLE 3 — WATER caustics: crossing wave trains form a rippling light net, like
    // sun on a pool floor — the "Wasser·Klang·Licht" aesthetic for music-video / film /
    // stage. A high power on the wave crests yields the bright caustic filaments;
    // coherence sharpens them, breath widens the ripple scale, the slow flash-safe
    // phase drifts the surface. Pure sin/cos (no loop), so it stays compile-safe.
    float fieldWater(float2 p, float phase, float coh, float breath) {
        float t = phase * 0.4;
        float scale = mix(4.0, 7.0, breath);
        float w = sin(p.x * scale + t) * cos(p.y * (scale - 1.0) - t * 0.7);
        w += sin(length(p) * (scale + 3.0) - t * 1.1);
        w += sin((p.x + p.y) * (scale - 1.5) + t * 0.5);
        float net = clamp(0.5 + 0.18 * w, 0.0, 1.0);
        return pow(net, mix(3.0, 6.0, coh));        // crests → bright caustic filaments
    }
    // Evaluate ONE style → (field, vignette). `d` is the aspect-correct radial distance
    // (for the rings + every style's framing); `pf` is a SQUARE, aspect-independent
    // coordinate in [-1,1]² for the 2D fields, so their pattern fills both axes evenly
    // on a tall phone (the old anisotropic coord collapsed the horizontal frequency to
    // near-zero → broad flat bands → the "flat green flood"). Returns x = field, y = vignette.
    float2 styleField(float si, float d, float2 pf, float density, float toneHz,
                      float phase, float coh, float breath, float spread) {
        float field;
        // One generous vignette for every style. The edge is ALWAYS larger than the
        // screen radius (max d ≈ 0.55), so even the smallest Spread can never collapse
        // the look to a black centre — it only tightens the soft frame.
        float vEdge = 0.9 + 0.5 * spread;          // 0.9 … 1.7, always > screen radius
        float vig = smoothstep(vEdge, 0.0, d);
        if (si < 0.5)       field = fieldRings(d, density, phase, coh);
        else if (si < 1.5)  field = fieldChladni(pf, toneHz, phase, coh);
        else if (si < 2.5)  field = fieldPlasma(pf, phase, coh);
        else                field = fieldWater(pf, phase, coh, breath);
        return float2(field, vig);
    }

    // Cheap hash → a sub-LSB dither that removes banding in the dark gradients.
    float echoelHash(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
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
        // Aspect-correct radial distance (for the rings + every style's framing).
        float2 uv = in.uv;
        uv.x *= u.aspect;
        float2 c = float2(0.5 * u.aspect, 0.5);
        float d = distance(uv, c);
        // SQUARE, aspect-independent coordinate in [-1,1]² for the 2D fields, so the
        // pattern keeps its frequency in BOTH axes on a tall phone (fixes the flood).
        float2 pf = in.uv * 2.0 - 1.0;

        // The temporal motion is the ACCUMULATED phase (integrated on the CPU from the
        // flash-safe frequency), NOT time × frequency — so an HR change alters the rate,
        // never snaps the pattern (kills the "ruckeln"). Flash-safety is enforced where
        // the phase is integrated (≤2.5 Hz, < WCAG 3 Hz); this is a pure read.
        float coh = clamp(u.coherence, 0.0, 1.0);
        float density = clamp(u.ringDensity, 4.0, 120.0);
        float phase = u.pulsePhase * 6.2831853;
        float spread = (0.85 + u.breath * 0.35) * clamp(u.spread, 0.4, 1.6);

        // BLEND two looks ("überlappend/mischend"): evaluate style A and style B and mix
        // both their field AND their vignette by the eased Mix ratio. blend 0 = pure A,
        // 1 = pure B, anything between = a true overlap of the two physical fields.
        float blend = clamp(u.blend, 0.0, 1.0);
        float2 fa = styleField(u.style,  d, pf, density, u.toneHz, phase, coh, u.breath, spread);
        float2 fb = styleField(u.styleB, d, pf, density, u.toneHz, phase, coh, u.breath, spread);
        float field    = mix(fa.x, fb.x, blend);
        float vignette = mix(fa.y, fb.y, blend);
        // Breath → a soft central bloom that swells on the inhale (light pressure).
        float bloom = (0.08 + 0.16 * u.breath) * smoothstep(0.5 * spread, 0.0, d);

        // Colour = the heard tone transposed into light (physically correct), now with
        // spatial SPECTRAL DISPERSION so the colours are distributed across the frame
        // (founder: "die Aufteilung der Farben im Raum") instead of one flat hue. The
        // per-pixel wavelength = the tone's wavelength + a spatial offset (radius gives a
        // radial rainbow, the horizontal axis a second gradient), scaled by Spread — like
        // light through water / a prism, still anchored to the heard tone at the centre.
        // Slowly drifts with the flash-safe phase so it breathes. Clamped to the visible
        // band; the CMF naturally dims the deep-red/violet ends.
        float wlBase = toneWavelengthNm(u.toneHz);
        float drift = 18.0 * sin(phase * 0.5);
        float disp = ((d - 0.30) * 165.0 + pf.x * 38.0 + drift) * spread;
        float3 col = wavelengthToRGB(clamp(wlBase + disp, 380.0, 780.0));
        col = mix(col, col * 1.15 + 0.05, coh);
        // Never near-black: deep-red/violet tones are dim via the CMF (eye sensitivity).
        // Lift very dark colours up to a luminance floor while PRESERVING hue, so the
        // look is always a visible colour and can never collapse toward black.
        float lum = dot(col, float3(0.2126, 0.7152, 0.0722));
        col *= (lum < 0.35) ? (0.35 / max(lum, 0.04)) : 1.0;
        col = echoelSaturate(col, clamp(u.saturation, 0.0, 2.0));
        col = echoelHue(col, u.hueShift);
        col *= clamp(u.intensity, 0.0, 1.5);   // user Intensity

        // Compose so the frame is NEVER a dead black: a faint full-frame tone wash
        // (ambient, independent of the vignette so a small Spread can't black it out)
        // rising to the full pattern at its peaks. The pattern keeps the structure;
        // the wash guarantees the look always reads as "on".
        float energy = clamp(field * vignette + bloom, 0.0, 1.0);
        float ambient = 0.06;
        float3 outCol = col * (ambient + (1.0 - ambient) * energy);
        outCol += (echoelHash(in.uv * 1000.0) - 0.5) / 255.0;   // anti-banding dither
        return float4(clamp(outCol, 0.0, 1.0), 1.0);
    }
    """
}
#endif
