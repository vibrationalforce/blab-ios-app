//
//  TouchInstrumentView.swift
//  Echoelmusic — Studio
//
//  The immersive visual as a PLAYABLE multi-touch instrument (founder
//  2026-07-07: "Vielleicht lässt sich sogar das Visual in ein Multi-Touch
//  Instrument umwandeln. Mit mehreren Fingern wird je nach Position, Fläche
//  und Druck passend zum Sound gespielt … wie wenn man mit den Fingern durchs
//  Wasser geht").
//
//  Coherence by construction: every touch is quantized into the take's
//  MusicalKey (root + scale) and voiced by the SAME PolySynthVoice patch the
//  generative loop plays — so whatever the fingers do, it belongs to the sound.
//  X = scale degree across one octave · Y = octave band (low/mid/high) ·
//  contact AREA (majorRadius) and PRESSURE (force, where the hardware has it)
//  = velocity. Slides glide through the scale like trailing a hand in water.
//
//  Render safety: pure UIKit for INPUT only — touch handling never touches
//  SwiftUI state, and (structural rebuild 2026-07-09) the water-ripple feedback
//  is NO LONGER Core Animation at all: every drop goes into TouchRippleChannel
//  and is drawn by the Metal shader inside the immersive field itself. One
//  pipeline, one clock, one drawable — the artifact class of a second compositor
//  layered over the Metal drawable (mismatched frames on any move/resize, layer
//  pop, animation-clock edges) is gone by construction. Sound goes through
//  PolySynthVoice.noteOn/noteOff, which are lock-free SPSC enqueues.
//
//  Water feel (founder: "es soll sich nach echtem Wasser anfühlen"): a touch is
//  a DROP — a colour cloud that blooms and dissolves like ink in water, with one
//  thin wavefront ring as its leading edge, in the played note's physical colour.
//

import Foundation

/// Pure touch→music mapping — Foundation-only (no UIKit/CoreGraphics), so it
/// unit-tests without an Apple UI stack.
public enum TouchPitchMap {
    /// Octave bands bottom→top. Around the composer's pad register (padOctave
    /// ~3–4, lead ~5): low third of the surface = 3, middle = 4, top = 5.
    public static let octaveBands = [3, 4, 5]

    /// Map a normalized touch position (x 0…1 left→right, y 0…1 BOTTOM→TOP)
    /// into a scale-quantized MIDI pitch. X spans one octave of scale degrees;
    /// Y picks the octave band — always inside the key, never a wrong note.
    public static func pitch(normX: Double, normY: Double, key: MusicalKey) -> Int {
        let n = max(1, key.degreesPerOctave)
        let x = min(max(normX, 0), 0.999_999)
        let y = min(max(normY, 0), 1)
        let degree = Int(x * Double(n))
        let band = min(octaveBands.count - 1, Int(y * Double(octaveBands.count)))
        return key.degree(degree, octave: octaveBands[band])
    }

    /// Velocity from contact: whichever of pressure (0…1, 0 where the hardware
    /// has no force sensing) and contact radius (points; fingertip ≈ 8, flat
    /// finger ≈ 25+) says MORE intent wins. Floor keeps a feather touch audible.
    /// Range lifted 2026-07-07 (founder: "der Sound … könnte sich im mix ein bisschen
    /// mehr durchsetzen") so a played note sits slightly ON TOP of the generative loop
    /// instead of under it — feather ≈ 0.45, firm ≈ 0.95 (was 0.35 / 0.85).
    public static func velocity(forceNorm: Double, radiusPoints: Double) -> Float {
        let area = min(max((radiusPoints - 6) / 22, 0), 1)
        let intent = max(min(max(forceNorm, 0), 1), area)
        return Float(min(max(0.45 + 0.5 * intent, 0.3), 0.95))
    }

    /// A slide re-triggers only when it crosses into a new quantized pitch —
    /// jitter inside one degree must NOT machine-gun the note.
    public static func slideRetriggers(oldPitch: Int, newPitch: Int) -> Bool {
        oldPitch != newPitch
    }

