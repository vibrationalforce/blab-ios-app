// FXPreset.swift
// Echoel — a complete, shareable snapshot of an EchoelFXChain.
//
// One portable Codable value captures every stage's enable + its continuous
// parameters, so a preset is a single `.echoelfx` JSON file. The SAME type backs
// three things: the user's own saved presets (local), the curated community
// library (bundled in the app, founder-ranked via `tags` + a featured order), and
// the submit-for-curation flow (the JSON is embedded in a pre-filled GitHub issue).
//
// Enum modes are stored as their String rawValue so this model has no dependency
// on the DSP enums' Codable conformance. `schema` is a forward-compat version so a
// future field addition can be decoded leniently.

import Foundation

public struct FXPreset: Codable, Identifiable, Sendable, Equatable {

    // Identity / curation
    public var id: UUID
    public var name: String
    /// Curation tags ("vapor", "dub", "lofi", …). Empty for plain user presets.
    public var tags: [String]
    /// Forward-compat schema version (bump when fields change).
    public var schema: Int

    // Master gate
    public var fxEnabled: Bool

    // Filter
    public var filterEnabled: Bool
    public var filterModeRaw: String
    public var filterCutoff: Float
    public var filterResonance: Float

    // Saturation
    public var saturationEnabled: Bool
    public var saturationDrive: Float
    public var saturationMix: Float

    // Harmonizer (topology only — its internal params aren't surfaced yet)
    public var harmonizerEnabled: Bool

    // Chorus
    public var chorusEnabled: Bool
    public var chorusRate: Float
    public var chorusDepth: Float
    public var chorusMix: Float

    // Flanger
    public var flangerEnabled: Bool
    public var flangerRate: Float
    public var flangerDepth: Float
    public var flangerFeedback: Float
    public var flangerMix: Float

    // Phaser
    public var phaserEnabled: Bool
    public var phaserRate: Float
    public var phaserDepth: Float
    public var phaserFeedback: Float
    public var phaserMix: Float

    // Tremolo
    public var tremoloEnabled: Bool
    public var tremoloRate: Float
    public var tremoloDepth: Float
    public var tremoloStereoPan: Bool

    // Delay
    public var delayEnabled: Bool
    public var delayModeRaw: String
    public var delayMix: Float
    public var delayTime: Float
    public var delayFeedback: Float
    public var delayTone: Float
    public var delayWow: Float
    public var delayDrive: Float

    // Reverb (topology only)
    public var reverbEnabled: Bool

    // Compressor
    public var compressorEnabled: Bool
    public var compThreshold: Float
    public var compRatio: Float
    public var compMakeup: Float

    // Limiter
    public var limiterEnabled: Bool
    public var limiterCeiling: Float

    /// Lenient decode: any field missing from an older/newer file falls back to a
    /// safe default, so a preset never fails to load on a schema mismatch.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func f(_ k: CodingKeys, _ d: Float) -> Float { (try? c.decode(Float.self, forKey: k)) ?? d }
        func b(_ k: CodingKeys, _ d: Bool) -> Bool { (try? c.decode(Bool.self, forKey: k)) ?? d }
        func s(_ k: CodingKeys, _ d: String) -> String { (try? c.decode(String.self, forKey: k)) ?? d }

        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = s(.name, "Preset")
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        schema = (try? c.decode(Int.self, forKey: .schema)) ?? 1

        fxEnabled = b(.fxEnabled, true)

        filterEnabled = b(.filterEnabled, false)
        filterModeRaw = s(.filterModeRaw, "lowpass")
        filterCutoff = f(.filterCutoff, 18000)
        filterResonance = f(.filterResonance, 0)

        saturationEnabled = b(.saturationEnabled, true)
        saturationDrive = f(.saturationDrive, 0.30)
        saturationMix = f(.saturationMix, 0.5)

        harmonizerEnabled = b(.harmonizerEnabled, false)

        chorusEnabled = b(.chorusEnabled, true)
        chorusRate = f(.chorusRate, 0.45)
        chorusDepth = f(.chorusDepth, 0.35)
        chorusMix = f(.chorusMix, 0.22)

        flangerEnabled = b(.flangerEnabled, false)
        flangerRate = f(.flangerRate, 0.2)
        flangerDepth = f(.flangerDepth, 0.5)
        flangerFeedback = f(.flangerFeedback, 0)
        flangerMix = f(.flangerMix, 0.5)

        phaserEnabled = b(.phaserEnabled, false)
        phaserRate = f(.phaserRate, 0.2)
        phaserDepth = f(.phaserDepth, 0.5)
        phaserFeedback = f(.phaserFeedback, 0)
        phaserMix = f(.phaserMix, 0.5)

        tremoloEnabled = b(.tremoloEnabled, false)
        tremoloRate = f(.tremoloRate, 4)
        tremoloDepth = f(.tremoloDepth, 0.5)
        tremoloStereoPan = b(.tremoloStereoPan, false)

