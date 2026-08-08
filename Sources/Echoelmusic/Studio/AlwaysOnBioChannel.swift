//
//  AlwaysOnBioChannel.swift
//  Echoelmusic — Studio
//
//  #498. The four body channels that shape the instrument's OWN timbre while a session
//  runs, described once so a surface can SHOW them instead of only claiming them.
//
//  WHY THIS EXISTS. #496 stopped the "Live — body → sound" panel from DENYING the
//  always-on path and added a sentence naming the four. A sentence is not a readout: a
//  player still cannot see whether the body is reaching the engine right now, and #497 made
//  that gap sharper rather than smaller — since then an UNMEASURED channel deliberately
//  hands the engine its declared neutral (0.5), which is indistinguishable, from outside,
//  from a body that happens to sit mid-scale. The value alone cannot say which it is. So
//  every channel here carries BOTH the number the engine receives AND whether that number
//  is a measurement, and the two travel together by construction.
//
//  ⭐ THE `shapes` STRINGS ARE READ OFF `applyBioReactive`, NOT off CLAUDE.md. The
//  "DDSP Bio-Mappings" table there is a one-to-one list (coherence → harmonicity, HRV →
//  brightness, heart rate → vibrato, breath phase → envelope) and the engine is not
//  one-to-one — coherence alone moves FOUR things. Measured on the anchored (patch) path,
//  which is the shipping one:
//    · coherence     → filter cutoff · brightness · harmonicity · noise level
//    · hrvVariability→ brightness · reverb mix
//    · heartRate     → vibrato depth AND rate · brightness
//    · breathPhase   → amplitude (the breath swell)
//  The table is not wrong so much as PARTIAL, and a UI built from it would have shipped a
//  fresh under-statement onto the one surface #496 just corrected for over-statement.
//
//  ⚠️ ONE CONDITIONAL IS DELIBERATELY LEFT OUT OF THE COPY, and it is left out because
//  stating it would be MORE misleading, not less: on the `.harmonicSeries` map profile HRV
//  ALSO takes over harmonicity outright (`0.40 + hrv * 0.50`), overwriting the coherence
//  term above it. Naming that in a row would suggest the player can see which profile is
//  active — they cannot, it is a patch property. What the copy says stays true under every
//  profile; this note is where the exception lives.
//
//  ⚠️ AND THE LIMIT ON THE WHOLE TYPE: this describes what the engine RECEIVES. It does not
//  and cannot say the result is audible — the four values enter a chain of clamped
//  deviations around the patch, and #497 measured two of those deviations at 25 % and
//  0.92 dB. Loud enough to matter, small enough that a readout is not a substitute for a
//  hearing test.
//

import Foundation

/// One of the four body channels wired into `EchoelDDSP.applyBioReactive` from a live frame.
///
/// The other three inputs that function takes (`breathDepth`, `lfHfRatio`, `coherenceTrend`)
/// are pinned to neutral literals at BOTH construction sites and are deliberately absent —
/// see `TheAlwaysOnBioPathIsNamedTests` (#496), which keeps them absent.
public enum AlwaysOnBioChannel: String, CaseIterable, Identifiable, Sendable {
    case coherence
    case hrv
    case heartRate
    case breathPhase

    public var id: String { rawValue }

    /// Matches the wording of the always-on note in `BioModLiveView` — same four names, so
    /// the sentence and the rows cannot drift into calling one channel two things (#416).
    public var name: String {
        switch self {
        case .coherence:   return "Coherence"
        case .hrv:         return "HRV"
        case .heartRate:   return "Heart rate"
        case .breathPhase: return "Breath phase"
        }
    }

    /// What this channel moves in the engine, read off `applyBioReactive` (see the file
    /// header for the measurement and for the one profile-dependent exception).
    public var shapes: String {
        switch self {
        case .coherence:   return "filter · brightness · harmonicity · noise"
        case .hrv:         return "brightness · reverb"
        case .heartRate:   return "vibrato · brightness"
        case .breathPhase: return "level"
        }
    }

    /// The number the engine receives for this channel — the `…ForSound` accessor, never the
    /// raw field. Showing the raw field would put a readout and the engine one #497 apart.
    public func value(in frame: BioSampleFrame) -> Float {
        switch self {
        case .coherence:   return frame.coherenceForSound
        case .hrv:         return frame.hrvForSound
        case .heartRate:   return frame.heartRateForSound
        case .breathPhase: return frame.breathPhaseForSound
        }
    }

    /// Whether that number is a MEASUREMENT or the engine's declared neutral.
    ///
    /// Each case asks the frame's own named gate rather than restating a comparison — two of
    /// these four existed before #498 (`hasMeasuredHeartRate`, `hasMeasuredBreath`) and two
    /// were bare inline `> 0` tests inside the accessors; naming all four is what makes this
    /// switch a lookup instead of a third copy of the rule (#416).
    public func isMeasured(in frame: BioSampleFrame) -> Bool {
        switch self {
        case .coherence:   return frame.hasMeasuredCoherence
        case .hrv:         return frame.hasMeasuredHRV
        case .heartRate:   return frame.hasMeasuredHeartRate
        case .breathPhase: return frame.hasMeasuredBreath
        }
    }
}
