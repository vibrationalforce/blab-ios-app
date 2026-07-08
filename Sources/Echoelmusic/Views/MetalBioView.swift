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
    /// COLOUR CROSSFADE pair (anti-strobe law, part 1 — PRISM only): the prism fan is
    /// a per-pixel RGB fade from the PREVIOUS note's dispersion (A) to the CURRENT
    /// note's (B) — NEVER computed from an eased frequency. Gliding Hz sweeps the hue
    /// through every colour between two notes, and when the glide crosses the
    /// visible-band edge the octave-fold in toneWavelengthNm wraps red↔violet in ONE
    /// frame ("Kästchen flackern"). A/B are discrete note frequencies; only the MIX
    /// eases, and retargets are GATED until the running fade is well past halfway.
    var colorToneA: Float = 261.63
    var colorToneB: Float = 261.63
    var colorFade: Float = 1
    /// Anti-strobe law, part 2 — the CLOUDS (the default colour of every look): five
    /// RGB triples, one per REALLY-SOUNDING note (see cc*x/y/w below), EASED
    /// PER-CHANNEL ON THE CPU (SpectralColor twins the shader's CIE fit). A colour
    /// that CHASES its target can never jump, no matter how fast notes retrigger —
    /// the A/B crossfade alone was retargeted faster than it could complete on fast
    /// finger slides, and every retarget flashed the stale A end for a frame (the
    /// fullscreen "Bildfehler" while playing the touch instrument).
    var cc0r: Float = 0; var cc0g: Float = 0; var cc0b: Float = 0
    var cc1r: Float = 0; var cc1g: Float = 0; var cc1b: Float = 0
    var cc2r: Float = 0; var cc2g: Float = 0; var cc2b: Float = 0
    var cc3r: Float = 0; var cc3g: Float = 0; var cc3b: Float = 0
    var cc4r: Float = 0; var cc4g: Float = 0; var cc4b: Float = 0
    /// Per-cloud PLACEMENT + PRESENCE (founder 2026-07-08: "die Farben nur erscheinen
    /// und an der richtigen Stelle, wenn die entsprechenden Töne auch kommen — egal
    /// ob vom Visual Touch Instrument selbst oder von den anderen Sound Quellen").
    /// Each cloud is a SLOT for one really-sounding note: anchored at the note's
    /// pitch-space position (x = within-octave, y = octave height — the fretboard's
    /// layout, +y up) and weighted by how loudly that note sounds RIGHT NOW (touch
    /// notes at full weight, generative bus notes at their amplitude). All weights
    /// 0 = silence → the shader shows a warm neutral: no tone, no colour.
    var cc0x: Float = 0; var cc0y: Float = 0; var cc0w: Float = 0
    var cc1x: Float = 0; var cc1y: Float = 0; var cc1w: Float = 0
    var cc2x: Float = 0; var cc2y: Float = 0; var cc2w: Float = 0
    var cc3x: Float = 0; var cc3y: Float = 0; var cc3w: Float = 0
    var cc4x: Float = 0; var cc4y: Float = 0; var cc4w: Float = 0
}

/// Touch → visual excitation channel (founder 2026-07-07: "das Spiel mit den Fingern
/// beeinflusst die visuals noch mehr"). The play surface (TouchInstrumentView) pushes
/// energy in on every note; the renderer's draw loop consumes it per frame, boosting
/// intensity/motion so the picture visibly SWELLS under the fingers and relaxes when
/// they rest. Lock-protected + decayed on read (same hand-off pattern as the rPPG
/// RGBSampleQueue) — zero SwiftUI invalidations, safe from any thread, and the boost
/// rides through the renderer's existing eased targets, so it glides rather than snaps.
/// Flash-safety unaffected: the pulse/flash rate is capped downstream regardless.
final class TouchVisualEnergy: @unchecked Sendable {
    static let shared = TouchVisualEnergy()
    private let lock = NSLock()
    private var energy: Float = 0
    private var lastRead: CFTimeInterval = 0

    /// Add excitation (touch began ≈ 0.35, slide re-trigger ≈ 0.15). Clamped to 1.
    func excite(_ amount: Float) {
        lock.lock()
        energy = min(1, energy + max(0, amount))
        lock.unlock()
    }