        delayEnabled = b(.delayEnabled, false)
        delayModeRaw = s(.delayModeRaw, "digital")
        delayMix = f(.delayMix, 0.3)
        delayTime = f(.delayTime, 0.3)
        delayFeedback = f(.delayFeedback, 0.3)
        delayTone = f(.delayTone, 0.5)
        delayWow = f(.delayWow, 0)
        delayDrive = f(.delayDrive, 0)

        reverbEnabled = b(.reverbEnabled, false)

        compressorEnabled = b(.compressorEnabled, false)
        compThreshold = f(.compThreshold, -18)
        compRatio = f(.compRatio, 3)
        compMakeup = f(.compMakeup, 0)

        limiterEnabled = b(.limiterEnabled, true)
        limiterCeiling = f(.limiterCeiling, -0.5)
    }

    /// Direct memberwise init (used by `capture`).
    public init(
        id: UUID, name: String, tags: [String], schema: Int,
        fxEnabled: Bool,
        filterEnabled: Bool, filterModeRaw: String, filterCutoff: Float, filterResonance: Float,
        saturationEnabled: Bool, saturationDrive: Float, saturationMix: Float,
        harmonizerEnabled: Bool,
        chorusEnabled: Bool, chorusRate: Float, chorusDepth: Float, chorusMix: Float,
        flangerEnabled: Bool, flangerRate: Float, flangerDepth: Float, flangerFeedback: Float, flangerMix: Float,
        phaserEnabled: Bool, phaserRate: Float, phaserDepth: Float, phaserFeedback: Float, phaserMix: Float,
        tremoloEnabled: Bool, tremoloRate: Float, tremoloDepth: Float, tremoloStereoPan: Bool,
        delayEnabled: Bool, delayModeRaw: String, delayMix: Float, delayTime: Float,
        delayFeedback: Float, delayTone: Float, delayWow: Float, delayDrive: Float,
        reverbEnabled: Bool,
        compressorEnabled: Bool, compThreshold: Float, compRatio: Float, compMakeup: Float,
        limiterEnabled: Bool, limiterCeiling: Float
    ) {
        self.id = id; self.name = name; self.tags = tags; self.schema = schema
        self.fxEnabled = fxEnabled
        self.filterEnabled = filterEnabled; self.filterModeRaw = filterModeRaw
        self.filterCutoff = filterCutoff; self.filterResonance = filterResonance
        self.saturationEnabled = saturationEnabled; self.saturationDrive = saturationDrive; self.saturationMix = saturationMix
        self.harmonizerEnabled = harmonizerEnabled
        self.chorusEnabled = chorusEnabled; self.chorusRate = chorusRate; self.chorusDepth = chorusDepth; self.chorusMix = chorusMix
        self.flangerEnabled = flangerEnabled; self.flangerRate = flangerRate; self.flangerDepth = flangerDepth
        self.flangerFeedback = flangerFeedback; self.flangerMix = flangerMix
        self.phaserEnabled = phaserEnabled; self.phaserRate = phaserRate; self.phaserDepth = phaserDepth
        self.phaserFeedback = phaserFeedback; self.phaserMix = phaserMix
        self.tremoloEnabled = tremoloEnabled; self.tremoloRate = tremoloRate
        self.tremoloDepth = tremoloDepth; self.tremoloStereoPan = tremoloStereoPan
        self.delayEnabled = delayEnabled; self.delayModeRaw = delayModeRaw; self.delayMix = delayMix
        self.delayTime = delayTime; self.delayFeedback = delayFeedback; self.delayTone = delayTone
        self.delayWow = delayWow; self.delayDrive = delayDrive
        self.reverbEnabled = reverbEnabled
        self.compressorEnabled = compressorEnabled; self.compThreshold = compThreshold
        self.compRatio = compRatio; self.compMakeup = compMakeup
        self.limiterEnabled = limiterEnabled; self.limiterCeiling = limiterCeiling
    }
}

public extension FXPreset {

