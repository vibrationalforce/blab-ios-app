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
    ///
    /// ⭐ DEFAULT 1.05 SINCE #578 — FOUNDER, 2026-08-13, asked plainly for the opposite of
    /// what this default was tuned for: *"je intensiver das Erlebnis desto besser. Bunter,
    /// mehr Textur, Glitzer etc., Räumlichkeit."*
    ///
    /// ⛔ THE OLD DEFAULT WAS 0.82 AND ITS REASONING IS RETRACTED, not merely overridden. It
    /// read: *"full spectral saturation reads 'neon rainbow / amateur'; a gentle pull toward a
    /// graded palette looks professional."* That was a taste judgement I do not get to hold
    /// against an explicit founder instruction — and it was ALSO arithmetically worse than it
    /// looked, which is the part worth recording: it was the third of THREE stacked
    /// desaturators. Net chroma was 0.92 (warm tint) × ~0.90 (warm lift) × 0.82 = **~0.68**,
    /// and no single line said so. B9 already un-stacked one of the three (0.80 → 0.92) and
    /// the field still read grey on device, because two were left.
    ///
    /// ⚠️ **THIS DEFAULT IS A FALLBACK, NOT THE ONE THAT RENDERS.** Every mounted surface
    /// passes `saturation:` explicitly from `@AppStorage(StudioDefaultKeys.visualSaturation)`,
    /// so this literal is overwritten at every call site and is reachable only by a caller
    /// that omits the argument — which today does not exist. It is kept equal to the shared
    /// default so the two can never disagree, and #578 moved it only for that reason: moving
    /// it ALONE (which is what this slice tried first) changes nothing a user can see.
    ///
    /// The value is a JUDGEMENT and stays free to retune — its guard pins relations and a
    /// floor, never 1.05 (#364). It lands on a two-decimal step so the user control can
    /// return to it exactly.
    var saturation: Float = 1.05
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
    /// visible-band edge the octave fold wraps red↔violet in ONE
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
    /// TOUCH RIPPLES (structural rebuild, founder 2026-07-09: "immer noch diese
    /// grafischen Fehler … strukturiere das Visual Touch Instrument von Anfang an
    /// neu"). The water feedback is now DRAWN IN THIS SHADER — one pipeline, one
    /// clock, one drawable — instead of CAShapeLayer/CAGradientLayer animations
    /// composited OVER the Metal layer (two compositors with independent timing =
    /// the whole artifact class: mismatched frames during any move/resize, layer
    /// pop-in/out, animation-clock edge cases). 6 slots; per slot: (x, y) in the
    /// touch surface's normalized space (x 0…1 left→right, y 0…1 BOTTOM→top —
    /// the shader's own uv orientation), p = life progress 0…1 (computed on the
    /// CPU each frame, shader stays stateless), a = amplitude (0 = slot empty),
    /// rgb = the played note's colour (same CIE fit as everything else).
    var rp0x: Float = 0; var rp0y: Float = 0; var rp0p: Float = 1; var rp0a: Float = 0
    var rp0r: Float = 0; var rp0g: Float = 0; var rp0b: Float = 0
    var rp1x: Float = 0; var rp1y: Float = 0; var rp1p: Float = 1; var rp1a: Float = 0
    var rp1r: Float = 0; var rp1g: Float = 0; var rp1b: Float = 0
    var rp2x: Float = 0; var rp2y: Float = 0; var rp2p: Float = 1; var rp2a: Float = 0
    var rp2r: Float = 0; var rp2g: Float = 0; var rp2b: Float = 0
    var rp3x: Float = 0; var rp3y: Float = 0; var rp3p: Float = 1; var rp3a: Float = 0
    var rp3r: Float = 0; var rp3g: Float = 0; var rp3b: Float = 0
    var rp4x: Float = 0; var rp4y: Float = 0; var rp4p: Float = 1; var rp4a: Float = 0
    var rp4r: Float = 0; var rp4g: Float = 0; var rp4b: Float = 0
    var rp5x: Float = 0; var rp5y: Float = 0; var rp5p: Float = 1; var rp5a: Float = 0
    var rp5r: Float = 0; var rp5g: Float = 0; var rp5b: Float = 0
}

/// The touch surface's water-drop events for the Metal renderer (structural rebuild
/// 2026-07-09): the play surface pushes a DROP per note/wake; the renderer reads the
/// live list once per frame and hands it to the shader as ripple slots. Pure
/// snapshot reads (no drain) — safe with any number of mounted renderer instances.
/// Same lock-safe leaf pattern as TouchVisualEnergy/TouchToneChannel; clock is
/// CFAbsoluteTimeGetCurrent (MUST match the draw loop's frame clock — see
/// TouchToneChannel's epoch note).
final class TouchRippleChannel: @unchecked Sendable {
    static let shared = TouchRippleChannel()

    struct Drop {
        var x: Float            // 0…1 left→right (touch surface normalized)
        var y: Float            // 0…1 BOTTOM→top (shader uv orientation)
        var amp: Float          // brightness of this drop's light
        var r: Float; var g: Float; var b: Float
        var birth: CFTimeInterval
        var duration: CFTimeInterval
    }

    private let lock = NSLock()
    private var drops: [Drop] = []
    /// Matches the shader's slot count.
    private static let maxDrops = 6
    /// Wake (slide-trail) drops are rate-capped: a fast slide spawns one every
    /// ~14 pt of travel (40–80/s) — unbounded, that recycled all 6 slots every
    /// ~0.1 s, each light popping in and being CUT out (the machine-gun flicker,
    /// artifact audit 2026-07-09 #2 — the flash law covers creation rate too).
    private static let minWakeInterval: CFTimeInterval = 0.05
    private var lastWakeAccepted: CFTimeInterval = 0

