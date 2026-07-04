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
    /// DEFAULT 0.82 (not 1): full spectral saturation reads "neon rainbow / amateur"; a
    /// gentle pull toward a graded palette looks professional while staying scientific
    /// (the tone→light hue order is untouched). The VJ control can push it back to vivid.
    var saturation: Float = 0.82
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
    @Environment(VisualRecorder.self) private var visualRecorder
    /// Only the instance that owns the record affordance (the fullscreen VJ cover)
    /// feeds the recorder — keeps a second mounted MetalBioView from double-capturing.
    var capturesVideo: Bool = false
    var reduceMotion: Bool = false
    /// The instrument's current fundamental (Hz) — its colour is the physical
    /// octave-transposition of this pitch into visible light.
    var toneHz: Double = 261.63
    // User look controls (all clamped in the renderer; motion is flash-capped).
    var intensity: Float = 1.0
    var ringDensity: Float = 40
    var motion: Float = 1.0
    var spread: Float = 1.0
    /// VJ palette controls (see BioUniforms). hueShift 0 keeps the physical hue order;
    /// saturation defaults to a graded 0.82 (see BioUniforms) so the palette reads
    /// professional, not neon — pushable back to vivid by the VJ control.
    var hueShift: Float = 0
    var saturation: Float = 0.82
    /// Visual style: 0 rings · 1 Chladni · 2 plasma · 3 water · 4 Prism (see `BioUniforms.style`).
    var style: Int = 0
    /// Secondary style to blend with `style` (same index space). 0 rings · 1 Chladni · 2 plasma · 3 water · 4 Prism.
    var styleB: Int = 0
    /// Mix ratio A↔B [0…1] — 0 = pure `style`, 1 = pure `styleB`. The "mischend" control.
    var blend: Float = 0
    /// Armed brainwave-entrainment visual pulse (Hz, already flash-safe ≤3). When > 0 it
    /// overrides the HR-derived pulse so the picture breathes WITH the entrainment. 0 = off.
    var entrainmentPulseHz: Double = 0

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
        // START on the FAST path (framebufferOnly = true). A blit-readable drawable
        // (framebufferOnly = false) is EXPENSIVE and is only needed WHILE actually recording,
        // so `draw(in:)` flips it false just for the recording frames and back to true after.
        // Keeping it false permanently — which the always-mounted floating capture instance
        // did — disabled Metal's fast path every frame and STUTTERED ("hakelt"). draw(in:)
        // only reads `drawable.texture` on a frame whose drawable was ALREADY readable, so the
        // flip never triggers the mid-frame validation failure that made this permanent before.
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.isOpaque = true
        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        // CRITICAL (stability): do NOT read the live bus / governor `@Observable`s here.
        // `updateUIView` is a SwiftUI graph node — reading `bus.freshBio()` /
        // `bus.freshMusical()` / `governor.settings` (all ~10 Hz) would subscribe this
        // representable AND the enclosing fullscreen overlay to those properties, re-running
        // them 10×/s (the "visuals/controls feel unstable while playing" churn). Instead we
        // forward ONLY the static, user-set look params; the renderer pulls the live bio +
        // governor itself inside `draw(in:)` (the CADisplayLink loop, off the SwiftUI graph).
        let c = context.coordinator
        c.bus = bus
        c.governor = governor
        c.visualRecorder = capturesVideo ? visualRecorder : nil
        c.capturesVideo = capturesVideo
        c.setLook(toneFallbackHz: toneHz, intensity: intensity, ringDensity: ringDensity,
                  motion: motion, spread: spread, hueShift: hueShift, saturation: saturation,
                  style: style, styleB: styleB, blend: blend, reduceMotionAccessibility: reduceMotion,
                  entrainmentPulseHz: entrainmentPulseHz)
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
    /// Last FPS pushed to the MTKView — so we only reassign `preferredFramesPerSecond`
    /// (which reconfigures the CADisplayLink) when the governor's tier actually changes it,
    /// not on every one of the 60 frames/s (free win over a long installation run).
    private var lastAppliedFPS: Int = -1
    /// Last `framebufferOnly` value written to the MTKView. Writing the property EVERY frame
    /// (even to the same value) reconfigures the drawable/CAMetalLayer and made the picture
    /// shimmer ("Visualfenster zittert") — worse at fullscreen resolution and on a style switch
    /// (the palette "Bild Fehler"). We only assign it when the desired state actually flips
    /// (record start / stop), so the steady state never touches the layer config.
    private var lastFramebufferOnly: Bool = true
    private let startTime = CFAbsoluteTimeGetCurrent()
    private var lastFrameTime = CFAbsoluteTimeGetCurrent()
    /// The resource governor receives each frame's timestamp so a sustained FPS drop
    /// can demote the visual tier. The MTKView draw callback runs on the main thread
    /// (default CADisplayLink), so the @MainActor hop below is a safe no-op assertion.
    weak var governor: ResourceGovernor?
    /// The live bio/music source — read HERE in `draw(in:)` (the CADisplayLink loop), not
    /// in `updateUIView`, so the ~10 Hz snapshots never churn the SwiftUI graph / overlay.
    weak var bus: EngineBus?
    /// Optional video-capture sink (set only for the fullscreen VJ instance). When it is
    /// recording, each rendered frame is blitted into it (see the tap in `draw(in:)`).
    weak var visualRecorder: VisualRecorder?
    var capturesVideo = false

    // Static, user-set look params forwarded from `updateUIView` (change on user action,
    // not per-frame). The per-frame bio/governor values are pulled in `draw(in:)` and
    // combined with these. Defaults match the look's neutral state.
    private var lookToneFallbackHz: Double = 261.63
    private var lookIntensity: Float = 1
    private var lookRingDensity: Float = 40
    private var lookMotion: Float = 1
    private var lookSpread: Float = 1
    private var lookHue: Float = 0
    private var lookSaturation: Float = 1
    private var lookStyle: Int = 0
    private var lookStyleB: Int = 0
    private var lookBlend: Float = 0
    private var lookReduceMotionAccessibility = false
    /// Entrainment visual pulse (Hz). When > 0 it OVERRIDES the HR-derived pulse so the
    /// on-screen pulse follows the armed brainwave band's flash-safe sub-harmonic. Always
    /// already ≤3 Hz from `BioEntrainmentDirector.visualHz`; the draw loop re-caps anyway.
    private var lookEntrainmentPulseHz: Double = 0
    /// Slew-limited pulse target — the visual pulse is the most bio-jitter-sensitive value
    /// (a weak-signal rPPG reading can bounce HR, and thus the raw pulse target, hard). We
    /// rate-limit the TARGET here (then glide slowly), so the picture breathes steadily
    /// instead of stuttering with beat-to-beat noise. The measurement stays honest; only
    /// the VISUAL is smoothed (CameraAnalyzer untouched).
    private var smoothedPulseTarget: Float = 0

    /// Store the user's static look params (called from `updateUIView`). No bio/governor
    /// reads here — those are pulled per-frame in `draw(in:)`.
    func setLook(toneFallbackHz: Double, intensity: Float, ringDensity: Float, motion: Float,
                 spread: Float, hueShift: Float, saturation: Float, style: Int, styleB: Int,
                 blend: Float, reduceMotionAccessibility: Bool, entrainmentPulseHz: Double = 0) {
        lookToneFallbackHz = toneFallbackHz
        lookIntensity = intensity
        lookRingDensity = ringDensity
        lookMotion = motion
        lookSpread = spread
        lookHue = hueShift
        lookSaturation = saturation
        lookStyle = style
        lookStyleB = styleB
        lookBlend = blend
        lookReduceMotionAccessibility = reduceMotionAccessibility
        lookEntrainmentPulseHz = entrainmentPulseHz
    }

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
        // 0 rings · 1 Chladni · 2 plasma · 3 water · 4 Prism (spectral dispersion)
        // · 5 Aurora · 6 Lissajous · 7 Depth Caustics · 8 Oscilloscope · 9 Fractal.
        let s = Float(min(max(style, 0), 9))
        target.style = s
        uniforms.style = s
        let sb = Float(min(max(styleB, 0), 9))
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
        // STUTTER FIX ("hakelt"): keep the FAST path (framebufferOnly=true) unless actually
        // recording. Only capture on a frame whose drawable was ALREADY blit-readable coming in
        // (readyToCapture) — so the flip never leaves the texture we read framebuffer-only (the
        // validation failure that once forced this to be permanently false). The single first
        // frame after record-start is skipped (~16 ms, imperceptible). Runs on the main-thread
        // draw loop, so the MTKView property write is main-actor-safe.
        let readyToCapture: Bool = MainActor.assumeIsolated {
            let wantCapture = capturesVideo && (visualRecorder?.isRecording ?? false)
            let ready = wantCapture && !view.framebufferOnly
            // Only touch the property when the desired state actually flips — writing it every
            // frame reconfigures the drawable and made the picture shimmer / glitch (zittert,
            // Bild-Fehler beim Look-Wechsel). Steady state (not recording) never writes it.
            let desired = !wantCapture
            if desired != lastFramebufferOnly {
                view.framebufferOnly = desired
                lastFramebufferOnly = desired
            }
            return ready
        }
        // Pull the live governor + bio HERE — the CADisplayLink draw loop runs on the main
        // thread (so `assumeIsolated` is a safe no-op assertion) and is OFF the SwiftUI
        // dependency graph, so these ~10 Hz `@Observable` reads no longer re-run
        // `updateUIView`/the fullscreen overlay (the visual-instability churn). The governor
        // sets the frame rate + detail tier; the bus gives the freshest bio + live note.
        let nowGov = CFAbsoluteTimeGetCurrent()
        MainActor.assumeIsolated {
            // Aspect EVERY frame from the LIVE drawable size, so the rings are concentric from
            // the FIRST frame. It used to be set only in drawableSizeWillChange, which on launch
            // fires late / with a stale size — the first frames then rendered with the default
            // aspect = 1, which on a tall phone stretches the radial metric into ellipses, so the
            // rings looked non-concentric until a ROTATION forced a resize (founder: "Kreise am
            // Anfang viel, bis man das Handy dreht — sie sollen immer concentrisch sein").
            let ds = view.drawableSize
            if ds.height > 0 { uniforms.aspect = Float(ds.width / ds.height) }
            let q = governor?.settings
            if let q, q.targetFPS != lastAppliedFPS {
                view.preferredFramesPerSecond = q.targetFPS
                lastAppliedFPS = q.targetFPS
            }
            let detailScale = q?.visualDetailScale ?? 1
            let effectiveReduceMotion = lookReduceMotionAccessibility || (q?.reduceMotion ?? false)
            let bio = bus?.freshBio()
            let vp = BioVisualParams.from(bio, reduceMotion: effectiveReduceMotion)
            // Colour follows the MUSIC when sounding (loudest live note), else the tonic.
            let musicTone = bus?.freshMusical(maxAge: 1.5)
                .flatMap { $0.notes.max(by: { $0.amplitude < $1.amplitude })?.frequencyHz }
            // IDLE ATTRACT: with NO bio and NO music, the resting picture would sit on one
            // frozen colour + coherence — pretty but static. Slowly drift the palette, breath
            // and coherence over ~20–60 s so the first seconds feel ALIVE and inviting ("wow
            // von Sekunde 1"). Only when truly idle; frozen under Reduce Motion.
            let idle = (bio == nil) && (musicTone == nil)
            let idleT: Double = effectiveReduceMotion ? 0 : (CFAbsoluteTimeGetCurrent() - startTime)
            let idleTone: Double  = lookToneFallbackHz * (1.0 + 0.18 * sin(idleT * 0.035))
            let idleCoh   = Float(0.5 + 0.25 * sin(idleT * 0.06))
            let idleBreath = Float(0.5 + 0.35 * sin(idleT * 0.09))
            let liveTone = musicTone ?? (idle ? idleTone : lookToneFallbackHz)
            update(hr: bio?.heartRateBPM ?? 60,
                   coherence: bio?.coherence ?? (idle ? idleCoh : 0.5),
                   breath: bio?.breathPhase ?? (idle ? idleBreath : 0.5),
                   toneHz: liveTone,
                   intensity: lookIntensity, ringDensity: lookRingDensity * detailScale,
                   motion: lookMotion, spread: lookSpread,
                   // Armed entrainment overrides the HR-derived pulse so the visual
                   // breathes at the brainwave band's flash-safe sub-harmonic (still
                   // re-capped ≤3 Hz inside update()).
                   pulseHz: Float(lookEntrainmentPulseHz > 0 ? lookEntrainmentPulseHz : vp.pulseHz),
                   hueShift: lookHue, saturation: lookSaturation,
                   style: lookStyle, styleB: lookStyleB, blend: lookBlend,
                   reduceMotion: effectiveReduceMotion)
            // Feed the render cadence back to the governor so a sustained FPS drop can
            // demote the tier (lets it back off detail/FPS if the GPU can't keep up).
            governor?.recordFrame(timestamp: nowGov)
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
            // Visual pulse: slew-limit the target (≤0.5 Hz/s) THEN glide slowly (tau 3 s)
            // so weak-signal HR bounce can't stutter the breathing. Double-smoothed, visual
            // only.
            let pulseSlew = Float(0.5 * dt)
            let dPulse = min(max(target.pulseHz - smoothedPulseTarget, -pulseSlew), pulseSlew)
            smoothedPulseTarget += dPulse
            uniforms.pulseHz   = Self.ease(uniforms.pulseHz,   smoothedPulseTarget, tau: 3.0, dt: dt)
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

        // Video tap: blit this exact rendered frame into the recorder (same command
        // buffer, before present). Only when recording AND the drawable was already
        // blit-readable coming into this frame (readyToCapture) — otherwise the fast-path
        // (framebufferOnly) drawable can't be read. Runs on main (CADisplayLink loop).
        if readyToCapture, let vr = visualRecorder {
            MainActor.assumeIsolated {
                vr.capture(from: drawable.texture, in: buffer, device: drawable.texture.device)
            }
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

    // Multiple drifting COLOUR CLOUDS so the picture is varied ("verschiedene Farbwolken
    // in Kombination") instead of one flat hue or one muddy average. Each cloud is a
    // HARMONIC of the played tone (1st..5th) rendered as its TRUE light colour, placed at
    // its own slowly-drifting centre with a soft Gaussian falloff. The per-pixel colour is
    // the weight-DOMINANT cloud (weighted average, but sharp falloffs mean each region
    // keeps its own cloud's colour — only overlaps blend, never a global average). `glow`
    // returns the summed cloud density so the clouds can softly self-illuminate. Drift is
    // slow (flash-safe); each cloud's colour is fixed, so no colour flashing.
    float3 toneCloudColour(float2 q, float phase, float toneHz, float spread, thread float& glow) {
        float3 acc = float3(0.0);
        float w = 0.0;
        float radius = 0.45 * spread;
        float r2 = max(radius * radius, 1e-4);
        for (int k = 0; k < 5; k++) {
            // ODD harmonics 1,3,5,7,9 → five DISTINCT pitch classes (tonic, fifth, third,
            // seventh, second). Even harmonics are octaves of these and octave-fold to the
            // same colour, which would collapse the variety — odd harmonics stay bunt.
            float h = float(1 + 2 * k);
            float3 ck = wavelengthToRGB(clamp(toneWavelengthNm(toneHz * h), 380.0, 780.0));   // each harmonic → its true light colour
            float a = phase * 0.3 + h * 1.7;                      // slow, flash-safe drift
            float2 ctr = float2(cos(a * 0.7 + h), sin(a + h * 2.0)) * (0.5 * spread);
            float2 dq = q - ctr;
            float wk = exp(-dot(dq, dq) / r2);
            acc += ck * wk;
            w += wk;
        }
        glow = w;
        return acc / max(w, 1e-3);
    }

    // PRISM colour — disperse the sounding tone across space like white light through a
    // glass prism. Horizontal position selects an octave offset around the played tone,
    // so the frame fans the tone's neighbourhood across the full visible spectrum: a
    // rainbow refraction centred on what you hear. A slow refraction drift keeps it alive
    // (flash-safe: the colour at each location is fixed, only the band slides gently);
    // coherence narrows the spread to a tighter, purer spectrum. The downstream warm-
    // desaturation + luminance floor render it as NATURAL daylight, not neon.
    float3 prismColour(float2 q, float toneHz, float phase, float coh) {
        float span   = mix(1.5, 0.7, coh);                       // octaves fanned across frame
        float x      = q.x * 0.5 + 0.05 * sin(phase * 0.3 + q.y * 1.5);   // slow refraction drift
        float octave = clamp(x * span, -4.0, 4.0);               // guard exp2 range
        float hz     = max(toneHz, 1.0) * exp2(octave);
        float3 c     = wavelengthToRGB(clamp(toneWavelengthNm(hz), 380.0, 780.0));   // disperse by true light wavelength
        float band   = 0.85 + 0.15 * cos(q.y * 3.14159265);      // luminous band, not flat fill
        return c * band;
    }

    // ── Visual styles — each returns a scalar field in ~[0,1] ───────────────────
    // STYLE 0 — wave INTERFERENCE rings. Two radial wave trains, the second detuned by
    // coherence, are SUPERPOSED (added) and the visible field is their INTENSITY = |amplitude|²
    // — the physically correct quantity (energy ∝ amplitude²), which yields crisp bright
    // fringes on a dark field instead of a soft sinusoidal wash (the old `0.5+0.5·sin`
    // gradient-haze that read as a blurry rainbow and broke the "no soft gradients" rule).
    // Coherence does double duty, physically: it both detunes the second train (high = nearly
    // aligned → wide ordered fringes; low = turbulent moiré beat) AND sharpens the fringes
    // (coherent light interferes into thin crisp maxima; incoherent washes out).
    float fieldRings(float d, float density, float phase, float coh) {
        float w1 = sin(d * density - phase);
        float detune = mix(1.6, 1.02, coh);                 // high coh → near-unison, ordered
        float w2 = sin(d * density * detune - phase * 0.5);
        float interf = (w1 + w2) * 0.5;                     // superposition, [-1,1]
        float intensity = interf * interf;                  // energy = amplitude² → crisp fringes
        return pow(intensity, mix(1.0, 2.6, coh));          // coherence sharpens the maxima
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
    // STYLE 4 — PRISM: a luminous, mostly-open field so the spectral COLOUR (see
    // prismColour) is the star — the prism's job is dispersion, not dark structure.
    // A slow travelling shimmer adds life; coherence firms it up. Slow phase only, so
    // it stays well under the flash-safety ceiling.
    float fieldPrism(float2 p, float phase, float coh) {
        float shimmer = 0.5 + 0.5 * sin(p.x * 6.0 + phase * 0.6) * cos(p.y * 5.0 - phase * 0.4);
        return clamp(mix(0.80, 0.94, coh) + 0.10 * shimmer, 0.0, 1.0);
    }
    // STYLE 5 — AURORA: soft vertical curtains that wave horizontally and breathe,
    // like northern lights — for ambient/installation looks. Two offset bands drift on
    // the slow flash-safe phase; coherence tightens the curtain edge (ordered vs diffuse).
    // Colour comes from the tone (physical-colour default), so a low tone reads warm, a
    // high tone cool — a real pitch→hue aurora. Pure sin (no loop), compile-safe.
    float fieldAurora(float2 p, float phase, float coh, float breath) {
        float t = phase * 0.35;                                   // slow drift
        float wave = sin(p.x * 2.2 + t) * 0.35 + sin(p.x * 4.7 - t * 0.6) * 0.15;
        float edge = mix(0.55, 0.30, coh);                        // coherence sharpens
        float curtain = 1.0 - smoothstep(0.0, edge, abs(p.y - wave));
        float wave2 = sin(p.x * 3.1 - t * 0.8) * 0.30;
        float curtain2 = 1.0 - smoothstep(0.0, 0.45, abs(p.y + 0.4 - wave2));
        float breathe = 0.8 + 0.2 * sin(phase * 0.5);             // gentle
        return clamp((curtain + curtain2 * 0.6) * breathe, 0.0, 1.0);
    }
    // STYLE 6 — LISSAJOUS: woven nodal figures from two tone-derived axis frequencies
    // (a harmonograph weave). The x/y integer ratios come from the sounding TONE via
    // log2, so pitch shapes the figure; coherence sharpens the lines; the slow phase
    // rotates it. Distinct from Chladni (plate eigenmodes) — this is curve interference.
    float fieldLissajous(float2 p, float toneHz, float phase, float coh) {
        float b = log2(max(toneHz, 1.0));
        float a = 2.0 + floor(fract(b * 0.50) * 4.0);            // 2..5
        float c = 3.0 + floor(fract(b * 0.37 + 0.3) * 4.0);      // 3..6
        float t = phase * 0.5;
        float x = sin(a * p.x * 3.14159265 + t);
        float y = sin(c * p.y * 3.14159265 + t * 0.8);
        float w = mix(0.16, 0.045, coh);                         // coherence sharpens
        return 1.0 - smoothstep(0.0, w, abs(x - y));
    }
    // STYLE 7 — DEPTH CAUSTICS: three superposed caustic layers at increasing scale
    // and decreasing brightness → a parallax/occlusion sense of depth (deeper filaments
    // finer + dimmer), like light through deep water. Manually unrolled (no loop, like
    // fieldWater) for compile safety; slow flash-safe phase only; coherence brightens
    // the crests into caustic filaments.
    float fieldDepthCaustics(float2 p, float phase, float coh, float breath) {
        float t = phase * 0.4;
        float s = mix(3.0, 5.0, breath);
        float w0 = sin(p.x * s + t) * cos(p.y * s - t * 0.8)
                 + sin(length(p) * (s + 2.0) - t * 1.1);
        float s1 = s * 1.7;
        float w1 = sin(p.x * s1 + t + 1.3) * cos(p.y * s1 - t * 0.8 + 1.0)
                 + sin(length(p) * (s1 + 2.0) - t * 1.1 - 1.0);
        float s2 = s1 * 1.7;
        float w2 = sin(p.x * s2 + t + 2.6) * cos(p.y * s2 - t * 0.8 + 2.0)
                 + sin(length(p) * (s2 + 2.0) - t * 1.1 - 2.0);
        float acc = w0 + 0.55 * w1 + 0.30 * w2;
        float net = clamp(0.5 + 0.14 * acc, 0.0, 1.0);
        return pow(net, mix(3.0, 6.0, coh));
    }
    // Cheap hash (moved up from below so the fractal look can build value noise on it)
    // → also the sub-LSB dither that removes banding in the dark gradients.
    float echoelHash(float2 p) {
        p = fract(p * float2(123.34, 456.21));
        p += dot(p, p + 45.32);
        return fract(p.x * p.y);
    }
    // Smooth-interpolated lattice (value) noise from the hash — the octave primitive for
    // the fractal look.
    float valNoise(float2 p) {
        float2 i = floor(p);
        float2 f = fract(p);
        f = f * f * (3.0 - 2.0 * f);                       // smoothstep interpolation
        float a = echoelHash(i);
        float b = echoelHash(i + float2(1.0, 0.0));
        float c = echoelHash(i + float2(0.0, 1.0));
        float d = echoelHash(i + float2(1.0, 1.0));
        return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    }
    // STYLE 8 — OSCILLOSCOPE: a glowing beam tracing a tone-derived waveform (fundamental
    // + two harmonics), scrolling on the slow flash-safe phase; coherence sharpens the
    // beam and a soft halo makes it read as a scope, not a bare line. Pitch sets the wiggle
    // frequency, so a higher note draws a busier trace.
    float fieldScope(float2 p, float toneHz, float phase, float coh) {
        float b = log2(max(toneHz, 1.0));
        float k = 3.0 + floor(fract(b * 0.5) * 6.0);       // 3..8 spatial freq from pitch
        float t = phase * 0.6;                             // slow scroll (≤ flash-safe)
        float wave = 0.55 * sin(p.x * k + t)
                   + 0.25 * sin(p.x * k * 2.0 + t * 1.3)
                   + 0.12 * sin(p.x * k * 3.0 - t * 0.7);
        wave *= 0.5;                                       // amplitude in screen space
        float dist = abs(p.y - wave);
        float thickness = mix(0.05, 0.015, coh);           // coherent → crisper beam
        float trace = 1.0 - smoothstep(0.0, thickness, dist);
        float glow  = 0.15 * (1.0 - smoothstep(0.0, 0.4, dist));
        return clamp(trace + glow, 0.0, 1.0);
    }
    // STYLE 9 — FRACTAL: ridged fractal-Brownian-motion (4 value-noise octaves, manually
    // unrolled — no loops, like fieldWater), drifting slowly and breathing its scale with
    // respiration; coherence sharpens the ridges into filaments. Pairs beautifully UNDER
    // the Oscilloscope via the Blend control — "a mix of oscilloscope and fractals".
    float fieldFractal(float2 p, float phase, float coh, float breath) {
        float t = phase * 0.3;
        float2 q = p * mix(2.0, 3.5, breath) + float2(t, -t * 0.6);
        float n0 = valNoise(q);
        float n1 = valNoise(q * 2.0);
        float n2 = valNoise(q * 4.0);
        float n3 = valNoise(q * 8.0);
        float sum = 0.5000 * (1.0 - abs(2.0 * n0 - 1.0))
                  + 0.2500 * (1.0 - abs(2.0 * n1 - 1.0))
                  + 0.1250 * (1.0 - abs(2.0 * n2 - 1.0))
                  + 0.0625 * (1.0 - abs(2.0 * n3 - 1.0));
        return pow(clamp(sum, 0.0, 1.0), mix(1.0, 2.2, coh));
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
        else if (si < 3.5)  field = fieldWater(pf, phase, coh, breath);
        else if (si < 4.5)  field = fieldPrism(pf, phase, coh);
        else if (si < 5.5)  field = fieldAurora(pf, phase, coh, breath);
        else if (si < 6.5)  field = fieldLissajous(pf, toneHz, phase, coh);
        else if (si < 7.5)  field = fieldDepthCaustics(pf, phase, coh, breath);
        else if (si < 8.5)  field = fieldScope(pf, toneHz, phase, coh);
        else                field = fieldFractal(pf, phase, coh, breath);
        return float2(field, vig);
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
        // Only evaluate the SECOND look when actually blending. At the default blend = 0 the
        // B field is fully masked by mix(), so computing it is pure waste — and B can be a
        // heavy look (Fractal/Depth), doubling fragment cost for nothing. Skip it below the
        // blend threshold; this is the common single-style case (perf/thermal win).
        float2 fb = (blend > 0.001)
            ? styleField(u.styleB, d, pf, density, u.toneHz, phase, coh, u.breath, spread)
            : fa;
        float field    = mix(fa.x, fb.x, blend);
        float vignette = mix(fa.y, fb.y, blend);
        // HEARTBEAT (V3, deepened): the body must VISIBLY drive the picture ("dein Herzschlag
        // treibt es an", not a faint flicker). Breath sets the resting glow; each heartbeat
        // both BRIGHTENS the central bloom AND EXPANDS its radius, so the pulse reads as a
        // clear expanding bloom. Flash-safe: `phase` is integrated from a ≤2.5 Hz clock
        // (< WCAG 3 Hz), so even the larger swing can never strobe.
        float beat = 0.5 - 0.5 * cos(phase);            // 0…1 once per heartbeat
        float restGlow = 0.07 + 0.14 * u.breath;        // breath = resting swell
        float beatGain = 0.55 + 0.80 * beat;            // ~0.55…1.35 (was 0.80…1.00 — 4× swing)
        float bloomEdge = (0.44 + 0.24 * beat) * spread; // radius pulses with the beat
        float bloom = restGlow * beatGain * smoothstep(bloomEdge, 0.0, d);

        // Colour = drifting CLOUDS of the tone's harmonic colours distributed across the
        // frame (founder: "verschiedene Farbwolken in Kombination … nicht zu einer
        // Mischung") — a varied, bunt picture where each region keeps its own colour,
        // anchored to the heard tone's overtone series. `cloudGlow` lets them softly glow.
        float cloudGlow = 0.0;
        float3 col = toneCloudColour(pf, phase, u.toneHz, spread, cloudGlow);
        // PRISM look: replace the cloud colour with a spatial spectral dispersion (a
        // rainbow refraction of the sounding tone). Weighted by how much the active
        // look(s) are Prism (style/styleB == 4), so blending Prism↔another look cross-
        // fades the colour too. Injected BEFORE the natural-light block so the rainbow
        // is rendered as warm daylight, not neon.
        float prismW = clamp(step(3.5, u.style) * (1.0 - blend) + step(3.5, u.styleB) * blend, 0.0, 1.0);
        if (prismW > 0.0) { col = mix(col, prismColour(pf, u.toneHz, phase, coh), prismW); }
        // NATURAL WARM LIGHT (founder): pure spectral colours look "neon"; nature's light
        // — a prism/rainbow in warm daylight — is warmer and a touch less saturated. Pull
        // gently toward a warm white point (~3500 K) and ease the saturation, keeping the
        // warmth in the desaturated part so it never goes cold/grey. Still bunt; the user
        // Saturation control can push it back to vivid. Hue order/variety is preserved.
        {
            float l = dot(col, float3(0.2126, 0.7152, 0.0722));
            float3 warm = float3(1.0, 0.92, 0.80);          // warm daylight white point
            col = mix(float3(l) * warm, col, 0.80);         // warm-tinted desaturation (was .85 — ease neon further)
            col = mix(col, warm, 0.10);                     // slight overall warm lift
        }
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
        // (ambient) + a soft self-illumination of the colour clouds (so they read as
        // floating colour even between the field's bright structure) rising to the full
        // pattern at its peaks. The pattern keeps the structure; the clouds carry colour.
        float glow = clamp(cloudGlow * 0.22, 0.0, 0.5);
        float energy = clamp(field * vignette + bloom + glow, 0.0, 1.0);
        float ambient = 0.06;
        float3 outCol = col * (ambient + (1.0 - ambient) * energy);
        // Premium finish: a gentle filmic S-contrast so the frame reads rich/graded, not flat
        // (deepens shadows, lifts highlights a touch). Cheap, no new uniforms; degrade-safe.
        outCol = clamp((outCol - 0.5) * 1.06 + 0.5, 0.0, 1.0);
        outCol += (echoelHash(in.uv * 1000.0) - 0.5) / 255.0;   // anti-banding dither
        return float4(clamp(outCol, 0.0, 1.0), 1.0);
    }
    """
}
#endif