    /// POSITION MORPH (founder 2026-07-08: "Der Sound … soll auch morphbar sein.
    /// Je nachdem wo man sich befindet ändert sich der Sound"): the vertical
    /// position continuously morphs the touch voice's filter — low on the surface
    /// = darker/rounder, high = brighter/opener — riding ON TOP of the octave
    /// bands, so a slide upward both climbs the register AND opens the timbre,
    /// like a hand rising through water toward light. `depth` 0 = off (scale 1);
    /// depth 1 = ±1 octave of cutoff (0.5×…2×). Exponential so it's perceptually
    /// even; pure → unit-tested.
    public static func morphCutoffScale(normY: Double, depth: Double) -> Float {
        let y = min(max(normY.isFinite ? normY : 0.5, 0), 1)
        let d = min(max(depth.isFinite ? depth : 0, 0), 1)
        return Float(pow(2.0, (y - 0.5) * 2.0 * d))
    }
}

#if canImport(SwiftUI)
import SwiftUI

/// The touch instrument's OWN synth (founder 2026-07-08: presets/character must be
/// individually settable, and the play surface must not glitch the generative bed).
/// A dedicated PolySynthVoice instance means (a) touch notes never STEAL voices from
/// the generative loop mid-sustain — the "komische glitches" — and (b) the touch
/// sound can carry its own patch + position morph without re-patching the whole take.
/// nil (default) = fall back to the shared take voice (pre-wiring behaviour).
/// SwiftUI-only guard (no UIKit): EchoelmusicApp injects this on EVERY platform,
/// even where the UIKit play surface below doesn't compile (macOS CI).
private struct TouchSynthKey: EnvironmentKey {
    // Computed (not a stored `static let`): a stored non-Sendable static is a
    // Swift 6 strict-concurrency error; a computed nil default has no shared state.
    static var defaultValue: PolySynthVoice? { nil }
}

extension EnvironmentValues {
    var touchSynth: PolySynthVoice? {
        get { self[TouchSynthKey.self] }
        set { self[TouchSynthKey.self] = newValue }
    }
}

/// The dedicated LEAD voice (separate from the main `synth`/polyVoice), injected so the
/// Studio can reach it for per-track FX — the generated `.lead` notes play through it, so a
/// "Melodic" insert must cover it too. Same computed-default guard as TouchSynthKey.
private struct LeadSynthKey: EnvironmentKey {
    static var defaultValue: PolySynthVoice? { nil }
}

extension EnvironmentValues {
    var leadSynth: PolySynthVoice? {
        get { self[LeadSynthKey.self] }
        set { self[LeadSynthKey.self] = newValue }
    }
}
#endif

#if canImport(UIKit) && canImport(SwiftUI)
import UIKit

/// Transparent multi-touch layer mounted over the fullscreen immersive visual.
struct TouchInstrumentView: UIViewRepresentable {
    let key: MusicalKey
    let synth: PolySynthVoice
    var reduceMotion: Bool = false
    /// Position-morph amount (0 = off … 1 = ±1 octave of filter travel).
    var morphDepth: Double = 0.6
    /// Fretboard grid (founder 2026-07-08: "eine Art Griffbrett einblenden …
    /// Gitter mit Feldern in den passenden Farben"): show which note lives where.
    var showGrid: Bool = false
    /// Slide-expression depths + glide (founder 2026-07-08: "hin und her sliden
    /// verändert den Sound … Glide bzw. Portamento kann man auch einstellen").
    var slideVibrato: Double = 0.35
    var slideChorus: Double = 0.30
    var glide: Double = 0

    func makeUIView(context: Context) -> TouchInstrumentUIView {
        let v = TouchInstrumentUIView()
        v.synth = synth
        v.key = key
        v.reduceMotion = reduceMotion
        v.morphDepth = morphDepth
        v.showGrid = showGrid
        v.slideVibrato = slideVibrato
        v.slideChorus = slideChorus
        v.glideSeconds = glide
        return v
    }

    func updateUIView(_ uiView: TouchInstrumentUIView, context: Context) {
        uiView.key = key
        uiView.synth = synth
        uiView.reduceMotion = reduceMotion
        uiView.morphDepth = morphDepth
        uiView.showGrid = showGrid
        uiView.slideVibrato = slideVibrato
        uiView.slideChorus = slideChorus
        uiView.glideSeconds = glide
    }
}