    /// Current energy, decayed exponentially (~1.2 s time constant) since the last
    /// read — called once per rendered frame, so the swell breathes out naturally.
    func value(now: CFTimeInterval) -> Float {
        lock.lock()
        defer { lock.unlock() }
        if lastRead == 0 { lastRead = now }
        let dt = Float(max(0, now - lastRead))
        lastRead = now
        energy = max(0, energy * exp(-dt / 1.2))
        return energy
    }

    /// Drop all energy (session stop / window dismissed).
    func reset() {
        lock.lock()
        energy = 0
        lastRead = 0
        lock.unlock()
    }
}

/// The tone the PERFORMER'S FINGER is sounding right now (founder 2026-07-08: "die
/// Töne die gespielt werden sollen in die physikalisch hochglanzpolierten Farben
/// übersetzt werden"). Touch notes play on their own synth and never pass through
/// the bus's musical frames (those come from the piano-roll tick), so without this
/// channel the picture's tone→colour could not see the played note. Same lock-safe
/// leaf pattern as TouchVisualEnergy; the draw loop polls it once per frame and the
/// finger takes PERFORMER PRIORITY over the generative bed while fresh (~1.2 s).
final class TouchToneChannel: @unchecked Sendable {
    static let shared = TouchToneChannel()
    private let lock = NSLock()
    /// HELD notes, most-recent-first (founder 2026-07-08: "100 % der Sound in den
    /// richtigen Farben … chords etc." — a chord must paint ALL its colours, not
    /// just the last finger). Capped to the touch surface's max simultaneous
    /// touches; each entry keeps its pitch (identity for noteOff), frequency and
    /// last-touch time (staleness safety net if a noteOff ever gets lost).
    private var held: [(pitch: Int, hz: Double, stamp: CFTimeInterval)] = []
    private static let maxHeld = 5
    /// Afterglow: the most recent tone lingers ~1.2 s after ALL fingers lift, so
    /// the colour hands back to the generative bed softly instead of snapping.
    private var lastHz: Double = 0
    private var lastStamp: CFTimeInterval = 0

    /// A finger note starts (or a slide retriggers into a new pitch).
    func noteOn(pitch: Int, hz: Double, at now: CFTimeInterval) {
        guard hz.isFinite, hz > 0 else { return }
        lock.lock()
        held.removeAll { $0.pitch == pitch }
        held.insert((pitch, hz, now), at: 0)
        if held.count > Self.maxHeld { held.removeLast(held.count - Self.maxHeld) }
        lastHz = hz
        lastStamp = now
        lock.unlock()
    }

    /// A finger note ends (lift or slide-away).
    func noteOff(pitch: Int, at now: CFTimeInterval) {
        lock.lock()
        held.removeAll { $0.pitch == pitch }
        if held.isEmpty { lastStamp = now }   // afterglow starts when the LAST finger lifts
        lock.unlock()
    }

