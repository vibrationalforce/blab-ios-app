//
//  MusicalFrame.swift
//  Echoelmusic — Core
//
//  A snapshot of the live MUSICAL state, published on EngineBus alongside the bio
//  snapshot. This is the OUTPUT-STAGE backbone (DMMW as a product is retired,
//  2026-07-25 — docs/dev/PRODUCT_DEFINITION.md; its multidimensional half survives
//  as exactly this spine): visuals, light, spatial and (later) video subscribe to it
//  so every medium can be shaped BY musical parameters — the pitch/chord you play
//  becomes colour, the tempo/section drives motion and cues.
//
//  Pure value type, Core-only (no Studio/DSP dependency, so layering stays clean —
//  renderers map a MusicalFrame to their own domain, e.g. notes → SpectralColor).
//  Musical params are slow control-plane (UI-rate), so they travel as a @MainActor
//  snapshot like BioSampleFrame, not through the lock-free audio queue.
//

import Foundation

/// One sounding note: its frequency and how loud it is right now.
public struct MusicalNote: Sendable, Equatable {
    public let frequencyHz: Double
    public let amplitude: Double            // 0…1

    public init(frequencyHz: Double, amplitude: Double) {
        self.frequencyHz = frequencyHz.isFinite ? frequencyHz : 0
        self.amplitude = Swift.min(1, Swift.max(0, amplitude.isFinite ? amplitude : 0))
    }
}

public struct MusicalFrame: Sendable, Equatable {

    /// CFAbsoluteTimeGetCurrent clock — the SAME clock as BioSampleFrame.timestamp, so
    /// freshness checks compose across bio + musical sources.
    public let timestamp: Double
    /// The notes/chord sounding now (drives chord→colour, etc.).
    public let notes: [MusicalNote]
    /// Key root pitch-class 0…11, or -1 when unknown.
    public let rootPitchClass: Int
    /// Descriptive scale name (e.g. "dorian"); not interpreted here.
    public let scaleName: String
    /// Tempo in BPM (0 = unknown/stopped).
    public let tempoBPM: Double
    /// Arrangement section index, or -1 when none.
    public let sectionIndex: Int
    /// Phase within the current beat [0,1) — for a musical pulse on the visual.
    public let beatPhase: Double
    /// Per-track output levels [0,1] (e.g. drums, bass, lead, FX) for element reactivity.
    public let trackLevels: [Double]
    /// Broadband master output level [0,1].
    public let masterLevel: Double
    /// How many ACTIVE notes the publisher dropped as inaudible before building this
    /// frame. **DIAGNOSTIC ONLY — no renderer may react to it.**
    ///
    /// It exists because filtering silent notes at the publisher
    /// (`PianoRollModel.musicalFrame`) destroyed the signature an earlier cycle added
    /// precisely to FIND that class of fault: `mfNotes=5 mfAmp=0.000` meant "the roll is
    /// publishing silence", and now reads `mfNotes=0`, which is byte-identical to a
    /// genuine rest. Carrying the dropped count keeps the two apart in the founder's
    /// pastable device log instead of trading a diagnosable failure for a silent one.
    public let inaudibleNoteCount: Int

    public init(timestamp: Double = CFAbsoluteTimeGetCurrent(),
                notes: [MusicalNote] = [],
                rootPitchClass: Int = -1,
                scaleName: String = "",
                tempoBPM: Double = 0,
                sectionIndex: Int = -1,
                beatPhase: Double = 0,
                trackLevels: [Double] = [],
                masterLevel: Double = 0,
                inaudibleNoteCount: Int = 0) {
        self.timestamp = timestamp
        self.notes = notes
        self.rootPitchClass = rootPitchClass < 0 ? -1 : (rootPitchClass % 12)
        self.scaleName = scaleName
        self.tempoBPM = (tempoBPM.isFinite && tempoBPM > 0) ? tempoBPM : 0
        self.sectionIndex = sectionIndex < 0 ? -1 : sectionIndex
        self.beatPhase = Self.clamp01(beatPhase)
        self.trackLevels = trackLevels.map(Self.clamp01)
        self.masterLevel = Self.clamp01(masterLevel)
        self.inaudibleNoteCount = Swift.max(0, inaudibleNoteCount)
    }

    /// Nothing playing — the neutral default renderers fall back to.
    public static let silent = MusicalFrame()

    /// True when there is real audible musical content to react to.
    public var isSounding: Bool { !notes.isEmpty && masterLevel > 0 }

    private static func clamp01(_ x: Double) -> Double {
        guard x.isFinite else { return 0 }
        return Swift.min(1, Swift.max(0, x))
    }
}
