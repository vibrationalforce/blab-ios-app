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
//  Render safety: pure UIKit. Touch handling never touches SwiftUI state; the
//  water-ripple feedback is CAShapeLayer animation (GPU-composited, removed on
//  completion) — zero body invalidations at any touch rate. Sound goes through
//  PolySynthVoice.noteOn/noteOff, which are lock-free SPSC enqueues.
//
//  Water feel (founder: "es soll sich nach echtem Wasser anfühlen"): a touch is
//  a DROP — it sends out several concentric wavefronts, each starting a beat
//  after the last, so the ripple spreads outward the way water does rather than
//  as one flat ring. Tinted soft aqua-white so it reads as water/light on the
//  immersive visual (vaporwave-fit), not a hard UI stroke.
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

    func makeUIView(context: Context) -> TouchInstrumentUIView {
        let v = TouchInstrumentUIView()
        v.synth = synth
        v.key = key
        v.reduceMotion = reduceMotion
        v.morphDepth = morphDepth
        return v
    }

    func updateUIView(_ uiView: TouchInstrumentUIView, context: Context) {
        uiView.key = key
        uiView.synth = synth
        uiView.reduceMotion = reduceMotion
        uiView.morphDepth = morphDepth
    }
}

/// UIKit view doing the actual multi-touch → notes + water rings.
final class TouchInstrumentUIView: UIView {
    weak var synth: PolySynthVoice?
    var key = MusicalKey(root: 0, scale: .minor)
    var reduceMotion = false
    /// Position-morph amount for the vertical filter travel (0 = off).
    var morphDepth: Double = 0.6

