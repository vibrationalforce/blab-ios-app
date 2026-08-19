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

    /// ⭐ THE FRAME IS OPTIONAL, and nil is not a new case — it is the DEGENERATE form of
    /// the case this type already exists for. `EngineBus.usableBio()` returns nil when no
    /// source has published inside its freshness window, and "nothing was measured" is
    /// exactly what all-three-fields-nil already means. Spelling that as a separate
    /// `unmeasured` constant would have been a SECOND definition of the same fact (#416),
    /// and fabricating a zeroed `BioSampleFrame` to stand in for "no frame" would have
    /// been worse: this file's own doc explains at length why an unavailable signal
    /// encoded as 0 must never be read as a low value.
    ///
    /// Source-compatible: every existing call site passes a non-optional frame and is
    /// promoted, so `BioDirectionFallback.direction` and `BioMusicDirector.suggest` are
    /// bit-identical for every frame they could already receive.
    public init(from f: BioSampleFrame?) {
        guard let f else {
            // No frame at all ⇒ nothing measured, on every axis. Not "low", not
            // "restless", not "slow" — the whole point of the optionals above.
            arousal = nil
            steadiness = nil
            breath = nil
            return
        }
        // Heart rate and coherence gate on `> 0` — heart rate is non-zero only on a
        // confident lock (see PolySynthVoice's entrainment quality gate), and coherence
        // is 0 on any source that computes no beat-to-beat RR. Breath does NOT: it uses
        // the shared plausibility window, because `breathRate: 1` is as impossible as 0
        // and would otherwise pass a bare `> 0` test.
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
    /// ⭐ THE FRAME IS OPTIONAL, and this is the whole point of #506. Everything below —
    /// the "no pulse measured yet" branch, the `measuredAnything` suppression of the
    /// phrase " from your live signal," — was written for the case where the body was
    /// not read. `EngineBus.usableBio()` returning nil IS that case, and it is the
    /// COMMON one: device log 2494 (v10.79.377) recorded `body=0` in every single
    /// generate breadcrumb for ~475 s. Yet the one production caller was
    /// `if let frame { caption.text = … }`, so the no-body branch of a public, tested
    /// function could never be reached from the app — and, worse, a no-body take left
    /// the PREVIOUS take's narration standing, telling the user about a heart rate that
    /// had stopped arriving (the #503 defect one surface up).
    ///
    /// Nil is NOT a new sentence: `BioStateSummary(from: nil)` is all-fields-unmeasured,
    /// which every clause below already handles. Source-compatible — existing callers
    /// pass non-optional frames and are promoted.
    public static func text(for f: BioSampleFrame?, tempo: Double) -> String {
        let s = BioStateSummary(from: f)
        let bpm = Int(tempo.rounded())
        // Bound here rather than inside the arousal branch so that branch does not have
        // to unwrap `f` a second time. `s.arousal != nil` implies `f != nil` (the summary
        // sets all three to nil for a nil frame), so pairing them in one `if let` below
        // cannot change the outcome for any frame that could already arrive.
        let measuredHR = f.map { Int($0.heartRateBPM.rounded()) }

        // Each clause is built ONLY from a measured field. An unmeasured one drops the
        // clause entirely rather than narrating a default — this text is presented as
        // EchoelAI telling the user what their body is doing, so a filled-in adjective
        // reads as an observation.
        var clauses: [String] = []

        if let arousal = s.arousal, let hr = measuredHR {
            let pace = arousal == "low" ? "calm" : (arousal == "high" ? "driving" : "flowing")
            clauses.append("heart rate \(hr) BPM sets a \(pace) \(bpm) BPM tempo")
        } else {
            // DESCRIPTIVE, not predictive. "…until a pulse is measured" would be a promise
            // the tempo lock falsifies: with `lockBPM` on, the tempo resolves from
            // `lockedBPM` unconditionally and will never move to the pulse, so the user
            // would be waiting for something that cannot happen.
            clauses.append("tempo holds at \(bpm) BPM; no pulse measured yet")
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

        // Breath is credited ONLY for the swell, which is what it actually drives:
        // `EchoelDDSP.applyBioReactive` shapes `amplitude` by a raised cosine on
        // breathPhase. The old clause said breathing "places it in a wide hall reverb" /
        // "a tighter room space" — that was false twice over. Reverb mix is driven by
        // HRV (`reverbMix = bioBaseReverbMix + (hrvVariability - 0.5) * 0.12`), never by
        // breath; and the arousal→space mapping it was copying lives in
        // `BioDirectionFallback`, which nothing in the app consumes. A clause naming a
        // causal chain that does not exist is the same defect as a fabricated number.
        if let breath = s.breath {
            clauses.append("\(breath) breathing shapes the swell")
        }

        // The tail describes the ENGINE, so it is safe to always append — except for the
        // phrase "from your live signal", which is a claim about the body and directly
        // contradicts the "no pulse measured" opening when nothing was read.
        let measuredAnything = s.arousal != nil || s.steadiness != nil || s.breath != nil
        // ⭐ #634b — WHOSE signal, not just whether there was one. Every clause above is a
        // sentence about the listener's body ("heart rate 72 BPM sets a flowing tempo"),
        // and `BioSimulator` satisfies every `hasMeasured…` gate by construction, so under
        // the Simulation source this whole paragraph attributed a fabricated pulse to the
        // person reading it — including the literal possessive "your live signal".
        //
        // ⛔ `measuredAnything` COULD NOT CATCH THIS and its own doc block says why without
        // realising it: it asks whether a channel was READ, never where the reading came
        // from. The demo is read on every one of them.
        //
        // ⚠️ THIS IS THE HARDEST SURFACE OF THE #627 FAMILY TO MARK, and that is why the
        // marker is a PREFIX rather than a chip. The other seven surfaces are cells — a
        // dim tag beside a number qualifies it by adjacency. This is a running sentence
        // spoken by "EchoelAI", so a qualifier placed anywhere but the front corrects a
        // claim the reader has already accepted. Same reason the VoiceOver prefixes on
        // `AlwaysOnBioRow` and `HeaderMonitors` lead instead of trail.
        let synthetic = f?.source == .fallback
        let who = synthetic ? " from the demo signal," : " from your live signal,"
        // The connector rides INSIDE the conditional — leaving a bare " and" behind made
        // the no-body tail read "…opening pitch and dynamics and morphs in at the bar line".
        let source = measuredAnything ? who : ""
        return (synthetic ? "EchoelAI (demo signal) — " : "EchoelAI — ")
            + clauses.joined(separator: "; ")
            + ". Each phrase re-seeds the chords, opening pitch and dynamics\(source)"
            + " then morphs in at the bar line, so it never repeats and never cuts."
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
        // (vaporwave) and space on "room"; the mood ternary has no middle, so nil arousal
        // yields "lively". That IS a behaviour change: a fully unmeasured frame used to
        // read as arousal "low" AND coherence 0 as "restless", giving
        // deep ambient / TENSE / hall — the extreme this rule exists to block, which is
        // exactly what `testFallback_unmeasuredCoherenceCannotSelectTheTenseExtreme`
        // now pins. Deliberate:
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
