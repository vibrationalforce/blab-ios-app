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
//  water-ring feedback is CAShapeLayer animation (GPU-composited, removed on
//  completion) — zero body invalidations at any touch rate. Sound goes through
//  PolySynthVoice.noteOn/noteOff, which are lock-free SPSC enqueues.
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
    /// finger ≈ 25+) says MORE intent wins. Floor keeps a feather touch audible;
    /// cap leaves headroom over the generative loop.
    public static func velocity(forceNorm: Double, radiusPoints: Double) -> Float {
        let area = min(max((radiusPoints - 6) / 22, 0), 1)
        let intent = max(min(max(forceNorm, 0), 1), area)
        return Float(min(max(0.35 + 0.5 * intent, 0.2), 0.85))
    }

    /// A slide re-triggers only when it crosses into a new quantized pitch —
    /// jitter inside one degree must NOT machine-gun the note.
    public static func slideRetriggers(oldPitch: Int, newPitch: Int) -> Bool {
        oldPitch != newPitch
    }
}

#if canImport(UIKit) && canImport(SwiftUI)
import UIKit
import SwiftUI

/// Transparent multi-touch layer mounted over the fullscreen immersive visual.
struct TouchInstrumentView: UIViewRepresentable {
    let key: MusicalKey
    let synth: PolySynthVoice
    var reduceMotion: Bool = false

    func makeUIView(context: Context) -> TouchInstrumentUIView {
        let v = TouchInstrumentUIView()
        v.synth = synth
        v.key = key
        v.reduceMotion = reduceMotion
        return v
    }

    func updateUIView(_ uiView: TouchInstrumentUIView, context: Context) {
        uiView.key = key
        uiView.synth = synth
        uiView.reduceMotion = reduceMotion
    }
}

/// UIKit view doing the actual multi-touch → notes + water rings.
final class TouchInstrumentUIView: UIView {
    weak var synth: PolySynthVoice?
    var key = MusicalKey(root: 0, scale: .minor)
    var reduceMotion = false

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
            synth?.noteOn(pitch: pitch, velocity: velocity(of: touch))
            spawnRing(at: p, strong: true)
            lastRing[id] = p
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let id = ObjectIdentifier(touch)
            guard let old = held[id] else { continue }
            let p = touch.location(in: self)
            let new = pitch(at: p)
            if TouchPitchMap.slideRetriggers(oldPitch: old, newPitch: new) {
                synth?.noteOff(pitch: old)
                synth?.noteOn(pitch: new, velocity: velocity(of: touch))
                held[id] = new
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

    // MARK: - Water rings (CAShapeLayer — GPU, no SwiftUI invalidation)

    private func spawnRing(at p: CGPoint, strong: Bool) {
        guard !reduceMotion else { return }
        let radius: CGFloat = strong ? 60 : 34
        let ring = CAShapeLayer()
        ring.path = UIBezierPath(ovalIn: CGRect(x: -radius, y: -radius,
                                                width: radius * 2, height: radius * 2)).cgPath
        ring.position = p
        ring.fillColor = nil
        ring.strokeColor = UIColor.white.withAlphaComponent(strong ? 0.38 : 0.22).cgColor
        ring.lineWidth = 1.5
        layer.addSublayer(ring)

        let duration: CFTimeInterval = strong ? 0.9 : 0.6
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.12
        scale.toValue = 1.0
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
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
