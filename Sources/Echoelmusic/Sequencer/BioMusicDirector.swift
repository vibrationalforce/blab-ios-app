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
public struct BioStateSummary: Sendable, Equatable {
    public let arousal: String      // "low" | "medium" | "high"
    public let steadiness: String   // "steady and coherent" | "moderately steady" | "restless"
    public let breath: String       // "slow" | "relaxed" | "fast"

    public init(from f: BioSampleFrame) {
        let hr = f.heartRateBPM
        arousal = hr < 65 ? "low" : (hr < 95 ? "medium" : "high")
        let c = f.coherence
        steadiness = c > 0.6 ? "steady and coherent" : (c > 0.3 ? "moderately steady" : "restless")
        let br = f.breathRate
        breath = br < 8 ? "slow" : (br < 16 ? "relaxed" : "fast")
    }

    /// The text-only prompt fragment handed to the model.
    public var prompt: String {
        "Body state: \(arousal) arousal, \(steadiness), breathing \(breath)."
    }
}

/// Plain-English, on-device explanation of how the live body is shaping the music
/// right now — simple but precise technical language. Deterministic, no LLM, so it
/// works on iOS 18+ (not gated to the on-device model). Surfaced to the user as
/// "EchoelAI" narration of the bio→sound process.
public enum BioExplanation {
    public static func text(for f: BioSampleFrame, tempo: Double) -> String {
        let s = BioStateSummary(from: f)
        let hr = Int(f.heartRateBPM.rounded())
        let bpm = Int(tempo.rounded())
        let pace = s.arousal == "low" ? "calm" : (s.arousal == "high" ? "driving" : "flowing")
        let tone: String
        switch s.steadiness {
        case "steady and coherent": tone = "high coherence opens the filter for a brighter, fuller tone"
        case "restless":            tone = "an unsteady signal keeps the filter lower for a darker, softer tone"
        default:                    tone = "moderate coherence holds a balanced tone"
        }
        let space = s.arousal == "low" ? "a wide hall reverb" : "a tighter room space"
        return "EchoelAI — heart rate \(hr) BPM sets a \(pace) \(bpm) BPM tempo; \(tone); \(s.breath) breathing places it in \(space). Each phrase re-seeds the chords, opening pitch and dynamics from your live signal and morphs in at the bar line, so it never repeats and never cuts."
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
        let genre: String
        switch s.arousal {
        case "low":  genre = "deep ambient"
        case "high": genre = "psytrance"
        default:     genre = "vaporwave"
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
