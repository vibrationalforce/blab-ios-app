// SoundPrompt.swift
// Echoel — "shape the sound by prompt", fully on-device (no network, no LLM,
// deterministic, private — fits meditation). A curated vocabulary of sound
// descriptors + intensity modifiers maps natural words onto SynthPatch
// parameters (character, filter, envelope, space). Pure value logic so the
// mapping is unit-tested.
//
// Example: "very warm lush pad" → darker/rounder timbre, more reverb, slow
// attack + long release. Unknown words are ignored (never throws, never garbles).
//
// ⭐ THE DOOR (#320): `EchoelStudioView.promptRow` — the "Describe it" row in
// `soundPanel`, behind the Sound chip. It renders `suggestions` as chips and calls
// `apply` on the live patch. `Tests/CISmoke/SoundPromptHasADoorTests.swift` pins
// that, because this file spent a month claiming a door it did not have:
//
// ⛔ The line that stood here said "the editor calls `apply` and offers
// `suggestions`", and `git grep SoundPrompt -- Sources` returned nothing but
// comment lines in `EchoelDDSP.swift`. The obvious suspect was `PatchEditorView`
// (doorless since the 2026-07-02 Tools-grid removal, deleted by #132 Slice 6) —
// but that is NOT what happened: its last revision contains zero occurrences of
// "SoundPrompt" or even "prompt" (`git show 8d31c21^:…/PatchEditorView.swift`).
// So this was not a door that rotted. **It was a caller that was never written**,
// described in the present tense on the day the file landed. That is the worse
// failure of the two: a rotted door leaves a grep trail, an imagined one leaves the
// capability reading as WIRED to every session that opens the file — which is
// exactly why nobody re-doored it. A header that names a caller must be checkable.

import Foundation

public enum SoundPrompt {

    /// Intensity a modifier word implies (multiplies a descriptor's strength).
    private static func intensity(_ word: String) -> Float? {
        switch word {
        case "very", "super", "extremely", "really", "so": return 1.6
        case "quite", "fairly", "pretty": return 1.25
        case "slightly", "subtle", "subtley", "touch", "bit", "little", "gentle", "gently": return 0.5
        default: return nil
        }
    }

    /// The descriptors the engine understands (for suggestion chips + matching).
    public static let vocabulary: [String] = [
        "warm", "bright", "dark", "soft", "hard", "punchy", "airy", "metallic",
        "glassy", "deep", "lush", "thin", "gritty", "clean", "plucky", "pad",
        "drone", "evolving", "wide", "vibrato", "hollow", "sharp", "mellow", "huge"
    ]

    /// Ready-made prompt suggestions shown to the user.
    public static let suggestions: [String] = [
        "warm lush pad", "bright glassy pluck", "deep dark drone",
        "soft airy mellow", "punchy metallic lead", "evolving wide pad",
        "gentle clean bell", "huge cinematic drone"
    ]

    /// Descriptor words recognized in `text` (order of appearance, de-duplicated).
    public static func recognizedTerms(in text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for word in tokens(text) where vocabulary.contains(word) && !seen.contains(word) {
            seen.insert(word)
            result.append(word)
        }
        return result
    }

    /// Apply a natural-language prompt to a patch, returning a new shaped patch.
    /// Deterministic; out-of-vocabulary words are ignored; all params clamped.
    public static func apply(_ text: String, to patch: SynthPatch) -> SynthPatch {
        var p = patch
        let words = tokens(text)
        var pendingIntensity: Float = 1.0

        for word in words {
            if let mod = intensity(word) {
                pendingIntensity = mod
                continue
            }
            if vocabulary.contains(word) {
                shape(word, &p, pendingIntensity)
            }
            // ⛔ "the next DESCRIPTOR" is what this said, and it is wrong in a way that
            // matters now that a UI line describes the behaviour: the reset happens on the
            // next TOKEN, known or not. So "very lovely warm" silently loses the ×1.6 on
            // `warm`, because the unknown `lovely` consumed it. Behaviour deliberately
            // unchanged (an unknown word must stay inert, and "swallow it" is one rule, not
            // two) — only the sentence is corrected.
            pendingIntensity = 1.0   // a modifier only affects the next TOKEN
        }
        clamp(&p)
        return p
    }

    // MARK: - Tokenizing

    private static func tokens(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
    }

    // MARK: - The vocabulary → parameter map

