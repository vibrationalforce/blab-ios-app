import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// Bio → musical-direction orchestration. An on-device model (when present)
// *suggests* a musical configuration from a coarse body-state description; the
// engine *applies* it. The model only ever sees adjectives derived locally —
// never raw biometrics, RR intervals, identifiers or audio. On iOS 18 / when the
// on-device model is absent, callers use the deterministic `BioDirectionFallback`
// (no LLM, no network) so the feature still does something.

/// A coarse, non-identifying description of the body state — adjectives only.
/// This is the ONLY thing ever handed to the language model.
///
/// Every field is OPTIONAL, and `nil` means **not measured** — never a value.
/// This is not defensive style, it is the whole point: each field is derived from
/// a signal whose "unavailable" encoding is 0, and the earlier non-optional form
/// mapped that 0 straight onto the *low* end of each scale. A HealthKit session
/// (which never yields coherence) was described as "restless"; a body with no
/// respiratory rate (HealthKit only has one if the user tracks sleep) was described
/// as "slow breathing". `BioExplanation` then narrated both back to the user in
/// plain English as observations. A wrong number is a rendering defect; a wrong
/// adjective about someone's body, stated as fact, is not — so the unmeasured case
/// has to be representable, and every consumer has to omit rather than guess.
public struct BioStateSummary: Sendable, Equatable {
    public let arousal: String?      // "low" | "medium" | "high"
    public let steadiness: String?   // "steady and coherent" | "moderately steady" | "restless"
    public let breath: String?       // "slow" | "relaxed" | "fast"

    public init(from f: BioSampleFrame) {
        // `> 0` is the established "measured" gate for all three: heart rate is only
        // non-zero on a confident lock (see PolySynthVoice's entrainment quality gate),
        // and coherence/breathRate default to 0 for sources that never provide them.
        let hr = f.heartRateBPM
        arousal = hr > 0 ? (hr < 65 ? "low" : (hr < 95 ? "medium" : "high")) : nil
        let c = f.coherence
        steadiness = c > 0 ? (c > 0.6 ? "steady and coherent" : (c > 0.3 ? "moderately steady" : "restless")) : nil
        let br = f.breathRate
        breath = f.hasMeasuredBreath ? (br < 8 ? "slow" : (br < 16 ? "relaxed" : "fast")) : nil
    }

    /// The text-only prompt fragment handed to the model. Unmeasured fields are
    /// OMITTED, never defaulted — handing the model "restless" for a body it has no
    /// coherence for would launder a fabrication into a musical decision.
    public var prompt: String {
        var parts: [String] = []
        if let arousal { parts.append("\(arousal) arousal") }
        if let steadiness { parts.append(steadiness) }
        if let breath { parts.append("breathing \(breath)") }
        guard !parts.isEmpty else { return "Body state: not measured yet." }
        return "Body state: \(parts.joined(separator: ", "))."
    }
}

/// Plain-English, on-device explanation of how the live body is shaping the music
/// right now — simple but precise technical language. Deterministic, no LLM, so it
/// works on iOS 18+ (not gated to the on-device model). Surfaced to the user as
/// "EchoelAI" narration of the bio→sound process.
public enum BioExplanation {
    public static func text(for f: BioSampleFrame, tempo: Double) -> String {
        let s = BioStateSummary(from: f)
        let bpm = Int(tempo.rounded())

        // Each clause is built ONLY from a measured field. An unmeasured one drops the
        // clause entirely rather than narrating a default — this text is presented as
        // EchoelAI telling the user what their body is doing, so a filled-in adjective
        // reads as an observation.
        var clauses: [String] = []

        if let arousal = s.arousal {
            let hr = Int(f.heartRateBPM.rounded())
            let pace = arousal == "low" ? "calm" : (arousal == "high" ? "driving" : "flowing")
            clauses.append("heart rate \(hr) BPM sets a \(pace) \(bpm) BPM tempo")
        } else {
            clauses.append("tempo holds at \(bpm) BPM until a pulse is measured")
        }

        switch s.steadiness {
        case "steady and coherent":
            clauses.append("high coherence opens the filter for a brighter, fuller tone")
        case "moderately steady":
            clauses.append("moderate coherence holds a balanced tone")
        case "restless":
            clauses.append("an unsteady signal keeps the filter lower for a darker, softer tone")
        default:
            break   // no coherence measured — say nothing about steadiness
        }

        // The SPACE half follows arousal, so it is stated only when arousal was measured
        // too — but a measured breath still gets named on its own rather than dropped.
        if let breath = s.breath {
            if let arousal = s.arousal {
                let space = arousal == "low" ? "a wide hall reverb" : "a tighter room space"
                clauses.append("\(breath) breathing places it in \(space)")
            } else {
                clauses.append("\(breath) breathing shapes the swell")
            }
        }

        // The tail describes the ENGINE, so it is safe to always append — except for the
        // phrase "from your live signal", which is a claim about the body and directly
        // contradicts the "no pulse measured" opening when nothing was read.
        let measuredAnything = s.arousal != nil || s.steadiness != nil || s.breath != nil
        let source = measuredAnything ? " from your live signal" : ""
        return "EchoelAI — " + clauses.joined(separator: "; ")
            + ". Each phrase re-seeds the chords, opening pitch and dynamics\(source)"
            + " and morphs in at the bar line, so it never repeats and never cuts."
    }
}