/// UIKit view doing the actual multi-touch → notes + water rings.
final class TouchInstrumentUIView: UIView {
    weak var synth: PolySynthVoice? {
        didSet {
            if synth !== oldValue {
                setNeedsGridRebuild()            // colours read its A4/cents
                applyExpressionSettings()        // depths/glide land on the new voice
            }
        }
    }
    var key = MusicalKey(root: 0, scale: .minor) {
        didSet { if key != oldValue { setNeedsGridRebuild() } }
    }
    var reduceMotion = false
    /// Position-morph amount for the vertical filter travel (0 = off).
    var morphDepth: Double = 0.6
    /// Slide-expression depths (founder 2026-07-08: "hin und her sliden verändert
    /// den Sound: Filter, ein bisschen Vibrato, Chorus"): how much a travelling
    /// finger opens vibrato / ensemble on the touch voice. User-set in the
    /// Play-surface-sound menu; forwarded to the synth on change.
    var slideVibrato: Double = 0.35 {
        didSet { if slideVibrato != oldValue { applyExpressionSettings() } }
    }
    var slideChorus: Double = 0.30 {
        didSet { if slideChorus != oldValue { applyExpressionSettings() } }
    }
    /// Glide/portamento time (s). ≥ ~5 ms switches slides from retrigger to a
    /// true singing glide (same envelope, frequency slides).
    var glideSeconds: Double = 0 {
        didSet { if glideSeconds != oldValue { applyExpressionSettings() } }
    }

    private func applyExpressionSettings() {
        synth?.slideVibratoDepth = Float(min(max(slideVibrato, 0), 1))
        synth?.slideChorusDepth = Float(min(max(slideChorus, 0), 1))
        synth?.setPortamento(seconds: Float(min(max(glideSeconds, 0), 0.6)))
    }
    /// The fretboard grid — one field per playable note (columns = scale degrees,
    /// rows = octave bands), each tinted with ITS note's physical colour, exactly
    /// the mapping `pitch(at:)` uses. Display-only CALayers under the ripples.
    var showGrid = false {
        didSet { if showGrid != oldValue { setNeedsGridRebuild() } }
    }