    private static func shape(_ word: String, _ p: inout SynthPatch, _ w: Float) {
        switch word {
        case "warm":
            p.brightness -= 0.20 * w; p.harmonicity += 0.10 * w
            p.filterCutoff *= (1 - 0.20 * w); p.reverbMix += 0.05 * w
        case "bright", "sharp":
            p.brightness += 0.25 * w; p.filterCutoff *= (1 + 0.45 * w)
            p.spectralShape = "bright"
        case "dark":
            p.brightness -= 0.25 * w; p.filterCutoff *= (1 - 0.40 * w)
            p.spectralShape = "dark"
        case "soft", "mellow":
            p.attack += 0.18 * w; p.brightness -= 0.10 * w; p.filterCutoff *= (1 - 0.10 * w)
        case "hard", "punchy", "plucky":
            p.attack = max(0.001, p.attack * (1 - 0.8 * w))
            p.decay = max(0.02, p.decay * (1 - 0.3 * w))
            p.sustain -= 0.15 * w; p.release = max(0.05, p.release * (1 - 0.4 * w))
        case "airy":
            p.noiseLevel += 0.05 * w; p.reverbMix += 0.15 * w; p.brightness += 0.08 * w
        case "metallic":
            p.harmonicity -= 0.20 * w; p.brightness += 0.15 * w; p.spectralShape = "bell"
        case "glassy":
            p.brightness += 0.20 * w; p.harmonicity += 0.10 * w; p.reverbMix += 0.10 * w
        case "deep":
            p.filterCutoff *= (1 - 0.30 * w); p.harmonicLevel += 0.10 * w
        case "lush", "huge":
            p.reverbMix += 0.20 * w; p.reverbDecay += 1.5 * w; p.vibratoDepth += 0.04 * w
        case "thin", "hollow":
            p.harmonicLevel -= 0.20 * w; p.brightness += 0.05 * w
        case "gritty":
            p.noiseLevel += 0.12 * w
        case "clean":
            p.noiseLevel = max(0, p.noiseLevel * (1 - 0.8 * w))
        case "pad":
            p.attack += 0.4 * w; p.release += 1.5 * w; p.sustain += 0.15 * w
        case "drone":
            p.sustain += 0.25 * w; p.release += 2.0 * w; p.attack += 0.3 * w
        case "evolving":
            p.filterLFORate += 0.25 * w; p.lfoToFilterDepth += 0.20 * w
        case "wide":
            p.reverbMix += 0.10 * w
        case "vibrato":
            p.vibratoRate += 4.0 * w; p.vibratoDepth += 0.10 * w
        default:
            break
        }
    }

    // MARK: - Clamp to valid ranges

    /// ⭐ THESE BOUNDS ARE NOT WRITTEN HERE ANY MORE — they are `SynthPatch.Bounds`, the same
    /// constants the Sound panel's rows are built from (#441). "Describe it" writes straight back
    /// into `currentPatch` (`EchoelStudioView.applySoundPrompt`) and lives in the SAME panel as
    /// the rows that render those numbers, so a bound here that is NARROWER than its row silently
    /// destroys a value the user set with a finger, and one that is WIDER produces a value the row
    /// rewrites on first touch. Both failure modes had been live:
    ///
    ///   · `decay` clamped to 5 while the row spans 0…10 — `Drone Bed` ships 6.0 s, so ANY
    ///     recognised descriptor typed into the same panel rewrote it as 5.0 (fixed by #430,
    ///     by WIDENING here — never by rounding the patch).
    ///   · `reverbDecay` clamped to 12 while the row spans 0…10 (also #430).
    ///   · `filterLFORate` clamped to 12 while the row spans 0…20 — this one survived #430 and
    ///     was written off as harmless because the shipped bank tops out at 1.2. That reasoning
    ///     looked at the wrong population: the row lets a FINGER reach 20, and every recognised
    ///     descriptor then rewrote that as 12. A user-set value being destroyed is the harder
    ///     kind to notice than a shipped one, because no test fixture holds it.
    ///
    /// `attack`'s old 0.001 floor is gone from THIS function, and the reason is measured rather
    /// than assumed: `EchoelDDSP`'s envelope enforces a ~3 ms minimum attack ramp in its `.attack`
    /// stage, so 0 and 0.001 are the same sound and the floor's stated purpose ("a musical
    /// minimum below every shipped onset") was already served one layer down. Nothing here can
    /// produce a zero-length onset.
    ///
    /// ⚠️ TO BE EXACT, because "the floor is gone" would otherwise read wider than it is: the
    /// `"hard"/"punchy"/"plucky"` case in `shape` keeps its own `max(0.001, …)`. That one is not
    /// a range bound — it is a SHAPING decision (a multiplicative shortening that must not walk
    /// to zero over repeated words), it sits inside the range either way, and it is deliberately
    /// left where it is.
    ///
    /// ⚠️ `clamped(to:)` rather than `min(max(…))`: the NaN-safe one. A prompt cannot produce a
    /// non-finite value from a finite patch today — every `shape` case is `+`/`*` on finite
    /// literals — but this function is the LAST thing between "Describe it" and the audio thread,
    /// and `min(max(x, lo), hi)` passes NaN straight through by argument order (the house rule in
    /// `Core/FloatingPointClamp.swift`, which has cost this repo shipped permanent silence).
    private static func clamp(_ p: inout SynthPatch) {
        typealias B = SynthPatch.Bounds
        p.brightness = p.brightness.clamped(to: B.brightness)
        p.harmonicity = p.harmonicity.clamped(to: B.harmonicity)
        p.harmonicLevel = p.harmonicLevel.clamped(to: B.harmonicLevel)
        p.noiseLevel = p.noiseLevel.clamped(to: B.noiseLevel)
        p.sustain = p.sustain.clamped(to: B.sustain)
        p.reverbMix = p.reverbMix.clamped(to: B.reverbMix)
        p.filterResonance = p.filterResonance.clamped(to: B.filterResonance)
        p.lfoToFilterDepth = p.lfoToFilterDepth.clamped(to: B.lfoToFilterDepth)
        p.filterLFODepth = p.filterLFODepth.clamped(to: B.filterLFODepth)
        p.vibratoDepth = p.vibratoDepth.clamped(to: B.vibratoDepth)
        p.attack = p.attack.clamped(to: B.attack)
        p.decay = p.decay.clamped(to: B.decay)
        p.release = p.release.clamped(to: B.release)
        p.filterCutoff = p.filterCutoff.clamped(to: B.filterCutoff)
        p.filterLFORate = p.filterLFORate.clamped(to: B.filterLFORate)
        p.reverbDecay = p.reverbDecay.clamped(to: B.reverbDecay)
        p.vibratoRate = p.vibratoRate.clamped(to: B.vibratoRate)
    }
}