    func drop(x: Float, y: Float, amp: Float, r: Float, g: Float, b: Float,
              duration: CFTimeInterval, strong: Bool, at now: CFTimeInterval) {
        guard x.isFinite, y.isFinite, amp.isFinite, amp > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        drops.removeAll { now - $0.birth >= $0.duration }
        if !strong {
            // A trail light is decorative — never worth cutting a live light for,
            // and never faster than the rate cap.
            guard drops.count < Self.maxDrops,
                  now - lastWakeAccepted >= Self.minWakeInterval else { return }
            lastWakeAccepted = now
        } else if drops.count >= Self.maxDrops {
            // Full + a real note (7 overlapping strikes — rare): reuse the DIMMEST
            // light (amp × remaining life), the least-visible swap. NEVER
            // removeFirst() — that cut a possibly-bright ripple to black in one
            // frame (the "feuert rein" pop).
            if let victim = drops.indices.min(by: {
                remainingLight(drops[$0], now: now) < remainingLight(drops[$1], now: now)
            }) {
                drops.remove(at: victim)
            }
        }
        drops.append(Drop(x: min(max(x, 0), 1), y: min(max(y, 0), 1),
                          amp: min(amp, 1), r: r, g: g, b: b,
                          birth: now, duration: max(duration, 0.05)))
    }

    private func remainingLight(_ d: Drop, now: CFTimeInterval) -> Float {
        d.amp * Float(max(0, 1 - (now - d.birth) / d.duration))
    }

    /// All live drops (expired ones pruned). Pure value snapshot per frame.
    func active(now: CFTimeInterval) -> [Drop] {
        lock.lock()
        defer { lock.unlock() }
        drops.removeAll { now - $0.birth >= $0.duration }
        return drops
    }

    func reset() {
        lock.lock()
        drops.removeAll()
        lock.unlock()
    }
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
    /// saturation defaults to 1.05 (see BioUniforms for the retraction of the old 0.82 and
    /// the three-stacked-desaturator arithmetic behind it) — dialable either way by the VJ
    /// control. ⚠️ THIS IS THE SECOND OF TWO FALLBACK DEFAULTS and they must move together;
    /// a mismatch would make the look depend on which path constructed the uniforms. Neither
    /// is what renders: every mounted surface passes `saturation:` from
    /// `StudioDefaultKeys.visualSaturation`, and THAT is the number to change to change the
    /// picture (the mistake #578 made first, recorded at that declaration).
    var hueShift: Float = 0
    var saturation: Float = 1.05
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
        // B9b (founder "immer noch grau", 2026-07-13): the shader computes LINEAR
        // sRGB (CIE XYZ → linear, see wavelengthToRGB) and encodes NOTHING — with a
        // non-sRGB drawable those linear values were displayed as if already
        // gamma-encoded, crushing mid-tones (~0.5 → perceived 0.21) and turning every
        // saturated hue muddy grey. `_srgb` makes the GPU apply the linear→sRGB
        // encode on write, matching SpectralColor.displayRGB's pow(1/2.2) twin — the
        // visual and the donut/keyboard finally agree (anti-strobe law). Recording is
        // unaffected structurally: the blit copies raw (now correctly encoded) bytes
        // into the 32BGRA pixel buffer — sRGB/non-sRGB variants are copy-compatible.
        view.colorPixelFormat = .bgra8Unorm_srgb
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
        // STRUCTURAL RESIZE SAFETY (founder 2026-07-08: "Bei Vollbild immer noch
        // Bildfehler … eine andere Programmiertechnik"): the drawable is NEVER
        // re-allocated by layout. With autoResizeDrawable every bounds change —
        // fullscreen toggle, safe-area shift, rotation, any system animation —
        // re-created the Metal drawable mid-motion (the glitch frames). The
        // renderer now manages `drawableSize` itself in draw(in:): while the size
        // is moving, the last rendered image simply SCALES on the layer (smooth);
        // once the size has been stable for a couple of frames, ONE clean
        // re-allocation lands at the final resolution. Glitch-free by
        // construction for every resize path, not just our own buttons.
        view.autoResizeDrawable = false
        // COMPOSITING-BEAT FIX (founder 2026-07-09: "immer noch random strobe … an den
        // Punkt zurück, wo wir mehrere Fenstergrößen eingepflegt haben — da ist der Fehler
        // aufgetreten"). Exactly right: while the visual was FULLSCREEN-only the MTKView
        // owned the screen and its drawable presented in isolation. Since 56d3fed made it a
        // FLOATING, RESIZABLE sub-window, the MTKView is composited every frame with the rest
        // of the SwiftUI layer tree — and the DEFAULT asynchronous present (buffer.present +
        // commit) hands the drawable to the compositor on the GPU's clock, NOT in lockstep
        // with UIKit's CATransaction. The two cadences beat → a random strobe that a SCREEN
        // recording shows but the in-app MP4 (which taps the Metal TEXTURE, not the composited
        // display) never does — matching every symptom. `presentsWithTransaction = true` makes
        // us present the drawable SYNCHRONOUSLY inside the current transaction (see draw(in:):
        // commit → waitUntilScheduled → drawable.present()), so Metal content lands in the same
        // compositor pass as the surrounding UIKit layers. Safe fullscreen too (just adds sync).
        view.presentsWithTransaction = true
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
    /// Last `framebufferOnly` value written to the MTKView. Writing the property EVERY frame
    /// (even to the same value) reconfigures the drawable/CAMetalLayer and made the picture
    /// shimmer ("Visualfenster zittert") — worse at fullscreen resolution and on a style switch
    /// (the palette "Bild Fehler"). We only assign it when the desired state actually flips
    /// (record start / stop), so the steady state never touches the layer config.
    private var lastFramebufferOnly: Bool = true
    /// Settled-size drawable management (autoResizeDrawable = false): the size the
    /// layout is currently asking for, and how many consecutive frames it has held
    /// steady. Only a SETTLED size (≥2 stable frames, or the very first nonzero one)
    /// re-allocates the drawable — never a mid-animation frame.
    private var pendingDrawableSize: CGSize = .zero
    private var pendingStableFrames = 0
    private let startTime = CFAbsoluteTimeGetCurrent()
    private var lastFrameTime = CFAbsoluteTimeGetCurrent()
    /// Throttle for the ~5 s visual-health diag line (device-log triage: "die
    /// Visualisierung hat ihre Verbindung zum Sound verloren", 2026-07-12 —
    /// this one line in a pasted log pins whether bio/musical frames arrive and
    /// which quality tier is active). Main-thread, far off the render hot path.
    private var lastDiagLog: CFAbsoluteTime = 0
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