    /// Snapshot the live chain into a portable preset.
    static func capture(
        from chain: EchoelFXChain,
        fxEnabled: Bool,
        id: UUID = UUID(),
        name: String,
        tags: [String] = []
    ) -> FXPreset {
        FXPreset(
            id: id, name: name, tags: tags, schema: 1,
            fxEnabled: fxEnabled,
            filterEnabled: chain.filterEnabled,
            filterModeRaw: chain.filterL.mode.rawValue,
            filterCutoff: chain.filterL.cutoff,
            filterResonance: chain.filterL.resonance,
            saturationEnabled: chain.saturationEnabled,
            saturationDrive: chain.saturationDrive,
            saturationMix: chain.saturationMix,
            harmonizerEnabled: chain.harmonizerEnabled,
            chorusEnabled: chain.chorusEnabled,
            chorusRate: chain.chorus.rate,
            chorusDepth: chain.chorus.depth,
            chorusMix: chain.chorus.mix,
            flangerEnabled: chain.flangerEnabled,
            flangerRate: chain.flanger.rate,
            flangerDepth: chain.flanger.depth,
            flangerFeedback: chain.flanger.feedback,
            flangerMix: chain.flanger.mix,
            phaserEnabled: chain.phaserEnabled,
            phaserRate: chain.phaser.rate,
            phaserDepth: chain.phaser.depth,
            phaserFeedback: chain.phaser.feedback,
            phaserMix: chain.phaser.mix,
            tremoloEnabled: chain.tremoloEnabled,
            tremoloRate: chain.tremolo.rate,
            tremoloDepth: chain.tremolo.depth,
            tremoloStereoPan: chain.tremolo.stereoPan,
            delayEnabled: chain.delayEnabled,
            delayModeRaw: chain.delay.mode.rawValue,
            delayMix: chain.delay.mix,
            delayTime: chain.delay.timeSeconds,
            delayFeedback: chain.delay.feedback,
            delayTone: chain.delay.tone,
            delayWow: chain.delay.wow,
            delayDrive: chain.delay.drive,
            reverbEnabled: chain.reverbEnabled,
            compressorEnabled: chain.compressorEnabled,
            compThreshold: chain.compressor.thresholdDb,
            compRatio: chain.compressor.ratio,
            compMakeup: chain.compressor.makeupDb,
            limiterEnabled: chain.limiterEnabled,
            limiterCeiling: chain.limiter.ceilingDb
        )
    }

    /// Write this preset's parameters into a live chain. The caller flips the
    /// voice's master gate from `fxEnabled` and refreshes any UI mirrors.
    func apply(to chain: EchoelFXChain) {
        chain.filterEnabled = filterEnabled
        chain.setFilter(
            mode: EchoelSVFilter.Mode(rawValue: filterModeRaw) ?? .lowpass,
            cutoff: filterCutoff,
            resonance: filterResonance
        )
        chain.saturationEnabled = saturationEnabled
        chain.saturationDrive = saturationDrive
        chain.saturationMix = saturationMix
        chain.harmonizerEnabled = harmonizerEnabled
        chain.chorusEnabled = chorusEnabled
        chain.chorus.rate = chorusRate
        chain.chorus.depth = chorusDepth
        chain.chorus.mix = chorusMix
        chain.flangerEnabled = flangerEnabled
        chain.flanger.rate = flangerRate
        chain.flanger.depth = flangerDepth
        chain.flanger.feedback = flangerFeedback
        chain.flanger.mix = flangerMix
        chain.phaserEnabled = phaserEnabled
        chain.phaser.rate = phaserRate
        chain.phaser.depth = phaserDepth
        chain.phaser.feedback = phaserFeedback
        chain.phaser.mix = phaserMix
        chain.tremoloEnabled = tremoloEnabled
        chain.tremolo.rate = tremoloRate
        chain.tremolo.depth = tremoloDepth
        chain.tremolo.stereoPan = tremoloStereoPan
        chain.delayEnabled = delayEnabled
        chain.delay.mode = EchoelDelay.Mode(rawValue: delayModeRaw) ?? .digital
        chain.delay.mix = delayMix
        chain.delay.timeSeconds = delayTime
        chain.delay.feedback = delayFeedback
        chain.delay.tone = delayTone
        chain.delay.wow = delayWow
        chain.delay.drive = delayDrive
        chain.reverbEnabled = reverbEnabled
        chain.compressorEnabled = compressorEnabled
        chain.compressor.thresholdDb = compThreshold
        chain.compressor.ratio = compRatio
        chain.compressor.makeupDb = compMakeup
        chain.limiterEnabled = limiterEnabled
        chain.limiter.ceilingDb = limiterCeiling
    }

    // MARK: - Curated community library (bundled, founder-ranked)

    /// Echoel's curated starter library: the production characters captured as
    /// browsable, tagged presets. **Founder-curated — the array order IS the
    /// featured order.** Bundled in the app (the safe, offline baseline); an
    /// additive live-refresh from the repo can layer on later without changing
    /// this model. Community submissions are merged into the repo over time.
    ///
    /// Computed ONCE (`static let`) so the list keeps a stable identity across
    /// SwiftUI renders. (`.auto` needs a genre and `.clean` is the dry reset —
    /// both excluded; they aren't "sounds".)
    static let curatedCommunity: [FXPreset] = {
        let featured: [FXCharacter] = [
            .dream, .hall, .room, .cassette, .vinyl,
            .underwater, .blurry, .telephone, .megaphone, .harmonizer
        ]
        return featured.map { ch in
            let chain = EchoelFXChain()
            ch.apply(to: chain, bpm: 120, genre: .selfObservation)
            return FXPreset.capture(from: chain, fxEnabled: true,
                                    name: ch.displayName, tags: ch.presetTags)
        }
    }()
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
