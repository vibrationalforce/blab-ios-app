// FXCuratedLibrary.swift
// Echoel — the bundled, founder-curated FX preset library + per-character tags.
//
// Lives OUTSIDE Sources/Echoelmusic/DSP on purpose: DSP/ stays Foundation-only
// (self-contained Foundation+Accelerate) by hygiene. This code depends on
// FXCharacter (Sequencer/) and MusicStyle, which are main-app-only — so keeping
// it here keeps DSP/FXPreset.swift portable. (The rule was originally enforced by
// the EchoelmusicAUv3 target, removed 2026-07-24 in the pure-instrument verdict.)

import Foundation

public extension FXPreset {

    // MARK: - Curated community library (bundled, founder-ranked)

    /// Echoel's curated starter library: the production characters captured as
    /// browsable, tagged presets. **Founder-curated — the array order IS the
    /// featured order.** Bundled in the app (the safe, offline baseline); merged
    /// community submissions (`CommunityLibrary.fx`) are appended.
    ///
    /// Computed ONCE (`static let`) so the list keeps a stable identity across
    /// SwiftUI renders. (`.auto` needs a genre and `.clean` is the dry reset —
    /// both excluded; they aren't "sounds".)
    static let curatedCommunity: [FXPreset] = {
        // Production characters captured as presets (founder-ranked order).
        let featured: [FXCharacter] = [
            .dream, .hall, .room, .cassette, .vinyl,
            .underwater, .blurry, .telephone, .megaphone, .harmonizer
        ]
        let fromCharacters = featured.map { ch -> FXPreset in
            let chain = EchoelFXChain()
            ch.apply(to: chain, bpm: 120, genre: .selfObservation)
            return FXPreset.capture(from: chain, fxEnabled: true,
                                    name: ch.displayName, tags: ch.presetTags)
        }
        // Hand-crafted multi-stage signature presets (richer than a single
        // character) — built by configuring a fresh chain, then captured.
        let signatures: [FXPreset] = [
            make("Cathedral", ["reverb", "huge", "ambient"]) { c in
                c.reverbEnabled = true; c.reverb.roomSize = 0.95; c.reverb.damping = 0.35
                c.reverb.mix = 0.45; c.reverb.width = 1.0
                c.chorusEnabled = true; c.chorus.mix = 0.18
            },
            make("Warm Tape Wide", ["lofi", "warm", "wide"]) { c in
                c.saturationEnabled = true; c.saturationDrive = 0.55; c.saturationMix = 0.6
                c.chorusEnabled = true; c.chorus.depth = 0.5; c.chorus.mix = 0.3
                c.delayEnabled = true; c.delay.mode = .tape; c.delay.timeSeconds = 0.28
                c.delay.feedback = 0.25; c.delay.wow = 0.3
            },
            make("Octave Lead", ["harmony", "lead"]) { c in
                c.harmonizerEnabled = true; c.harmonizer.interval1 = 12
                c.harmonizer.voice2Enabled = true; c.harmonizer.interval2 = 7; c.harmonizer.mix = 0.45
                c.delayEnabled = true; c.delay.timeSeconds = 0.18; c.delay.feedback = 0.2; c.delay.mix = 0.2
            },
            make("Dub Chamber", ["dub", "delay", "space"]) { c in
                c.delayEnabled = true; c.delay.mode = .tape; c.delay.timeSeconds = 0.5
                c.delay.feedback = 0.65; c.delay.tone = 0.4; c.delay.mix = 0.4
                c.reverbEnabled = true; c.reverb.roomSize = 0.8; c.reverb.mix = 0.3
            },
            make("Crystal Shimmer", ["bright", "shimmer", "ambient"]) { c in
                c.reverbEnabled = true; c.reverb.roomSize = 0.9; c.reverb.damping = 0.2; c.reverb.mix = 0.4
                c.chorusEnabled = true; c.chorus.rate = 0.3; c.chorus.depth = 0.6; c.chorus.mix = 0.35
                c.flangerEnabled = true; c.flanger.depth = 0.3; c.flanger.mix = 0.2
            },
            make("Lo-Fi Dust", ["lofi", "vintage", "filter"]) { c in
                c.filterEnabled = true; c.setFilter(mode: .lowpass, cutoff: 5500, resonance: 0.1)
                c.saturationEnabled = true; c.saturationDrive = 0.5; c.saturationMix = 0.5
                c.delayEnabled = true; c.delay.mode = .tape; c.delay.wow = 0.5
                c.delay.timeSeconds = 0.22; c.delay.feedback = 0.2; c.delay.mix = 0.18
            },
            make("Slapback Room", ["slap", "room", "vocal"]) { c in
                c.delayEnabled = true; c.delay.mode = .tape; c.delay.timeSeconds = 0.12
                c.delay.feedback = 0.15; c.delay.mix = 0.25
                c.reverbEnabled = true; c.reverb.roomSize = 0.5; c.reverb.mix = 0.18
            },
            make("Fifth Stack", ["harmony", "thick", "lead"]) { c in
                c.harmonizerEnabled = true; c.harmonizer.interval1 = 7
                c.harmonizer.voice2Enabled = true; c.harmonizer.interval2 = 12; c.harmonizer.mix = 0.4
                c.chorusEnabled = true; c.chorus.mix = 0.18
            },
            make("Tape Wobble", ["lofi", "tape", "warble"]) { c in
                c.saturationEnabled = true; c.saturationDrive = 0.6; c.saturationMix = 0.6
                c.delayEnabled = true; c.delay.mode = .tape; c.delay.wow = 0.7
                c.delay.timeSeconds = 0.3; c.delay.feedback = 0.3; c.delay.tone = 0.4; c.delay.mix = 0.25
            },
            make("Phaser Sweep", ["modulation", "movement"]) { c in
                c.phaserEnabled = true; c.phaser.rate = 0.3; c.phaser.depth = 0.7
                c.phaser.feedback = 0.5; c.phaser.mix = 0.5
                c.tremoloEnabled = true; c.tremolo.rate = 5; c.tremolo.depth = 0.3
            },
            make("Dark Filter Dub", ["dub", "dark", "space"]) { c in
                c.filterEnabled = true; c.setFilter(mode: .lowpass, cutoff: 3500, resonance: 0.15)
                c.delayEnabled = true; c.delay.mode = .tape; c.delay.timeSeconds = 0.5
                c.delay.feedback = 0.6; c.delay.tone = 0.35; c.delay.mix = 0.4
                c.reverbEnabled = true; c.reverb.roomSize = 0.8; c.reverb.mix = 0.3
            }
        ]
        // Bundled community submissions (merged PRs) — appended after the
        // built-in set; empty until the first curated JSON ships.
        return fromCharacters + signatures + CommunityLibrary.fx
    }()

    /// Build a curated preset by configuring a fresh chain, then capturing it.
    private static func make(_ name: String, _ tags: [String],
                             _ configure: (EchoelFXChain) -> Void) -> FXPreset {
        let chain = EchoelFXChain()
        configure(chain)
        return FXPreset.capture(from: chain, fxEnabled: true, name: name, tags: tags)
    }
}

private extension FXCharacter {
    /// Curation tags for the bundled community library.
    var presetTags: [String] {
        switch self {
        case .dream:      return ["lush", "wide", "ambient"]
        case .hall:       return ["reverb", "space", "big"]
        case .room:       return ["reverb", "natural"]
        case .cassette:   return ["lofi", "tape", "warm"]
        case .vinyl:      return ["lofi", "vintage"]
        case .underwater: return ["filter", "watery", "experimental"]
        case .blurry:     return ["soft", "wash", "ambient"]
        case .telephone:  return ["lofi", "vocal", "filter"]
        case .megaphone:  return ["gritty", "vocal"]
        case .harmonizer: return ["harmony", "thick"]
        default:          return []
        }
    }
}