    /// The amplitude at which a published note starts counting as sounding — shared by the
    /// cloud-slot gate and by the colour tone's ADOPT threshold, so the picture does not hold a
    /// tone it refuses to give any colour. (It does not make the two fully consistent: the tone
    /// branch reads the bus at `maxAge: 1.5` and the cloud at `0.5`, so for a frame aged in
    /// between, the tone still holds while no slot fills. Unifying the windows is a separate
    /// question — this constant only removes the duplicated NUMBER.)
    private static let audibleAmplitude: Double = 0.02

    /// The amplitude at which an already-adopted colour tone is RELEASED — deliberately half
    /// the adopt threshold. A single threshold would let a take hovering around it flip
    /// adopt↔release every frame, and the colour retarget at the prism crossfade reads the
    /// UN-eased tone with only a ~0.165 s gate, so that alternation reaches ~3 Hz — above the
    /// house 2.5 Hz ceiling, and on a path `FlashGuard` does not cover (it guards `flashHz`
    /// only). Asymmetric hysteresis collapses the chatter band to zero width with no new state.
    private static let releaseAmplitude: Double = 0.01
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
    /// Whether the slot's note is a FINGER note (fast ease-in — a touch must answer
    /// NOW) or a generative-bed note (slower ease-in: the roll's 8 note-ons/s each
    /// blooming a half-frame cloud in ~90 ms read as rhythmic "shooting", artifact
    /// audit 2026-07-09 #3 — the bed should breathe in, only the fingers snap).
    private var cloudTouch = [Bool](repeating: false, count: 5)

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
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb   // must match the view (B9b)
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
        var soundingNotes: [(id: Int, hz: Double, amp: Float, touch: Bool)] = []
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
            // Settled-size drawable management (autoResizeDrawable = false, see
            // makeUIView): compute the size layout wants; only when it has held
            // steady for ≥2 frames (or is the FIRST real size at launch) does the
            // drawable re-allocate — a mid-animation frame only scales the last
            // image on the layer. This kills the fullscreen/resize glitch class
            // for EVERY resize path (our snap, safe-area shifts, rotation).
            let scale = view.window?.screen.scale ?? view.contentScaleFactor
            let want = CGSize(width: max(1, view.bounds.width * scale),
                              height: max(1, view.bounds.height * scale))
            let have = view.drawableSize
            if abs(want.width - have.width) > 0.5 || abs(want.height - have.height) > 0.5 {
                if abs(want.width - pendingDrawableSize.width) < 0.5,
                   abs(want.height - pendingDrawableSize.height) < 0.5 {
                    pendingStableFrames += 1
                } else {
                    pendingDrawableSize = want
                    pendingStableFrames = 0
                }
                if pendingStableFrames >= 2 || have.width <= 2 || have.height <= 2 {
                    view.drawableSize = want
                }
            } else {
                pendingStableFrames = 0
            }
            let ds = view.drawableSize
            if ds.height > 0 { uniforms.aspect = Float(ds.width / ds.height) }
            // Display frame rate is PINNED at 60 (makeUIView) and NEVER reassigned at
            // runtime. Changing MTKView.preferredFramesPerSecond reconfigures the
            // CADisplayLink — a visible display-cadence hitch that does NOT appear in a
            // recording (the recorder pulls rendered texture frames, not display
            // presents). That is exactly the founder's "Fullscreen flackert, aber in
            // der Aufnahme nicht" / "knistert hier und da" class. Thermal pressure is
            // handled by DETAIL scaling + reduce-motion below (both smooth and
            // frame-rate-independent) and the 15 fps rPPG camera cap — not by toggling
            // the display's frame rate. `recordFrame` feedback (further down) now drives
            // DETAIL, not FPS, so a device that can't hold 60 sheds detail smoothly.
            let q = governor?.settings
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
            } else if let frame = bus?.freshMusical(maxAge: 1.5),
                      let loudest = frame.notes.max(by: { $0.amplitude < $1.amplitude }),
                      loudest.amplitude > (colorToneHz == 0 ? Self.audibleAmplitude
                                                            : Self.releaseAmplitude) {
                // The amplitude floor is NOT cosmetic — without it the hysteresis LATCHES.
                // Device log 2466 (v10.79.350): `mfNotes=5 level=0.00 tone=432 ccw=0.00`
                // repeated unchanged for 25 s while the roll kept publishing. A frame whose
                // notes are all silent still satisfies `notes.max(by:)`, so this branch ran;
                // `currentAmp` was 0 and `loudest.amplitude > 0 * 1.3` is `0 > 0` = false, so
                // `colorToneHz` could never be replaced — and the release branch below, which
                // is the ONLY writer that clears it, cannot be reached while a fresh NON-EMPTY
                // frame exists (an empty one falls through `max(by:)`, so a genuine rest always
                // could heal it — a silent CHORD could not). The picture therefore held one
                // frozen tone and a dead colour indefinitely, with no way back short of closing
                // the visual. An all-silent frame now goes to the release branch instead.
                //
                // The threshold is ASYMMETRIC on purpose — adopt above `audibleAmplitude`, hold
                // until below half of it. See `releaseAmplitude`: a single threshold makes a
                // take that hovers on it flip every frame, and that alternation drives the
                // colour retarget faster than the 2.5 Hz house ceiling on a path FlashGuard
                // does not cover.
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
                    soundingNotes.append((id, hz, 1.0, true))
                }
            }
            let mf = bus?.freshMusical(maxAge: 0.5)
            musicLevel = Float(mf?.masterLevel ?? 0)
            // Visual-health diag (~every 5 s, main thread): one glanceable line per
            // log paste that answers "is the visual actually receiving sound/bio?" —
            // bus wired? musical frames arriving? which tone drives colour? governor
            // tier degrading (reduce-motion / detail) under thermal load?
            if nowGov - lastDiagLog > 5 {
                lastDiagLog = nowGov
                // BREADCRUMB, not os_log: the founder's pastable device log IS the
                // EchoelCrashLog stream — every earlier "bitte Log mit offenem
                // Visual" round failed because this line only went to os_log,
                // which that log never contains (solved 2026-07-12).
                // ccw = summed live cloud weights (colour reach), c0 = slot-0 eased RGB —
                // the COLOUR truth in every pastable log (B9b: "grau" is measurable now).
                // mfAmp = the LOUDEST published note. Added after log 2466, where
                // `mfNotes=5 level=0.00` could not distinguish two very different faults:
                // notes arriving with (near-)zero velocity from upstream, versus the level
                // arithmetic here being wrong while the notes are fine. One number splits it —
                // mfAmp ≈ 0 with notes present means the roll is publishing silence.
                //
                // mfNotes now reads AUDIBLE/ACTIVE (e.g. `0/5` = "nothing audible, five notes
                // active"). The roll filters inaudible notes before publishing, which is right
                // for every renderer but would have DELETED the fault signature above: the
                // 2472 case `mfNotes=5 mfAmp=0.000` would collapse to `mfNotes=0`, byte-
                // identical to a genuine rest. `inaudibleNoteCount` is carried purely so the
                // recurrence ("the mixer is baking everything to inaudible again") still reads
                // as a fault in a pasted log instead of as silence.
                let mfAmp = mf?.notes.map(\.amplitude).max() ?? 0
                let mfActive = mf.map { $0.notes.count + $0.inaudibleNoteCount } ?? -1
                EchoelCrashLog.breadcrumb(String(format:
                    "visual: bio=%d mfNotes=%d/%d mfAmp=%.3f level=%.2f tone=%.0f touch=%d redMot=%d detail=%.2f ccw=%.2f c0=%.2f/%.2f/%.2f",
                    bio != nil ? 1 : 0, mf?.notes.count ?? -1, mfActive, mfAmp, musicLevel,
                    musicTone ?? 0, playedNotes.count,
                    effectiveReduceMotion ? 1 : 0, detailScale,
                    cloudW.reduce(0, +), uniforms.cc0r, uniforms.cc0g, uniforms.cc0b))
            }
            if soundingNotes.count < 5, let mf {
                for n in mf.notes.sorted(by: { $0.amplitude > $1.amplitude }) {
                    guard soundingNotes.count < 5 else { break }
                    guard n.amplitude > Self.audibleAmplitude else { continue }
                    let id = Self.noteID(n.frequencyHz)
                    guard id != Int.min else { continue }
                    if !soundingNotes.contains(where: { $0.id == id }) {
                        soundingNotes.append((id, n.frequencyHz, Float(n.amplitude.squareRoot()), false))
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
                   // `coherenceForSound`: the `??` only covers a MISSING frame, so a
                   // present frame that has measured no coherence (HealthKit never
                   // does; the camera not until enough beats accrue) reached the
                   // shader as 0 — this mapping's extreme, the reddest and dimmest
                   // picture it can draw, shown precisely when nothing is known.
                   coherence: bio?.coherenceForSound ?? (idle ? idleCoh : 0.5),
                   // breathPhase is a WRAPPING 0→1 phase; the shader uses breath as
                   // a MAGNITUDE (spread/restGlow), so feeding it raw made the whole
                   // figure saw-collapse ~30 % at every cycle wrap (audit #4). Shape
                   // it into a smooth hump — the same fix the piano-roll view once
                   // applied to MPE press ("swell through the breath, not saw-reset at
                   // the wrap"). ⛔ That view was deleted by #475, so this is a NAMED
                   // precedent with no code to open; the reasoning stands on its own.
                   // The idle fallback is already a wrap-free sine; keep it raw.
                   breath: bio.map { sin(Float.pi * min(max($0.breathPhase, 0), 1)) }
                       ?? (idle ? idleBreath : 0.5),
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
                    cloudTouch[k] = soundingNotes[i].touch
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
                // Prefer a truly-INVISIBLE slot (snap colour+place, fade in) over
                // stealing a still-visible one: a stolen visible slot's colour +
                // position chase the new note, so a cloud visibly DARTED across
                // half the screen on every chord change (artifact audit 2026-07-09
                // #3). Now a visible fading cloud finishes fading in place; only
                // when all five are visibly lit does the quietest carry over.
                let invisible = free.filter { cloudW[$0] < 0.004 }
                guard let k = (invisible.isEmpty ? free : invisible)
                    .min(by: { cloudW[$0] < cloudW[$1] }) else { break }
                slotTaken[k] = true
                cloudID[k] = soundingNotes[i].id
                cloudHzSlot[k] = soundingNotes[i].hz
                targetW[k] = soundingNotes[i].amp
                cloudTouch[k] = soundingNotes[i].touch
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
                if !cloudSeeded {
                    // BIRTH SNAP (B9c, founder "immer noch grau" 2026-07-13): a fresh
                    // renderer is born on EVERY fullscreen open / donut-toggle remount
                    // (fullScreenCover builds lazily by design). Easing the weights up
                    // from 0 painted 1–2 s of GREY on every open — the founder checks
                    // the visual right after changing a look, so he kept landing in
                    // that window (device log: five first-frame ccw=0.00 diags in one
                    // 14 s stretch). Colour + place already SNAP on seed (slotSeeded);
                    // the weights now join them, so already-sounding notes are fully
                    // lit on frame 1. Not a flash-safety event: it is the view's first
                    // content, not an oscillation; real note-ons after birth keep the
                    // musical ease-in below.
                    cloudW[k] = targetW[k]
                } else {
                    let up = targetW[k] > cloudW[k]
                    // Ease-in split by source: a FINGER answers now (0.09); the
                    // generative bed breathes in (0.30) — its 16th-note retriggers at
                    // ~8/s otherwise bloom half-frame clouds in ~90 ms each, reading
                    // as rhythmic "shooting" synced to the roll (audit #3).
                    let inTau: Float = cloudTouch[k] ? 0.09 : 0.30
                    cloudW[k] = Self.ease(cloudW[k], targetW[k], tau: up ? inTau : 0.35, dt: dt)
                }
                if !slotTaken[k], cloudW[k] < 0.004 { cloudID[k] = Int.min }   // slot free again
                guard cloudHzSlot[k] > 0 else { continue }
                // Closed-circle tone colour (purple-line seam): a chord on E/F/G
                // used to sum to near-BLACK clouds — "chords not visualized"
                // (founder 2026-07-12). Twins the shader's toneColour seam.
                let c = SpectralColor.toneLinearRGB(forToneHz: cloudHzSlot[k])
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
            // TOUCH RIPPLES (see BioUniforms.rp*): snapshot the shared channel and
            // compute each drop's life progress HERE, so the shader stays stateless
            // and every mounted renderer instance shows the identical water. Empty
            // slots carry amp 0 (progress 1) → the shader skips them. Analytic
            // progress (no easing state) — a ripple can only ever fade out, so this
            // adds no strobe surface.
            var rp = [(x: Float, y: Float, p: Float, a: Float, rgb: SIMD3<Float>)](
                repeating: (0, 0, 1, 0, .zero), count: 6)
            let liveDrops = TouchRippleChannel.shared.active(now: nowT)
            for (i, dr) in liveDrops.prefix(6).enumerated() {
                let prog = Float(min(max((nowT - dr.birth) / dr.duration, 0), 1))
                rp[i] = (dr.x, dr.y, prog, dr.amp, SIMD3<Float>(dr.r, dr.g, dr.b))
            }
            (uniforms.rp0x, uniforms.rp0y, uniforms.rp0p, uniforms.rp0a) = (rp[0].x, rp[0].y, rp[0].p, rp[0].a)
            (uniforms.rp0r, uniforms.rp0g, uniforms.rp0b) = (rp[0].rgb.x, rp[0].rgb.y, rp[0].rgb.z)
            (uniforms.rp1x, uniforms.rp1y, uniforms.rp1p, uniforms.rp1a) = (rp[1].x, rp[1].y, rp[1].p, rp[1].a)
            (uniforms.rp1r, uniforms.rp1g, uniforms.rp1b) = (rp[1].rgb.x, rp[1].rgb.y, rp[1].rgb.z)
            (uniforms.rp2x, uniforms.rp2y, uniforms.rp2p, uniforms.rp2a) = (rp[2].x, rp[2].y, rp[2].p, rp[2].a)
            (uniforms.rp2r, uniforms.rp2g, uniforms.rp2b) = (rp[2].rgb.x, rp[2].rgb.y, rp[2].rgb.z)
            (uniforms.rp3x, uniforms.rp3y, uniforms.rp3p, uniforms.rp3a) = (rp[3].x, rp[3].y, rp[3].p, rp[3].a)
            (uniforms.rp3r, uniforms.rp3g, uniforms.rp3b) = (rp[3].rgb.x, rp[3].rgb.y, rp[3].rgb.z)
            (uniforms.rp4x, uniforms.rp4y, uniforms.rp4p, uniforms.rp4a) = (rp[4].x, rp[4].y, rp[4].p, rp[4].a)
            (uniforms.rp4r, uniforms.rp4g, uniforms.rp4b) = (rp[4].rgb.x, rp[4].rgb.y, rp[4].rgb.z)
            (uniforms.rp5x, uniforms.rp5y, uniforms.rp5p, uniforms.rp5a) = (rp[5].x, rp[5].y, rp[5].p, rp[5].a)
            (uniforms.rp5r, uniforms.rp5g, uniforms.rp5b) = (rp[5].rgb.x, rp[5].rgb.y, rp[5].rgb.z)
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
        // pulseHz × motion, hard-capped at `FlashGuard.maxPulseRateHz` (2.5 Hz, stricter
        // than WCAG's 3 Hz because Aurora's budget lands exactly on 3.00 Hz at this rate).
        // THIS is the authoritative cap — the phase every look's field is driven by.
        // Reduce Motion → freeze (no advance).
        //
        // The `Float(...)` cast is load-bearing for the BUILD, not for the maths: the ceiling
        // used to be a bare `2.5` here, inferred as `Float` from the uniforms, so reading the
        // hoisted `Double` broke `min` with "no exact matches" — and ONLY on the Xcode gate,
        // since this file is behind `canImport(MetalKit) && canImport(UIKit) &&
        // canImport(SwiftUI)`. Argument order is safe here for a reason worth stating: with
        // the cap SECOND, `min` would return the uncapped product if the cap were ever NaN —
        // it can't be (a finite literal), and both operands are sanitized above, but swapping
        // in a computed cap without reversing the order would silently uncap the renderer.
        if !reduceMotion {
            let flashHz = min(uniforms.pulseHz * uniforms.motion, Float(FlashGuard.maxPulseRateHz))
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

        // SYNCHRONOUS present in the current CATransaction (presentsWithTransaction = true,
        // set in makeUIView). Commit the GPU work, block until it is SCHEDULED (fast — not
        // until completed), then present the drawable directly. This puts the Metal frame in
        // lockstep with the UIKit compositor and removes the floating-window strobe. NOTE:
        // must be `drawable.present()` here, NOT `buffer.present(drawable)` — the latter is
        // the asynchronous path and would defeat the transaction sync.
        buffer.commit()
        buffer.waitUntilScheduled()
        drawable.present()
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
                      float cc4x; float cc4y; float cc4w;
                      float rp0x; float rp0y; float rp0p; float rp0a; float rp0r; float rp0g; float rp0b;
                      float rp1x; float rp1y; float rp1p; float rp1a; float rp1r; float rp1g; float rp1b;
                      float rp2x; float rp2y; float rp2p; float rp2a; float rp2r; float rp2g; float rp2b;
                      float rp3x; float rp3y; float rp3p; float rp3a; float rp3r; float rp3g; float rp3b;
                      float rp4x; float rp4y; float rp4p; float rp4a; float rp4r; float rp4g; float rp4b;
                      float rp5x; float rp5y; float rp5p; float rp5a; float rp5r; float rp5g; float rp5b; };

    // TOUCH RIPPLES — the water feedback drawn IN the field's own pipeline
    // (structural rebuild 2026-07-09; the old CAShapeLayer sandwich over the Metal
    // layer was the remaining artifact source). Each live drop renders as a soft
    // colour CLOUD that blooms + dissolves (ink in water) with ONE thin wavefront
    // ring as its leading edge — the same water identity as before, now perfectly
    // frame-locked to the field under it. `uvA` is the aspect-correct coordinate
    // (x scaled by aspect → circles stay circular on a tall phone). Flash-safe by
    // construction: every ripple's light EASES IN over the first ~10 % of its life
    // (a drop at prog 0 used to appear at FULL brightness in one frame — the
    // "feuert rein" pop, artifact audit 2026-07-09 #1), then decays monotonically;
    // the sum is clamped before compositing.
    float3 rippleLight(float2 uvA, constant Uniforms& u) {
        float rx[6] = { u.rp0x, u.rp1x, u.rp2x, u.rp3x, u.rp4x, u.rp5x };
        float ry[6] = { u.rp0y, u.rp1y, u.rp2y, u.rp3y, u.rp4y, u.rp5y };
        float rp[6] = { u.rp0p, u.rp1p, u.rp2p, u.rp3p, u.rp4p, u.rp5p };
        float ra[6] = { u.rp0a, u.rp1a, u.rp2a, u.rp3a, u.rp4a, u.rp5a };
        float3 rc[6];
        rc[0] = float3(u.rp0r, u.rp0g, u.rp0b);
        rc[1] = float3(u.rp1r, u.rp1g, u.rp1b);
        rc[2] = float3(u.rp2r, u.rp2g, u.rp2b);
        rc[3] = float3(u.rp3r, u.rp3g, u.rp3b);
        rc[4] = float3(u.rp4r, u.rp4g, u.rp4b);
        rc[5] = float3(u.rp5r, u.rp5g, u.rp5b);
        float3 acc = float3(0.0);
        for (int k = 0; k < 6; k++) {
            float amp = ra[k];
            float prog = rp[k];
            if (amp < 0.003 || prog >= 0.999) continue;   // empty / finished slot
            float life = 1.0 - prog;                       // monotonic fade-out
            float att = smoothstep(0.0, 0.10, prog);       // eased onset (~65-100 ms)
            float ease = 1.0 - life * life;                // easeOut expansion
            float2 ctr = float2(rx[k] * u.aspect, ry[k]);
            float rd = distance(uvA, ctr);
            // Cloud body: a gaussian glow that grows while it dissolves.
            float sigma = mix(0.045, 0.16, ease);
            float cloud = exp(-rd * rd / (2.0 * sigma * sigma)) * life * 0.34;
            // Leading wavefront: one thin ring travelling outward.
            float R = mix(0.02, 0.34, ease);
            float t = (rd - R) / 0.011;
            float band = exp(-t * t) * life * life * 0.42;
            acc += rc[k] * (amp * att * (cloud + band));
        }
        return min(acc, float3(0.85));
    }

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
        // Desaturate toward neutral by the most-negative channel, not a per-channel
        // clip-to-zero — clipping first always normalizes the single remaining
        // positive channel by itself (==1), collapsing the deep-red/violet bands to
        // one flat colour. Twin fix of SpectralColor.wavelengthToLinearRGB (Swift).
        float w = min(0.0, min(c.r, min(c.g, c.b)));
        c -= w;
        float m = max(c.r, max(c.g, c.b));
        if (m > 1.0) c /= m;
        return clamp(c, 0.0, 1.0);
    }

    // DELETED 2026-07-29: `toneWavelengthNm` — the NAIVE octave fold (nearest octave to a
    // ~555 nm green centre, then clamp). It had zero callers since the prism look moved to
    // `toneColour` below, and it is a DIFFERENT fold from the one every surface agrees on
    // (ceil-fold anchored at 780 nm): same tone, different colour. A second fold sitting in
    // the file with nothing calling it is not neutral — it is the one a future edit reaches
    // for by name, which is exactly how the prism kept the black-F seam for two weeks after
    // the clouds were fixed. `toneColour` is the only fold; deleting this makes that literal.

    // Tone → colour on the CLOSED spectral circle. The visible band is barely one
    // octave, so the naive fold has a SEAM where CIE response → 0 (at A4=440 the
    // pitch class F rendered BLACK, G/E dim — founder 2026-07-12). Colorimetry's
    // own closure is the CIE PURPLE LINE (red end ↔ violet end, real perceived
    // colours); inside 640…420 nm the pure spectral colour holds. Hand-written twin
    // of SpectralColor.toneLinearRGB — every surface must agree (anti-strobe law).
    //
    // The two SEAM BOUNDARIES are interpolated from SpectralColor rather than typed
    // here, because typed here they had DRIFTED: tViolet read 0.89306425 against a
    // true log2(780/420) = 0.89308480, while this comment claimed to be an "EXACT
    // twin". Sub-perceptual (the violet edge sat at 420.006 nm) and unreachable by
    // any test — the two properties that let it survive. The rest of the function is
    // still a hand-written twin; only the derived constants are now single-source.
    float3 toneColour(float toneHz) {
        float f = max(toneHz, 1.0);
        float p = log2(2.99792458e17 / 780.0 / f);  // octaves up to the 780 nm anchor
        float t = ceil(p) - p;                       // position in the closed circle [0,1)
        if (t >= 1.0) t -= 1.0;
        float tRed = \(SpectralColor.tRedMetalLiteral);      // log2(780/640) — last strong red
        float tViolet = \(SpectralColor.tVioletMetalLiteral); // log2(780/420) — last strong violet
        if (t >= tRed && t <= tViolet) {
            return wavelengthToRGB(780.0 / exp2(t));
        }
        float seam = tRed + 1.0 - tViolet;
        float s = (t < tRed) ? (tRed - t) / seam : (tRed + 1.0 - t) / seam;
        float3 red = wavelengthToRGB(640.0);
        float3 violet = wavelengthToRGB(420.0);
        float3 c = mix(red, violet, s);
        // Lift the mixed peak to the interpolated anchor peak — factor 1 at
        // both boundaries (continuous with the spectral span), full presence
        // mid-purple. Twin of SpectralColor.toneLinearRGB.
        float m = max(c.r, max(c.g, c.b));
        float target = mix(max(red.r, max(red.g, red.b)),
                           max(violet.r, max(violet.g, violet.b)), s);
        if (m > 1e-6) c *= target / m;
        return clamp(c, 0.0, 1.0);
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
        // Through `toneColour` — the CLOSED-circle twin of SpectralColor.toneLinearRGB.
        // It sat directly above this function, written and with ZERO callers, while this
        // line used a naive nearest-octave fold instead (`toneWavelengthNm`, deleted
        // 2026-07-29 once this was its last trace): the one with the
        // deep-red/violet SEAM, where a tone landing at the edge hits near-zero CIE response
        // and renders BLACK (at A4=440 that is the pitch class F — the founder's 2026-07-12
        // "da fehlt jetzt gerade das F komplett als Farbe"). The clouds were fixed; the
        // prism look kept the seam. Now every surface really does agree.
        float hzA    = max(toneA, 1.0) * exp2(octave);
        float hzB    = max(toneB, 1.0) * exp2(octave);
        float3 c     = mix(toneColour(hzA), toneColour(hzB), fade);
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
    // ⚠ FLASH LAW (fixed 2026-07-25). The visible field here is amplitude SQUARED, and
    // squaring a BIPOLAR signal DOUBLES its temporal rate (sin²x = ½(1 − cos 2x)). The
    // CPU caps the phase rate at 2.5 Hz, so feeding the FULL phase into the squared
    // field flashed at 2 × 2.5 = 5 Hz. It was over the 3 Hz WCAG limit for any
    // flashHz > 1.5 — i.e. from about 90 bpm at the default Motion 1.0, or 60 bpm at
    // Motion 1.5 — so ordinary use, not a corner case. Introduced 2026-07-12 when the
    // field became `interf * interf` (before that it was the non-squared 0.5+0.5·sin
    // form described above), fixed 2026-07-25.
    // Clamping the input is necessary but NOT sufficient once a FOLD follows it. So the
    // damping factor below halves the phase: 0.5 × 2 = 1.0, i.e. the squared field lands
    // back exactly on the cap. It is INTERPOLATED from `FlashGuard.ringsPhaseDamping`
    // rather than written here, so the Swift constant and this shader cannot drift apart.
    // Bonus the halving buys: post-fix the centre field is (1 − cos φ)/2, the SAME form
    // as the heartbeat bloom below, so the rings now peak ONCE per beat in phase with it
    // instead of twice per beat interleaved with it.
    float fieldRings(float d, float density, float phase, float coh) {
        float p = phase * \(FlashGuard.ringsPhaseDampingLiteral);   // squared field ⇒ damped phase
        float w1 = sin(d * density - p);
        float detune = mix(1.6, 1.02, coh);                 // high coh → near-unison, ordered
        float w2 = sin(d * density * detune - p * 0.5);
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
        // never snaps the pattern (kills the "ruckeln"). The phase is integrated at
        // ≤2.5 Hz (< WCAG 3 Hz) — but that clamp alone does NOT make a style safe. Only
        // a NON-MONOTONE operation on a phase-bearing quantity adds flashes, because only
        // a non-monotone map creates new extrema: squaring a bipolar signal (×2), `abs()`
        // of one (×2), or a PRODUCT of two phase-bearing factors (adds a sum sideband at
        // f₁+f₂). Monotone maps — `pow` on a non-negative field, `clamp`, `smoothstep`,
        // the S-curve near the end — change each flash's SHAPE, never the count, so do
        // not "fix" those. `fieldRings` broke the law by squaring (fixed 2026-07-25);
        // `fieldAurora` sits at exactly 3.0 Hz via an `abs()` fold times `breathe`.
        // Budgets: `FlashGuardTests.testEveryReachableLookObeysTheThreeHzLaw`.
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
        // clear expanding bloom.
        //
        // ⚠ FLASH LAW (2026-07-25, founder-approved trade-off). The old comment here said
        // "`phase` is integrated from a ≤2.5 Hz clock (< WCAG 3 Hz), so even the larger
        // swing can never strobe" — that reasoning is WRONG and it is the same mistake
        // that let `fieldRings` ship at 5 Hz. This bloom runs at the FULL phase rate while
        // the field runs at its own damped rate, and the two are ADDED into `energy`. At
        // radii where their peaks do not coincide a pixel sees TWO maxima per cycle — the
        // union of both flash counts, up to ~5/s — over a region that can cover the
        // screen. A clamped input does not protect an additive superposition.
        //
        // Fix chosen over slowing the heartbeat (which would read as a pulse every SECOND
        // beat): hold the bloom's own brightness swing BELOW the WCAG general-flash
        // threshold, so its transitions do not qualify and only the field's rate counts.
        // The RADIUS pulse below is deliberately left at full strength — the beat still
        // visibly expands, which is what reads as "dein Herzschlag treibt es an".
        // Swing comes from `FlashGuard.bloomBeatGainSwing` (interpolated, not copied) and
        // must satisfy swing × restGlowMax × (1−ambient) × sCurveGain < 0.10; see that
        // constant's doc for why 0.50 was NOT enough (the filmic S-curve lifts contrast
        // by 1.06 and has to be counted).
        float beat = 0.5 - 0.5 * cos(phase);            // 0…1 once per heartbeat
        float restGlow = 0.07 + 0.14 * u.breath;        // breath = resting swell
        float beatGain = 0.80 + \(FlashGuard.bloomBeatGainSwingLiteral) * beat;  // 0.80…1.22
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
        // B9 (founder 2026-07-13 "VISUALS GRAU"): the colour reach was too tight — a
        // 2–3-note cloud coloured only its tight centre, so the whole frame read grey.
        // Widen the cloud→colour gate (1.6 → 2.4) so a sounding note carries its colour
        // FURTHER across the frame. Silence is untouched (cloudGlow=0 → colourOn=0 →
        // still the warm-neutral field), so the 2026-07-08 "colour only where tones
        // sound" law holds — this only spreads colour where notes ACTUALLY sound.
        float presence = clamp((u.cc0w + u.cc1w + u.cc2w + u.cc3w + u.cc4w) * 1.8, 0.0, 1.0);
        float colourOn = mix(clamp(cloudGlow * 2.4, 0.0, 1.0), presence, prismW);
        col = mix(float3(0.60, 0.56, 0.50), col, colourOn);
        // NATURAL WARM LIGHT (founder): pure spectral colours look "neon"; nature's light
        // — a prism/rainbow in warm daylight — is warmer and a touch less saturated. Pull
        // gently toward a warm white point (~3500 K) and ease the saturation, keeping the
        // warmth in the desaturated part so it never goes cold/grey. Still bunt; the user
        // Saturation control can push it back to vivid. Hue order/variety is preserved.
        {
            float l = dot(col, float3(0.2126, 0.7152, 0.0722));
            float3 warm = float3(1.0, 0.92, 0.80);          // warm daylight white point
            // B9 un-stack: this block was a SECOND desaturator (0.80) stacked on top of
            // the user `saturation` grade (0.82) → net ~0.66 chroma = the "grau". Raise
            // to 0.92 so it mainly warm-TINTS (via the +0.10 lift below), leaving the
            // user Saturation as the single intentional grade. ⛔ B9's closing words were
            // "Still graded, not neon" and #578 retracts the GRADE half: the user default is
            // 1.05, a lift, so this block is no longer grading anything down. The "not neon"
            // half stands and is carried by the warm POINT, not by any of these strengths.
            // #578: B9 un-stacked the FIRST of three desaturators and the field still read
            // grey, because two remained. 0.92 → 0.97 and the warm lift 0.10 → 0.05 remove
            // most of what was left; with the user grade at 1.05 the net chroma goes
            // ~0.68 → ~0.97. The warm POINT is untouched — the founder asked for more colour,
            // not for cold colour, and the "warm daylight, not neon" hue character is what
            // the tint direction carries, not its strength.
            col = mix(float3(l) * warm, col, 0.97);         // warm TINT (0.80 → .92 B9 → .97 #578)
            col = mix(col, warm, 0.05);                     // slight overall warm lift
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
        // ── GLITTER + TEXTURE (#578, founder "Bunter, mehr Textur, Glitzer etc.") ────────
        //
        // ⚠️ FLASH-SAFE BY CONSTRUCTION, and the construction IS the safety argument — not a
        // rate clamp bolted on afterwards. Every speck carries its OWN phase and its OWN
        // frequency, both drawn from its own position hash, so the specks are mutually
        // uncorrelated and the FRAME's mean luminance does not modulate at all. WCAG's 3 Hz
        // limit is about coherent area flashing; uncorrelated point twinkle at ~0.5–0.9 Hz
        // per speck has no frame-level frequency to measure. A single global on/off — the
        // obvious way to write this — would be the unsafe design at ANY rate, and is exactly
        // what the per-speck phase avoids.
        //
        // ⚠️ AND IT DEGRADES CORRECTLY FOR FREE: `uniforms.time` is set to 0 under reduce
        // motion (see the draw loop), so `tw` collapses to each speck's static phase and the
        // glitter becomes a still, sparse specular field. Nothing extra to remember.
        //
        // Gated on `energy`: glitter sits ON the light, never on the dark. Sparkle on black
        // is dirt on the lens; sparkle on a lit field is water and mineral.
        float2 gcell = floor(in.uv * 420.0);
        float gAlive = step(0.985, echoelHash(gcell));          // ~1.5 % of cells ever spark
        float gSeed  = echoelHash(gcell + 17.0);
        float tw = 0.5 + 0.5 * sin(u.time * (3.4 + gSeed * 2.2) + gSeed * 6.2831853);
        float spark = gAlive * pow(tw, 6.0) * energy;           // pow → a sharp twinkle
        outCol += spark * mix(float3(1.0), col + 0.30, 0.6) * 0.55;
        // TEXTURE: two octaves of STATIC grain, modulated by the moving `energy`. Static on
        // purpose — a hash re-seeded by time is full-frame noise resampled every frame, and
        // while zero-mean noise is not a "flash", the honest version of the argument above is
        // easier to keep true if nothing here has temporal content at all. The texture reads
        // as alive anyway, because what modulates it is the field.
        float grain = (echoelHash(in.uv * 900.0) - 0.5) * 0.7
                    + (echoelHash(in.uv * 233.0) - 0.5) * 0.3;
        outCol += grain * 0.045 * energy;
        // ⛔ THIS CLAMP IS NOT TIDINESS — WITHOUT IT #578 WOULD HAVE REVIVED THE 2026-07-09
        // ARTIFACT the comment four lines below records. The ripple is a SCREEN blend,
        // `outCol += ripple * (1 - outCol)`, and that identity only holds while `outCol ≤ 1`.
        // Above 1 the factor goes NEGATIVE and the ripple starts SUBTRACTING — a touch would
        // punch dark holes in exactly the brightest, most glittered places. The filmic
        // S-curve above used to leave `outCol` clamped, so the screen blend inherited the
        // guarantee for free; the two additive lines this slice inserted between them broke
        // it silently. An additive term inserted before a screen blend must restore the
        // bound it consumed.
        outCol = clamp(outCol, 0.0, 1.0);
        // Touch-ripple light over the graded field (played water = light ON the
        // water, frame-locked to it — no second compositor). SCREEN blend, not raw
        // add: over an already-bright field a raw add clipped to pure white patches
        // (artifact audit 2026-07-09 #1); screen can approach but never clip white.
        outCol += rippleLight(uv, u) * (float3(1.0) - outCol);
        outCol += (echoelHash(in.uv * 1000.0) - 0.5) / 255.0;   // anti-banding dither
        return float4(clamp(outCol, 0.0, 1.0), 1.0);
    }
    """
}
#endif
