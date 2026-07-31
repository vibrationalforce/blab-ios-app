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
            pendingIntensity = 1.0   // a modifier only affects the next descriptor
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

    private static func clamp(_ p: inout SynthPatch) {
        func c01(_ x: Float) -> Float { min(max(x, 0), 1) }
        p.brightness = c01(p.brightness)
        p.harmonicity = c01(p.harmonicity)
        p.harmonicLevel = c01(p.harmonicLevel)
        p.noiseLevel = c01(p.noiseLevel)
        p.sustain = c01(p.sustain)
        p.reverbMix = c01(p.reverbMix)
        p.filterResonance = c01(p.filterResonance)
        p.lfoToFilterDepth = c01(p.lfoToFilterDepth)
        p.filterLFODepth = c01(p.filterLFODepth)
        p.vibratoDepth = c01(p.vibratoDepth)
        p.attack = min(max(p.attack, 0.001), 5)
        p.decay = min(max(p.decay, 0.0), 5)
        p.release = min(max(p.release, 0.0), 10)
        p.filterCutoff = min(max(p.filterCutoff, 20), 18_000)
        p.filterLFORate = min(max(p.filterLFORate, 0), 12)
        p.reverbDecay = min(max(p.reverbDecay, 0), 12)
        p.vibratoRate = min(max(p.vibratoRate, 0), 12)
    }
}