    /// Every sounding finger tone, most-recent-first. While notes are held they
    /// stay (with a 30 s staleness net); when none are held, the most recent tone
    /// lingers for `maxAge` (afterglow), then empty = hand back to the bed.
    func activeHz(now: CFTimeInterval, maxAge: CFTimeInterval = 1.2) -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        held.removeAll { now - $0.stamp > 30 }   // lost-noteOff safety net
        if !held.isEmpty { return held.map(\.hz) }
        guard lastHz > 0, now - lastStamp <= maxAge else { return [] }
        return [lastHz]
    }

    func reset() {
        lock.lock()
        held.removeAll()
        lastHz = 0
        lastStamp = 0
        lock.unlock()
    }
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
    /// The frequency currently driving the COLOUR. A per-frame `argmax` over note amplitudes
    /// hops between near-tied notes (chords/arpeggios) and made the colour wobble as it chased
    /// a jumpy target. We hold the chosen note and only hand off when a challenger is clearly
    /// louder (see the margin in `draw`), so the colour glides between notes instead of flicking.
    private var colorToneHz: Double = 0
    /// Colour-crossfade state (see BioUniforms.colorToneA/B): the discrete note pair
    /// whose colour fields the shader mixes, and the eased 0→1 fade between them.
    private var colorNoteFrom: Float = 261.63
    private var colorNoteTo: Float = 261.63
    private var colorNoteFade: Float = 1
    /// CPU-eased cloud colours (see BioUniforms.cc*) — chase the target, never jump.
    private var cloudRGB = [SIMD3<Float>](repeating: .zero, count: 5)
    private var cloudSeeded = false
    /// Cloud SLOTS (see BioUniforms.cc*x/y/w): each of the 5 clouds holds ONE
    /// really-sounding note across frames. Identity = nearest semitone (so a held
    /// note keeps its slot, colour and place), anchor = the note's pitch-space
    /// position, weight eases in on note-on and out on note-off/silence.
    private var cloudID = [Int](repeating: Int.min, count: 5)
    private var cloudHzSlot = [Double](repeating: 0, count: 5)
    private var cloudPos = [SIMD2<Float>](repeating: .zero, count: 5)
    private var cloudW = [Float](repeating: 0, count: 5)

    /// Slot identity for a sounding frequency: its nearest semitone (A4 = 440 ref —
    /// only an ID, the exact Hz still drives colour/place, so any Kammerton/tuning
    /// keeps its true colour). Int.min = invalid/free.
    private static func noteID(_ hz: Double) -> Int {
        guard hz.isFinite, hz > 0 else { return Int.min }
        return Int((12.0 * Foundation.log2(hz / 440.0) + 69.0).rounded())
    }

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
        let sb = Float(min(max(styleB, 0), 9))
        // "Grafikterror" fix (founder 2026-07-08): when the (A,B) STYLE PAIR changes —
        // scrubbing the stufenlos slider across a segment boundary — the styles snap
        // but the eased `blend` still holds the OLD pair's mix for ~0.3–1 s, so the
        // picture flashes ~100% of a look the user never steered to (e.g. crossing
        // Aurora→Depth briefly renders Plasma), and fast scrubbing strobes wrong
        // fields. The slider hand-off is continuous BY CONSTRUCTION (old pair at
        // blend≈1 ≡ new pair at blend≈0 — both are the SAME pure look), so the only
        // correct behaviour is to snap blend WITH the pair. Easing remains for
        // within-pair morphs (the smooth A↔B crossfade the slider is for).
        let pairChanged = hasTarget && (uniforms.style != s || uniforms.styleB != sb)
        target.style = s
        uniforms.style = s
        target.styleB = sb
        uniforms.styleB = sb
        target.blend = min(max(blend.isFinite ? blend : 0, 0), 1)
        if pairChanged { uniforms.blend = target.blend }
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
            // Seed the pulse slew-follower at the real target too — else it starts at 0 and
            // the very next frame eases pulseHz back down toward 0 and ramps up over ~3 s,
            // so the breathing visibly stalls-then-ramps at launch (undercuts "wow ab Sek. 1").
            smoothedPulseTarget = target.pulseHz
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
        // PERFORMER PRIORITY input (founder: played notes → their physical colours,
        // "chords etc."): every HELD finger note, most-recent-first. Declared at
        // function scope — read here for the tone selection below AND by the cloud
        // colour easing further down (outside the assumeIsolated closure).
        // Lock-protected channel, no actor hop needed.
        let playedNotes = TouchToneChannel.shared.activeHz(now: nowGov)
        // EVERY really-sounding note from EVERY source (founder 2026-07-08: colours
        // only when/where tones come, "egal ob vom Visual Touch Instrument selbst
        // oder von den anderen Sound Quellen"): touch notes first at full weight,
        // then the generative bed's notes at their live amplitude. Declared at
        // function scope (compile lesson 8873363); FILLED inside the MainActor
        // block below because the bus's musical snapshot is @MainActor.
        var soundingNotes: [(id: Int, hz: Double, amp: Float)] = []
        // Live musical LEVEL [0,1] (MusicalFrame.masterLevel — published since the
        // DMMW backbone, unused by the visual until now): the picture's energy
        // breathes WITH the music's actual density/loudness ("ineinandergreifen"),
        // exactly like TouchVisualEnergy does for the fingers. Eased downstream
        // (intensity tau 0.4), so tick-stepped levels read as a musical swell,
        // never a flicker.
        var musicLevel: Float = 0
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
            // Colour follows the MUSIC when sounding, else the tonic. HYSTERESIS: keep the
            // current colour note and only hand off to the loudest one when it's clearly louder
            // (≥30 %) than the note currently driving the colour — so chords/arpeggios with
            // near-tied amplitudes don't make the colour flick between pitches (the wobble).
            var musicTone: Double?
            // The newest finger note drives the geometry tone and seeds the
            // hysteresis holder; the full chord feeds the cloud colours below.
            if let played = playedNotes.first {
                colorToneHz = played
                musicTone = played
            } else if let frame = bus?.freshMusical(maxAge: 1.5), let loudest = frame.notes.max(by: { $0.amplitude < $1.amplitude }) {
                let currentAmp = frame.notes.first(where: { abs($0.frequencyHz - colorToneHz) < 0.5 })?.amplitude ?? 0
                if colorToneHz == 0 || loudest.amplitude > currentAmp * 1.3 {
                    colorToneHz = loudest.frequencyHz
                }
                musicTone = colorToneHz
            } else {
                colorToneHz = 0            // music stopped — release, so the next note adopts cleanly
                musicTone = nil
            }
            // Gather the sounding notes for the cloud slots. Touch notes carry full
            // weight (a finger IS the performance); the generative roll's chord
            // arrives with each note's real velocity→amplitude (perceptual sqrt).
            // Deduped by nearest semitone, capped at the 5 cloud slots.
            for hz in playedNotes {
                guard soundingNotes.count < 5 else { break }
                let id = Self.noteID(hz)
                guard id != Int.min else { continue }
                if !soundingNotes.contains(where: { $0.id == id }) {
                    soundingNotes.append((id, hz, 1.0))
                }
            }
            let mf = bus?.freshMusical(maxAge: 0.5)
            musicLevel = Float(mf?.masterLevel ?? 0)
            if soundingNotes.count < 5, let mf {
                for n in mf.notes.sorted(by: { $0.amplitude > $1.amplitude }) {
                    guard soundingNotes.count < 5 else { break }
                    guard n.amplitude > 0.02 else { continue }
                    let id = Self.noteID(n.frequencyHz)
                    guard id != Int.min else { continue }
                    if !soundingNotes.contains(where: { $0.id == id }) {
                        soundingNotes.append((id, n.frequencyHz, Float(n.amplitude.squareRoot())))
                    }
                }
            }
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
            // Finger-play excitation: notes on the play surface pump energy in; the
            // picture SWELLS (brighter, livelier, wider) under the hands and breathes
            // back out over ~a second when they rest. Rides the eased targets below,
            // so it glides. Flash rate stays capped inside update() regardless.
            let touchE = TouchVisualEnergy.shared.value(now: nowGov)
            update(hr: bio?.heartRateBPM ?? 60,
                   coherence: bio?.coherence ?? (idle ? idleCoh : 0.5),
                   breath: bio?.breathPhase ?? (idle ? idleBreath : 0.5),
                   toneHz: liveTone,
                   // Energy interlocks with what actually SOUNDS: fingers pump touchE,
                   // the generative music adds its live master level — the picture
                   // swells with the arrangement and rests in the quiet bars.
                   intensity: lookIntensity * (1 + 0.45 * touchE + 0.30 * musicLevel),
                   ringDensity: lookRingDensity * detailScale,
                   motion: lookMotion * (1 + 0.30 * touchE),
                   spread: lookSpread * (1 + 0.20 * touchE),
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
            // COLOUR (anti-strobe law; eased toneHz above drives GEOMETRY only):
            // 1) CLOUDS — each sounding note's colour is eased PER-CHANNEL in RGB
            //    toward its physically exact target (Swift SpectralColor twins the
            //    shader's CIE fit). A chasing colour cannot jump at ANY retrigger
            //    rate — the pure A/B crossfade flashed its stale A end on every
            //    fast-slide retarget (the fullscreen "Bildfehler" while playing).
            // Cloud SLOTS (founder 2026-07-08: "die Farben nur erscheinen und an der
            // richtigen Stelle, wenn die entsprechenden Töne auch kommen — egal von
            // welcher Quelle"): each of the 5 clouds holds ONE really-sounding note.
            // A slot keeps its note across frames (identity = nearest semitone), its
            // anchor is the note's pitch-space position (SpectralColor.notePosition —
            // the fretboard's layout: within-octave → x, octave height → y), and its
            // weight EASES in on note-on / out on note-off, so colour appears exactly
            // when and where a tone sounds and breathes away when it stops. No
            // decorative harmonics anymore — silence means neutral, never fake colour.
            var slotTaken = [Bool](repeating: false, count: 5)
            var slotSeeded = [Bool](repeating: false, count: 5)
            var noteConsumed = [Bool](repeating: false, count: soundingNotes.count)
            var targetW = [Float](repeating: 0, count: 5)
            // 1) Slots keep the note they already hold (stable colour + place).
            for k in 0..<5 where cloudID[k] != Int.min {
                if let i = soundingNotes.indices.first(where: { !noteConsumed[$0] && soundingNotes[$0].id == cloudID[k] }) {
                    noteConsumed[i] = true
                    slotTaken[k] = true
                    cloudHzSlot[k] = soundingNotes[i].hz
                    targetW[k] = soundingNotes[i].amp
                }
            }
            // 2) New notes claim the quietest free slot. A TRULY free slot (weight
            //    ~0) snaps colour+place invisibly and fades in. A still-VISIBLE slot
            //    being reassigned (all 5 occupied — e.g. a dense bed + new touch
            //    note) is NEVER cut: it keeps its weight, and the per-channel colour
            //    chase (tau 0.18) + position chase (tau 0.25, step 3) carry it over
            //    to the new note — the anti-strobe law holds under stealing too
            //    (review 2026-07-08: the old weight-to-0 cut popped a visible cloud
            //    out in one frame, the exact class this design exists to prevent).
            for i in soundingNotes.indices where !noteConsumed[i] {
                let free = (0..<5).filter { !slotTaken[$0] }
                guard let k = free.min(by: { cloudW[$0] < cloudW[$1] }) else { break }
                slotTaken[k] = true
                cloudID[k] = soundingNotes[i].id
                cloudHzSlot[k] = soundingNotes[i].hz
                targetW[k] = soundingNotes[i].amp
                if cloudW[k] < 0.004 {
                    slotSeeded[k] = true      // invisible: snap colour + place, fade in
                    cloudW[k] = 0
                }
            }
            // 3) Ease weights (fast in — a played note must answer NOW; softer out)
            //    and chase each held slot's exact note colour per-channel AND its
            //    pitch-space place (anti-strobe law: neither colour nor position can
            //    ever jump on a visible cloud, at any retrigger/steal rate).
            for k in 0..<5 {
                let up = targetW[k] > cloudW[k]
                cloudW[k] = Self.ease(cloudW[k], targetW[k], tau: up ? 0.09 : 0.35, dt: dt)
                if !slotTaken[k], cloudW[k] < 0.004 { cloudID[k] = Int.min }   // slot free again
                guard cloudHzSlot[k] > 0 else { continue }
                let wl = SpectralColor.visibleWavelength(forToneHz: cloudHzSlot[k])
                let c = SpectralColor.wavelengthToLinearRGB(wl)
                let t = SIMD3<Float>(Float(c.r), Float(c.g), Float(c.b))
                let p = SpectralColor.notePosition(forHz: cloudHzSlot[k])
                let tp = SIMD2<Float>(Float(p.x), Float(p.y))
                let snap = !cloudSeeded || slotSeeded[k]
                cloudRGB[k] = snap ? t
                    : SIMD3<Float>(Self.ease(cloudRGB[k].x, t.x, tau: 0.18, dt: dt),
                                   Self.ease(cloudRGB[k].y, t.y, tau: 0.18, dt: dt),
                                   Self.ease(cloudRGB[k].z, t.z, tau: 0.18, dt: dt))
                cloudPos[k] = snap ? tp
                    : SIMD2<Float>(Self.ease(cloudPos[k].x, tp.x, tau: 0.25, dt: dt),
                                   Self.ease(cloudPos[k].y, tp.y, tau: 0.25, dt: dt))
            }
            cloudSeeded = true
            (uniforms.cc0r, uniforms.cc0g, uniforms.cc0b) = (cloudRGB[0].x, cloudRGB[0].y, cloudRGB[0].z)
            (uniforms.cc1r, uniforms.cc1g, uniforms.cc1b) = (cloudRGB[1].x, cloudRGB[1].y, cloudRGB[1].z)
            (uniforms.cc2r, uniforms.cc2g, uniforms.cc2b) = (cloudRGB[2].x, cloudRGB[2].y, cloudRGB[2].z)
            (uniforms.cc3r, uniforms.cc3g, uniforms.cc3b) = (cloudRGB[3].x, cloudRGB[3].y, cloudRGB[3].z)
            (uniforms.cc4r, uniforms.cc4g, uniforms.cc4b) = (cloudRGB[4].x, cloudRGB[4].y, cloudRGB[4].z)
            (uniforms.cc0x, uniforms.cc0y, uniforms.cc0w) = (cloudPos[0].x, cloudPos[0].y, cloudW[0])
            (uniforms.cc1x, uniforms.cc1y, uniforms.cc1w) = (cloudPos[1].x, cloudPos[1].y, cloudW[1])
            (uniforms.cc2x, uniforms.cc2y, uniforms.cc2w) = (cloudPos[2].x, cloudPos[2].y, cloudW[2])
            (uniforms.cc3x, uniforms.cc3y, uniforms.cc3w) = (cloudPos[3].x, cloudPos[3].y, cloudW[3])
            (uniforms.cc4x, uniforms.cc4y, uniforms.cc4w) = (cloudPos[4].x, cloudPos[4].y, cloudW[4])
            // 2) PRISM keeps the discrete A→B fade (its colour is a continuous octave
            //    fan of the note Hz — not reducible to one RGB). Retargets are GATED
            //    until the running fade passes 0.6 (the newest target wins next frame,
            //    re-checked here every frame) so fast retriggers can no longer flash
            //    the stale A end.
            if abs(target.toneHz - colorNoteTo) > 0.5, colorNoteFade >= 0.6 {
                colorNoteFrom = colorNoteTo
                colorNoteTo = target.toneHz
                colorNoteFade = 0
            }
            colorNoteFade = Self.ease(colorNoteFade, 1, tau: 0.18, dt: dt)
            uniforms.colorToneA = colorNoteFrom
            uniforms.colorToneB = colorNoteTo
            uniforms.colorFade = colorNoteFade
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
            // Fallback: gentle clear-colour pulse (shader absent). Drive it from the
            // INTEGRATED pulsePhase (same as the main path) — NOT `time × pulseHz`, which
            // snaps the phase whenever pulseHz changes (the very jump the main path was
            // rewritten to avoid). Frozen under Reduce Motion via the phase not advancing.
            let beat = 0.15 + 0.12 * (0.5 + 0.5 * sin(2 * .pi * Double(uniforms.pulsePhase)))
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
                      float styleB; float blend; float colorToneA; float colorToneB; float colorFade;
                      float cc0r; float cc0g; float cc0b; float cc1r; float cc1g; float cc1b;
                      float cc2r; float cc2g; float cc2b; float cc3r; float cc3g; float cc3b;
                      float cc4r; float cc4g; float cc4b;
                      float cc0x; float cc0y; float cc0w; float cc1x; float cc1y; float cc1w;
                      float cc2x; float cc2y; float cc2w; float cc3x; float cc3y; float cc3w;
                      float cc4x; float cc4y; float cc4w; };

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

    // COLOUR CLOUDS = the really-sounding notes, each AT ITS PITCH-SPACE PLACE
    // (founder 2026-07-08: "die Farben nur erscheinen und an der richtigen Stelle,
    // wenn die entsprechenden Töne auch kommen — egal von welcher Quelle"). Each
    // cloud is one sounding note: its colour arrives PRE-EASED from the CPU (per-
    // channel RGB chase toward the exact note colour — SpectralColor twins this
    // shader's CIE fit, the anti-strobe law), its anchor is the note's position
    // (x = within-octave, y = octave height — the fretboard's layout) and its
    // weight is how loudly the note sounds RIGHT NOW (eased in/out on the CPU).
    // A silent slot (weight ~0) contributes NOTHING — no tone, no colour. A tiny
    // flash-safe breathing around the anchor keeps a held note alive without
    // moving it off its place. `glow` returns the summed weighted density so the
    // fragment can gate colour to where notes actually are.
    float3 toneCloudColour(float2 q, float phase, constant Uniforms& u,
                           float spread, thread float& glow) {
        float3 cols[5];
        cols[0] = float3(u.cc0r, u.cc0g, u.cc0b);
        cols[1] = float3(u.cc1r, u.cc1g, u.cc1b);
        cols[2] = float3(u.cc2r, u.cc2g, u.cc2b);
        cols[3] = float3(u.cc3r, u.cc3g, u.cc3b);
        cols[4] = float3(u.cc4r, u.cc4g, u.cc4b);
        float2 anchors[5];
        anchors[0] = float2(u.cc0x, u.cc0y);
        anchors[1] = float2(u.cc1x, u.cc1y);
        anchors[2] = float2(u.cc2x, u.cc2y);
        anchors[3] = float2(u.cc3x, u.cc3y);
        anchors[4] = float2(u.cc4x, u.cc4y);
        float wgts[5] = { u.cc0w, u.cc1w, u.cc2w, u.cc3w, u.cc4w };
        float3 acc = float3(0.0);
        float w = 0.0;
        float radius = 0.42 * spread;
        float r2 = max(radius * radius, 1e-4);
        for (int k = 0; k < 5; k++) {
            if (wgts[k] < 0.004) continue;                        // note not sounding → no colour
            float h = float(1 + 2 * k);
            float a = phase * 0.3 + h * 1.7;                      // slow, flash-safe breathing
            float2 ctr = anchors[k] + 0.06 * float2(cos(a * 0.7 + h), sin(a + h * 2.0));
            float2 dq = q - ctr;
            float wk = wgts[k] * exp(-dot(dq, dq) / r2);
            acc += cols[k] * wk;
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
    float3 prismColour(float2 q, float toneA, float toneB, float fade, float phase, float coh) {
        float span   = mix(1.5, 0.7, coh);                       // octaves fanned across frame
        float x      = q.x * 0.5 + 0.05 * sin(phase * 0.3 + q.y * 1.5);   // slow refraction drift
        float octave = clamp(x * span, -4.0, 4.0);               // guard exp2 range
        // Same anti-strobe crossfade as the clouds: fan BOTH note spectra and mix in RGB.
        float hzA    = max(toneA, 1.0) * exp2(octave);
        float hzB    = max(toneB, 1.0) * exp2(octave);
        float3 c     = mix(wavelengthToRGB(clamp(toneWavelengthNm(hzA), 380.0, 780.0)),
                           wavelengthToRGB(clamp(toneWavelengthNm(hzB), 380.0, 780.0)), fade);
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

        // Colour = CLOUDS of the really-sounding notes, each anchored at its pitch-
        // space place (founder 2026-07-08) — a chord paints its actual note colours
        // side by side WHERE those notes live; regions with no sounding note stay
        // neutral (gated below). `cloudGlow` = the summed weighted density, used for
        // both the soft self-illumination and the colour-truth gate.
        float cloudGlow = 0.0;
        float tfade = clamp(u.colorFade, 0.0, 1.0);
        float3 col = toneCloudColour(pf, phase, u, spread, cloudGlow);
        // PRISM look: replace the cloud colour with a spatial spectral dispersion (a
        // rainbow refraction of the sounding tone). Weighted by how much the active
        // look(s) are Prism (style/styleB == 4 EXACTLY), so blending Prism↔another
        // look crossfades the colour too. Injected BEFORE the natural-light block so
        // the rainbow is rendered as warm daylight, not neon.
        // FIX (founder 2026-07-08 "eindeutiger zum Sound"): the old `step(3.5, style)`
        // selected EVERY look ≥ 4 — Aurora/Lissajous/Depth/Scope/Fractal were all
        // silently prism-coloured, so six of ten looks never showed the placed
        // note-clouds. Prism colour now belongs to the Prism look ONLY; every other
        // look paints the sounding notes at their pitch-space places.
        float isPrismA = step(3.5, u.style)  * step(u.style,  4.5);
        float isPrismB = step(3.5, u.styleB) * step(u.styleB, 4.5);
        float prismW = clamp(isPrismA * (1.0 - blend) + isPrismB * blend, 0.0, 1.0);
        if (prismW > 0.0) { col = mix(col, prismColour(pf, u.colorToneA, u.colorToneB, tfade, phase, coh), prismW); }
        // COLOUR TRUTH GATE (founder 2026-07-08): colour exists ONLY when and WHERE
        // a tone is really sounding. The clouds' summed LOCAL density (each already
        // weighted by its note's live level) gates the cloud colour per-pixel — the
        // colour sits at the note's place and fades to a warm neutral away from it.
        // The prism fan is a fullscreen dispersion of the tone, so it gates on the
        // GLOBAL presence of any sounding note instead. Silence → a warm neutral
        // field: the structure stays alive, the colour waits for the music.
        float presence = clamp((u.cc0w + u.cc1w + u.cc2w + u.cc3w + u.cc4w) * 1.8, 0.0, 1.0);
        float colourOn = mix(clamp(cloudGlow * 1.6, 0.0, 1.0), presence, prismW);
        col = mix(float3(0.60, 0.56, 0.50), col, colourOn);
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