    /// Sounding pitch per active touch. Capped so the play surface can never
    /// starve the generative loop of voices (PolySynthVoice steals oldest).
    private var held: [ObjectIdentifier: Int] = [:]
    /// Last per-note filter scale actually SENT for each finger. UIKit delivers touch
    /// moves at 60–120 Hz per finger; forwarding every one would push ~600 events/s into
    /// the lock-free note queue, which the render drains ~94×/s. Sending only audible
    /// changes keeps the queue far from its bound (#155) without any perceptible loss —
    /// a 1% cutoff step is well under a just-noticeable difference.
    private var lastSentMorph: [ObjectIdentifier: Float] = [:]
    private static let maxTouches = 4
    /// Last ring position per touch — a slide drops a new ring only every ~14 pt
    /// (a wake, not a smear).
    private var lastRing: [ObjectIdentifier: CGPoint] = [:]
    /// Last touch position per finger for the slide-expression gesture (every
    /// move event, unlike lastRing's 14 pt quantum).
    private var lastExprPos: [ObjectIdentifier: CGPoint] = [:]
    /// Host layer for the fretboard grid — sits UNDER the ripple layers.
    private let gridLayer = CALayer()
    private var gridBuiltForSize: CGSize = .zero
    private var gridDirty = true
    /// Per-note haptic (Vibration is a core Echoel dimension): a light impact on
    /// every note-on, intensity following the played velocity — the finger FEELS
    /// the note speak, which also makes the instrument playable without hearing.
    private let hapticGenerator = UIImpactFeedbackGenerator(style: .light)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        // Water-ring layers must stay INSIDE the visual card: UIView does not clip
        // sublayers by default, so at the floating sizes rings near the edge were
        // drawn OVER the surrounding Studio UI (play-at-every-size made this visible).
        clipsToBounds = true
        isAccessibilityElement = true
        accessibilityLabel = "EchoelSynth play surface"
        accessibilityHint = "Touch and slide to play notes in the current key"
        // DIRECT INTERACTION — the accessibility standard for musical instruments
        // (GarageBand model): a VoiceOver user double-taps the surface once, then
        // touches play IMMEDIATELY (no element-by-element navigation between the
        // fingers and the music). Combined with the note grid + per-note haptics,
        // the instrument is playable without sight.
        accessibilityTraits = [.allowsDirectInteraction]
        layer.addSublayer(gridLayer)   // first sublayer → ripples always render above
        hapticGenerator.prepare()
    }

    required init?(coder: NSCoder) { return nil }   // never instantiated from a nib

    // MARK: - Fretboard grid

    private func setNeedsGridRebuild() {
        gridDirty = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if gridDirty || gridBuiltForSize != bounds.size { rebuildGrid() }
    }

    /// The playable rect: bounds inset to the safe area. Fullscreen, the raw
    /// bounds run under the Dynamic Island / home indicator / rounded corners —
    /// the outermost grid columns rendered there but were physically cut off
    /// (founder screenshot 2026-07-09: "Also das adaptiv bitte"). Grid AND touch
    /// mapping share this rect so what you see is exactly what plays; in the
    /// floating window the insets are zero and nothing changes.
    private var playRect: CGRect {
        let r = bounds.inset(by: safeAreaInsets)
        return (r.width > 40 && r.height > 40) ? r : bounds
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        setNeedsGridRebuild()
    }

    /// One field per playable note — columns = the key's scale degrees (X mapping),
    /// rows = the octave bands (Y mapping, bottom = low) — each filled + hairlined
    /// in ITS note's physical colour and labeled with the note name. Static
    /// display-only layers (rebuilt only on key/size/toggle change, never per
    /// frame or per touch), so the grid costs nothing while playing.
    private func rebuildGrid() {
        gridDirty = false
        gridBuiltForSize = bounds.size
        gridLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
        gridLayer.frame = bounds
        // VoiceOver knows the terrain even without the visual grid: key, layout,
        // and how the surface is organised (kept current on every key change).
        let rootName = ["C", "C sharp", "D", "D sharp", "E", "F", "F sharp",
                        "G", "G sharp", "A", "A sharp", "B"][((key.root % 12) + 12) % 12]
        accessibilityValue = "Root \(rootName), \(key.degreesPerOctave) notes per octave, three octave rows, low at the bottom"
        guard showGrid, bounds.width > 60, bounds.height > 60 else { return }

        let rect = playRect                      // adaptive: never under notch/corners
        let n = max(1, key.degreesPerOctave)
        let bands = TouchPitchMap.octaveBands
        let cellW = rect.width / CGFloat(n)
        let cellH = rect.height / CGFloat(bands.count)
        let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]
        let labelSize: CGFloat = min(12, max(9, cellH * 0.16))

        for d in 0..<n {
            for b in bands.indices {
                let pitch = key.degree(d, octave: bands[b])
                let tint = Self.noteTint(hz: frequency(of: pitch))
                let isRoot = d == 0
                // Band 0 is the LOW octave = BOTTOM row (UIKit y grows downward).
                let cellFrame = CGRect(x: rect.minX + CGFloat(d) * cellW,
                                       y: rect.maxY - CGFloat(b + 1) * cellH,
                                       width: cellW, height: cellH)
                    .insetBy(dx: 1.5, dy: 1.5)
                let cell = CALayer()
                cell.frame = cellFrame
                // AUTHENTIC READ: the fill deepens toward the LOW octave (bottom
                // row darkest — low notes carry more visual weight, like thick
                // strings) and the ROOT column is anchored with a stronger border,
                // the way every fretboard marks its tonal home. Fills stay subtle
                // so the living visual underneath remains the star.
                let octaveWeight = 0.14 - 0.03 * CGFloat(b)          // 0.14 · 0.11 · 0.08
                cell.backgroundColor = tint.withAlphaComponent(octaveWeight).cgColor
                cell.borderColor = tint.withAlphaComponent(isRoot ? 0.70 : 0.30).cgColor
                cell.borderWidth = isRoot ? 1.5 : 1
                cell.cornerRadius = 6
                gridLayer.addSublayer(cell)

                // Label: near-white for WCAG-solid contrast on the dark field (the
                // pure tint was unreadable for dim colours); the note's colour
                // stays on the field + border, so nothing is lost.
                let label = CATextLayer()
                label.string = names[((pitch % 12) + 12) % 12] + "\(pitch / 12 - 1)"
                label.fontSize = labelSize
                label.foregroundColor = UIColor.white.withAlphaComponent(isRoot ? 0.9 : 0.62).cgColor
                label.alignmentMode = .left
                label.contentsScale = window?.screen.scale ?? 3
                label.frame = CGRect(x: cellFrame.minX + 6,
                                     y: cellFrame.maxY - labelSize - 6,
                                     width: cellFrame.width - 8, height: labelSize + 3)
                gridLayer.addSublayer(label)
            }
        }
    }

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard held.count < Self.maxTouches else { break }
            let id = ObjectIdentifier(touch)
            let p = touch.location(in: self)
            let pitch = pitch(at: p)
            held[id] = pitch
            lastSentMorph[id] = morphScale(at: p)   // the note-on already carried this value
            let vel = velocity(of: touch)
            // This finger's OWN position travels with its note (MPE-style), instead of
            // being written to the instrument-wide scale where the next finger overwrote it.
            synth?.noteOn(pitch: pitch, velocity: vel, cutoffScale: morphScale(at: p))
            hapticGenerator.impactOccurred(intensity: CGFloat(0.4 + 0.6 * Double(vel)))
            hapticGenerator.prepare()   // re-warm the Taptic engine so the NEXT note (tap or
                                        // slide-retrigger) fires with minimal latency — a play
                                        // surface triggers continuously, so it must never idle-sleep.
            // Playing feeds the picture: each note pumps excitation into the Metal
            // visual (swells intensity/motion), so the fingers visibly shape the light.
            TouchVisualEnergy.shared.excite(0.35)
            // The played tone becomes the picture's COLOUR (physical octave
            // transposition into visible light — performer priority in the renderer;
            // HELD, so a chord paints all its colours until the fingers lift).
            // CFAbsoluteTime — MUST match the draw loop's `nowGov` clock (CACurrentMediaTime
            // is a DIFFERENT epoch; mixing them would read every note as stale).
            TouchToneChannel.shared.noteOn(pitch: pitch, hz: frequency(of: pitch),
                                           at: CFAbsoluteTimeGetCurrent())
            spawnRing(at: p, strong: true, pitch: pitch, velocity: vel)
            lastRing[id] = p
            lastExprPos[id] = p
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard let old = held[id] else { continue }
            let p = touch.location(in: self)
            // CONTINUOUS morph while the finger travels — addressed to THIS finger's note.
            if let sounding = held[id] {
                let scale = morphScale(at: p)
                if abs(scale - (lastSentMorph[id] ?? 1)) > 0.01 {
                    lastSentMorph[id] = scale
                    synth?.setNoteCutoffScale(pitch: sounding, scale: scale)
                }
            }
            // Slide-expression gesture (founder 2026-07-08: "hin und her sliden
            // verändert den Sound"): finger travel pumps vibrato/ensemble energy
            // into the touch voice; it decays (~0.45 s) when the finger rests and
            // clears when the fingers lift. Atomic param writes — touch-rate-safe.
            if let lp = lastExprPos[id] {
                let travel = Double(hypot(p.x - lp.x, p.y - lp.y))
                if travel > 0.5 {
                    synth?.pushSlideExpression(Float(min(0.35, travel / 320.0)))
                }
            }
            lastExprPos[id] = p
            let new = pitch(at: p)
            if TouchPitchMap.slideRetriggers(oldPitch: old, newPitch: new) {
                let vel = velocity(of: touch)
                if glideSeconds >= 0.005 {
                    // GLIDE (portamento on): the held voice keeps its envelope and
                    // SLIDES to the new pitch — no retrigger, a singing legato.
                    synth?.slide(from: old, to: new, velocity: vel, cutoffScale: morphScale(at: p))
                } else {
                    synth?.noteOff(pitch: old)
                    synth?.noteOn(pitch: new, velocity: vel, cutoffScale: morphScale(at: p))
                }
                // Slides tick more softly than fresh strikes — a fret-crossing feel.
                hapticGenerator.impactOccurred(intensity: CGFloat(0.25 + 0.35 * Double(vel)))
                hapticGenerator.prepare()   // keep the Taptic engine warm through a slide's rapid ticks
                held[id] = new
                TouchVisualEnergy.shared.excite(0.15)   // slides keep the picture alive
                let now = CFAbsoluteTimeGetCurrent()
                TouchToneChannel.shared.noteOff(pitch: old, at: now)
                TouchToneChannel.shared.noteOn(pitch: new, hz: frequency(of: new), at: now)
            }
            // Wake trail — a small ring roughly every 14 pt of travel, in the colour
            // of the note the finger is sounding right now.
            if let last = lastRing[id], hypot(p.x - last.x, p.y - last.y) > 14 {
                spawnRing(at: p, strong: false, pitch: held[id] ?? old, velocity: velocity(of: touch))
                lastRing[id] = p
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        release(touches)
    }

    private func release(_ touches: Set<UITouch>) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            lastSentMorph.removeValue(forKey: id)
            if let pitch = held.removeValue(forKey: id) {
                synth?.noteOff(pitch: pitch)
                // Colour follows the fingers: lifting releases this note's cloud;
                // the last lift starts the ~1.2 s afterglow back to the bed.
                TouchToneChannel.shared.noteOff(pitch: pitch, at: CFAbsoluteTimeGetCurrent())
            }
            lastRing.removeValue(forKey: id)
            lastExprPos.removeValue(forKey: id)
        }
        // All fingers lifted → the slide expression settles immediately (no
        // lingering vibrato/ensemble on the release tails).
        if held.isEmpty { synth?.clearSlideExpression() }
    }

    /// Leaving the window (exit fullscreen mid-touch, dismissal) must not leave
    /// notes hanging.
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil, !held.isEmpty {
            for pitch in held.values { synth?.noteOff(pitch: pitch) }
            held.removeAll()
            lastSentMorph.removeAll()
            lastRing.removeAll()
            lastExprPos.removeAll()
            synth?.setCutoffScale(1)           // no lingering morph after dismissal
            synth?.clearSlideExpression()      // no lingering vibrato/ensemble either
            TouchVisualEnergy.shared.reset()   // no lingering swell after dismissal
            TouchToneChannel.shared.reset()    // colour hands back to the bed
            TouchRippleChannel.shared.reset()  // water settles instantly too
        }
    }

    // MARK: - Mapping

    private func pitch(at p: CGPoint) -> Int {
        // Same rect as the drawn grid — a finger on a visible field always plays
        // THAT field; touches in the safe-area margin clamp to the edge notes.
        let rect = playRect
        let w = max(rect.width, 1), h = max(rect.height, 1)
        return TouchPitchMap.pitch(normX: Double((p.x - rect.minX) / w),
                                   normY: Double(1 - (p.y - rect.minY) / h),   // UIKit y is down; up = higher
                                   key: key)
    }

    private func velocity(of touch: UITouch) -> Float {
        let forceNorm = touch.maximumPossibleForce > 0
            ? Double(touch.force / touch.maximumPossibleForce) : 0
        return TouchPitchMap.velocity(forceNorm: forceNorm,
                                      radiusPoints: Double(touch.majorRadius))
    }

    /// Vertical position → this touch's filter morph, RETURNED rather than applied
    /// (founder 2026-07-27: "mehr MPE vibes"). It used to call `setCutoffScale`, the
    /// instrument-wide scale — so with three fingers at three heights every note took the
    /// LAST finger's filter, which is the opposite of per-note expression and was invisible
    /// only because one finger is the common case. The value now rides with the note event
    /// and the engine holds it per voice; the global scale stays free for automation.
    ///
    /// `depth` 0 → 1 (neutral), so a disabled morph is bit-identical to no expression.
    private func morphScale(at p: CGPoint) -> Float {
        guard morphDepth > 0.001 else { return 1 }
        let rect = playRect
        let h = max(rect.height, 1)
        let normY = Double(min(max(1 - (p.y - rect.minY) / h, 0), 1))   // UIKit y is down; up = brighter
        return TouchPitchMap.morphCutoffScale(normY: normY, depth: morphDepth)
    }

    /// Sounding frequency of a MIDI pitch at the take's concert pitch (the touch
    /// synth is tuned by the Studio, so read its live A4 — not a hardcoded 440).
    /// Includes the active tone system's per-pitch-class cents (Pythagorean, just,
    /// maqām …) — same formula as the synth's noteOn — so the colour octave is
    /// transposed from the frequency the ear actually hears, in every tuning.
    private func frequency(of pitch: Int) -> Double {
        let a4 = Double(synth?.poly.a4Hz ?? 440)
        let cents = Double(synth?.uiTuningCents[((pitch % 12) + 12) % 12] ?? 0)
        return a4 * pow(2.0, (Double(pitch) - 69.0 + cents / 100.0) / 12.0)
    }

    // MARK: - Water ripples (drawn by the Metal renderer — structural rebuild 2026-07-09)

    /// The grid's field tint in the note's physical colour (CIE fit, sRGB-encoded
    /// for UIKit with a small white lift so deep red/violet still reads on the
    /// dark field). Used ONLY by the static fretboard grid now — the animated
    /// water feedback no longer lives in Core Animation at all.
    private static func noteTint(hz: Double) -> UIColor {
        // Shared display encoding (SpectralColor.displayComponents) — the SAME
        // helper the piano-roll raster uses, so both grids recolour identically
        // when the Kammerton moves (founder 2026-07-12).
        let c = SpectralColor.displayComponents(forToneHz: hz)
        return UIColor(red: CGFloat(c.r), green: CGFloat(c.g), blue: CGFloat(c.b), alpha: 1)
    }

    /// A touch is a drop of COLOURED LIGHT — pushed into `TouchRippleChannel` and
    /// DRAWN BY THE METAL SHADER inside the immersive field itself (founder
    /// 2026-07-09: "immer noch diese grafischen Fehler … strukturiere von Anfang
    /// an neu"). The old CAShapeLayer/CAGradientLayer animations lived in a SECOND
    /// compositor over the Metal drawable — two pipelines with independent clocks,
    /// which is exactly the artifact class the renderer-managed drawable work
    /// eliminated everywhere else. Now: one pipeline, one clock, one drawable —
    /// the water is frame-locked to the field by construction. This view keeps
    /// only input, sound, haptics and the static grid.
    private func spawnRing(at p: CGPoint, strong: Bool, pitch: Int, velocity: Float) {
        guard !reduceMotion else { return }
        let w = max(bounds.width, 1), h = max(bounds.height, 1)
        let rgb = SpectralColor.toneLinearRGB(forToneHz: frequency(of: pitch))
        // Equal-luminance light: normalize so every note's ripple glows visibly —
        // the shader's cloud luminance floor does not cover this additive light,
        // and raw deep-red/violet CMF output is otherwise near-invisible.
        let m = max(rgb.r, max(rgb.g, rgb.b))
        let s = m > 0.001 ? 0.9 / m : 1
        let vel = Double(velocity.clamped(to: 0...1))     // NaN-safe: NaN → dimmest ripple
        TouchRippleChannel.shared.drop(
            x: Float(p.x / w),
            y: Float(1 - p.y / h),                    // shader space: y up
            amp: Float((strong ? 0.5 : 0.28) * (0.6 + 0.4 * vel)),
            r: Float(rgb.r * s), g: Float(rgb.g * s), b: Float(rgb.b * s),
            duration: strong ? 1.0 : 0.65,
            // strong drives the channel's eviction policy: wake (trail) drops are
            // rate-capped and never evict a live light; only real strikes may
            // reuse the dimmest slot (artifact audit 2026-07-09 #2).
            strong: strong,
            // CFAbsoluteTime — MUST match the draw loop's frame clock (same epoch
            // rule as TouchToneChannel; CACurrentMediaTime would read as stale).
            at: CFAbsoluteTimeGetCurrent())
    }
}
#endif