    /// Sounding pitch per active touch. Capped so the play surface can never
    /// starve the generative loop of voices (PolySynthVoice steals oldest).
    private var held: [ObjectIdentifier: Int] = [:]
    private static let maxTouches = 4
    /// Last ring position per touch — a slide drops a new ring only every ~14 pt
    /// (a wake, not a smear).
    private var lastRing: [ObjectIdentifier: CGPoint] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
        isAccessibilityElement = true
        accessibilityLabel = "Play surface"
        accessibilityHint = "Touch and slide to play notes in the current key"
    }

    required init?(coder: NSCoder) { return nil }   // never instantiated from a nib

    // MARK: - Touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            guard held.count < Self.maxTouches else { break }
            let id = ObjectIdentifier(touch)
            let p = touch.location(in: self)
            let pitch = pitch(at: p)
            held[id] = pitch
            applyMorph(at: p)   // set the position timbre BEFORE the note speaks
            synth?.noteOn(pitch: pitch, velocity: velocity(of: touch))
            // Playing feeds the picture: each note pumps excitation into the Metal
            // visual (swells intensity/motion), so the fingers visibly shape the light.
            TouchVisualEnergy.shared.excite(0.35)
            spawnRing(at: p, strong: true)
            lastRing[id] = p
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard let old = held[id] else { continue }
            let p = touch.location(in: self)
            applyMorph(at: p)   // CONTINUOUS morph while the finger travels (not just at retriggers)
            let new = pitch(at: p)
            if TouchPitchMap.slideRetriggers(oldPitch: old, newPitch: new) {
                synth?.noteOff(pitch: old)
                synth?.noteOn(pitch: new, velocity: velocity(of: touch))
                held[id] = new
                TouchVisualEnergy.shared.excite(0.15)   // slides keep the picture alive
            }
            // Wake trail — a small ring roughly every 14 pt of travel.
            if let last = lastRing[id], hypot(p.x - last.x, p.y - last.y) > 14 {
                spawnRing(at: p, strong: false)
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
            if let pitch = held.removeValue(forKey: id) {
                synth?.noteOff(pitch: pitch)
            }
            lastRing.removeValue(forKey: id)
        }
    }

    /// Leaving the window (exit fullscreen mid-touch, dismissal) must not leave
    /// notes hanging.
    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil, !held.isEmpty {
            for pitch in held.values { synth?.noteOff(pitch: pitch) }
            held.removeAll()
            lastRing.removeAll()
            synth?.setCutoffScale(1)           // no lingering morph after dismissal
            TouchVisualEnergy.shared.reset()   // no lingering swell after dismissal
        }
    }

    // MARK: - Mapping

    private func pitch(at p: CGPoint) -> Int {
        let w = max(bounds.width, 1), h = max(bounds.height, 1)
        return TouchPitchMap.pitch(normX: p.x / w,
                                   normY: 1 - p.y / h,   // UIKit y is down; up = higher
                                   key: key)
    }

    private func velocity(of touch: UITouch) -> Float {
        let forceNorm = touch.maximumPossibleForce > 0
            ? Double(touch.force / touch.maximumPossibleForce) : 0
        return TouchPitchMap.velocity(forceNorm: forceNorm,
                                      radiusPoints: Double(touch.majorRadius))
    }

    /// Vertical position → continuous filter morph on the touch synth. An atomic
    /// param write consumed by the render block (same discipline as setTuning) —
    /// safe at any touch-event rate. With a DEDICATED touch synth this shapes only
    /// the played notes; the generative bed's timbre is untouched.
    private func applyMorph(at p: CGPoint) {
        guard morphDepth > 0.001 else { return }
        let h = max(bounds.height, 1)
        let normY = Double(1 - p.y / h)   // UIKit y is down; up = brighter
        synth?.setCutoffScale(TouchPitchMap.morphCutoffScale(normY: normY, depth: morphDepth))
    }

    // MARK: - Water ripples (CAShapeLayer — GPU, no SwiftUI invalidation)

    /// Soft aqua-white — reads as water/light on the immersive visual, not a
    /// hard UI stroke. (Vaporwave-fit; brand chrome stays clean elsewhere.)
    private static let rippleTint = UIColor(red: 0.72, green: 0.92, blue: 1.0, alpha: 1)

    /// A touch is a drop: emit several concentric wavefronts, each starting a
    /// beat after the last and reaching a little farther, so the ripple SPREADS
    /// outward like real water instead of one flat expanding ring.
    private func spawnRing(at p: CGPoint, strong: Bool) {
        guard !reduceMotion else { return }
        let wavefronts = strong ? 3 : 2
        let baseRadius: CGFloat = strong ? 58 : 34
        let baseAlpha: Float = strong ? 0.40 : 0.24
        let stagger: CFTimeInterval = 0.16
        let now = CACurrentMediaTime()
        for i in 0..<wavefronts {
            let t = Float(i) / Float(wavefronts)           // 0 = leading front
            spawnWavefront(at: p,
                           radius: baseRadius * CGFloat(1 + 0.35 * Double(i)),
                           alpha: baseAlpha * (1 - 0.55 * t), // outer fronts fainter
                           duration: (strong ? 1.0 : 0.7) + Double(i) * 0.12,
                           beginAt: now + Double(i) * stagger)
        }
    }

    private func spawnWavefront(at p: CGPoint, radius: CGFloat, alpha: Float,
                                duration: CFTimeInterval, beginAt: CFTimeInterval) {
        let ring = CAShapeLayer()
        ring.path = UIBezierPath(ovalIn: CGRect(x: -radius, y: -radius,
                                                width: radius * 2, height: radius * 2)).cgPath
        ring.position = p
        ring.fillColor = nil
        ring.strokeColor = Self.rippleTint.cgColor
        ring.lineWidth = 1.5
        ring.opacity = 0   // model value: invisible until its wavefront begins (no pre-begin flash)
        layer.addSublayer(ring)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.08
        scale.toValue = 1.0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = alpha
        fade.toValue = 0.0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.beginTime = beginAt
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards   // .forwards only — holds the END value (opacity 0) after; before beginTime the model value (0) shows, so no early flash
        // Remove the layer when the animation finishes — bounded sublayer count.
        // A CATransaction completion block runs on the main thread and (unlike
        // DispatchQueue.asyncAfter) is NOT a @Sendable closure, so capturing the
        // non-Sendable CAShapeLayer is clean under Swift 6 strict concurrency.
        CATransaction.begin()
        CATransaction.setCompletionBlock { ring.removeFromSuperlayer() }
        ring.add(group, forKey: "ripple")
        CATransaction.commit()
    }
}
#endif