/// The model's (or fallback's) suggestion — plain, Sendable, engine-facing.
public struct MusicDirectionResult: Sendable, Equatable {
    public let genre: String
    public let mood: String
    public let space: String   // "dry" | "room" | "hall"

    public init(genre: String, mood: String, space: String) {
        self.genre = genre
        self.mood = mood
        self.space = space
    }
}

/// Deterministic, on-device, no-LLM mapping. Always available (iOS 18+), pure,
/// and unit-testable — the privacy-safe baseline and the fallback when the
/// on-device model is absent.
public enum BioDirectionFallback {
    public static func direction(for frame: BioSampleFrame) -> MusicDirectionResult {
        let s = BioStateSummary(from: frame)
        // Unmeasured fields fall through to the same branch a MEDIUM body takes — the
        // instrument must still pick something. Genre lands on the middle choice
        // (vaporwave) and space on "room"; mood is binary, so nil arousal yields
        // "lively", which is NOT a middle and is a real behaviour change from the old
        // code (nil used to read as "low" ⇒ deep ambient / calm / hall). Deliberate:
        // the guarantee here is narrower than "neutral" — it is only that an UNMEASURED
        // signal cannot select an EXTREME. "restless" is the sole path to "tense", and
        // it is now unreachable without a real coherence reading.
        let genre: String
        switch s.arousal {
        case "low":  genre = "deep ambient"
        case "high": genre = "psytrance"
        default:     genre = "vaporwave"       // includes nil = not measured
        }
        let mood = s.steadiness == "restless"
            ? "tense"
            : (s.arousal == "low" ? "calm" : "lively")
        let space = s.arousal == "low" ? "hall" : "room"
        return MusicDirectionResult(genre: genre, mood: mood, space: space)
    }
}

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable
struct MusicDirection {
    @Guide(description: "One genre from: vaporwave, deep ambient, dub techno, classical, jazz, synthwave, doom, psytrance, trap")
    var genre: String
    @Guide(description: "One mood from: calm, dark, romantic, tense, weird, lively")
    var mood: String
    @Guide(description: "Reverb space, one of: dry, room, hall")
    var space: String
}

/// On-device bio→music director. `@MainActor` control-plane only — it never runs
/// on the audio thread; it produces a snapshot the engine applies.
@available(iOS 26, *)
@MainActor
@Observable
public final class BioMusicDirector {

    public private(set) var lastSuggestion: MusicDirectionResult?

    public init() {}

    /// Ask the on-device model for a musical direction. Returns `nil` (caller
    /// should use `BioDirectionFallback`) when the on-device model is unavailable
    /// or the request fails — never a cloud call.
    public func suggest(for frame: BioSampleFrame) async -> MusicDirectionResult? {
        guard OnDeviceModelGate.isOnDeviceLLMAvailable else { return nil }
        let summary = BioStateSummary(from: frame)
        // Nothing measured ⇒ don't ask. The prompt would degrade honestly to "Body state:
        // not measured yet.", but the model would still return a genre/mood/space and the
        // engine would apply it AS a bio-derived direction. Falling through to
        // `BioDirectionFallback` is at least honestly deterministic.
        guard summary.arousal != nil || summary.steadiness != nil || summary.breath != nil else {
            return nil
        }
        let session = LanguageModelSession(
            instructions: "You arrange a bio-reactive musical instrument. Given a body state, pick a genre, mood and reverb space that fit. Reply only with the structured fields. Never give health or medical advice.")
        do {
            let response = try await session.respond(
                to: "\(summary.prompt) Choose a genre, mood and space.",
                generating: MusicDirection.self)
            let d = response.content
            let result = MusicDirectionResult(genre: d.genre, mood: d.mood, space: d.space)
            lastSuggestion = result
            return result
        } catch {
            return nil
        }
    }
}
#endif
