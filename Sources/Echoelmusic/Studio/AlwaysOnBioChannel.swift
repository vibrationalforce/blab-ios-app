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
//    · hrvVariability→ brightness   (⛔ "· reverb mix" struck, see below)
//    · heartRate     → vibrato depth AND rate · brightness
//    · breathPhase   → amplitude (the breath swell)
//  The table is not wrong so much as PARTIAL, and a UI built from it would have shipped a
//  fresh under-statement onto the one surface #496 just corrected for over-statement.
//
//  ⛔ AND READING IT OFF `applyBioReactive` WAS NOT ENOUGH — the write is there and the READ
//  is switched off (#546). `applyBioReactive` really does set `reverbMix` from
//  `hrvVariability` (`EchoelDDSP.swift:2195`), so the measurement above was honest about what
//  it looked at. But `reverbMix` is read at exactly one place — inside
//  `if Self.useConvolutionReverb, reverbMix > 0, …` (`EchoelDDSP.swift:1503`) — and
//  `useConvolutionReverb` is declared `false` with NO assignment anywhere in `Sources/`
//  (`git grep -n "useConvolutionReverb *=" -- Sources` returns the declaration and nothing
//  else). The stage cannot produce sound, so HRV moves no reverb, and the user-facing
//  `.hrv` row said "brightness · reverb" until this slice.
//
//  ⭐ THE LESSON IS ABOUT WHERE A MAPPING ENDS, and it is a different one from #496's. That
//  slice removed three channels with NO PRODUCER — nothing wrote them. This one is the
//  mirror: a producer that writes faithfully into a CONSUMER THAT IS COMPILED OUT AT RUNTIME.
//  Following the value one hop from the assignment looks like the careful thing to do and
//  stops one hop short. **A mapping is live when the write reaches an ungated read**, and the
//  cheap check is to grep the destination's readers, not only its writers.
//
//  ⚠️ NOT the same reverb the FX panel sells. `EchoelReverb` in `EchoelFXChain` is
//  algorithmic, switched on by the genre presets, and a bio ROUTE onto its parameters is
//  reachable through the modulation matrix — so `EchoelFXView`'s "coherence → reverb" hint
//  is true and must NOT be "corrected" by anyone acting on this paragraph. The dead one is
//  the convolution stage inside `EchoelDDSP`, which only the always-on path touches.
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

    /// The one-sentence version of this whole enum, for a surface that has room for a line but
    /// not for four rows.
    ///
    /// ⭐ IT MOVED HERE IN #542, AND THE MOVE IS THE POINT. It was `BioModLiveView.alwaysOnNote`
    /// — one reader, in the FX sheet. The Bio panel promises "your body then drives the sound"
    /// and then names nothing, so a player who asks the question where it naturally occurs to
    /// them gets no answer; the answer sat two chips away behind Effects → All parameters →
    /// scroll. Giving the Bio panel its own wording would have been the #416 defect (two
    /// spellings of one claim, and this one has already had to be corrected twice — #496 for
    /// over-claiming, #498 for the channel list). So the sentence has ONE home and two callers.
    ///
    /// ⚠️ IT NAMES EXACTLY THE FOUR CASES OF THIS ENUM, and that is enforced, not hoped:
    /// `TheAlwaysOnBioPathIsNamedTests` binds it to the two `…BioParams(` construction sites, so
    /// wiring a real producer for one of the three pinned channels (`breathDepth`, `lfHf`,
    /// `coherenceTrend` — all handed neutral literals today) goes red HERE instead of quietly
    /// leaving the sentence one channel short.
    public static let alwaysOnSentence =
        "Separately from these routes, four body channels shape the instrument's own timbre "
        + "while a session runs: coherence, HRV, heart rate and breath phase. Routes here add "
        + "effect parameters on top."

    /// The same claim for a surface that is NOT the FX sheet — same four channels, no "these
    /// routes" to point at.
    ///
    /// ⚠️ TWO STRINGS AND NOT ONE, deliberately, and this is the line where #416 could be
    /// misread into a worse outcome. The rule is one definition per DECISION; the decision here
    /// is WHICH FOUR CHANNELS, and both sentences take that from the same four enum cases,
    /// which the guard pins. What differs is the deictic half — the FX footer sits under a list
    /// of routes and says "these", the Bio panel has no such list and must say where to look.
    /// Folding them into one string would force one of the two surfaces to point at something
    /// that is not there, which is exactly the class of copy #491 and #480 had to retract.
    public static let bioPanelSentence =
        "Four body channels shape the instrument's own timbre while a session runs: coherence, "
        + "HRV, heart rate and breath phase. To watch them move — and to add your own routes "
        + "onto effect parameters — open Effects › All parameters."

    /// What this channel moves in the engine, in the channel row's own reading order.
    ///
    /// ⭐ #560 TURNED THIS FROM A STRING INTO A SET, and the reason is the direction nobody
    /// could ask before: the channel rows answer "what does coherence move?", while a player
    /// standing in the Sound panel is asking the INVERSE — "which of these numbers does my
    /// body move?". A `· `-joined string can be read forwards only. `shapes` below is now
    /// derived from this, so the two directions cannot disagree (#416); the rendered words are
    /// unchanged, and `TheBodyShapedRowsAreNamedOnceTests` pins them character for character.
    ///
    /// ⚠️ THE ORDER HERE IS THE CHANNEL ROW'S, NOT the enum's declaration order — the latter is
    /// the Sound panel's top-to-bottom order and is used by `soundPanelSentence`. Two orders
    /// for two readings, and confusing them silently rewrites a user-facing string.
    ///
    /// ⛔ NO REVERB CASE EXISTS, deliberately (#546). `applyBioReactive` really does write
    /// `reverbMix` from `hrvVariability`, but the only read of it is gated on
    /// `EchoelDDSP.useConvolutionReverb`, which is `false` with no writer in `Sources/` — the
    /// stage cannot sound. `DisabledReverbIsNotClaimedLiveTests` scans THIS member (and
    /// `shapes`) for the word and falls silent by itself the day the stage is enabled.
    public var shapedParameters: [BioShapedParameter] {
        switch self {
        case .coherence:   return [.filterCutoff, .brightness, .harmonicity, .noiseLevel]
        case .hrv:         return [.brightness]
        case .heartRate:   return [.vibrato, .brightness]
        case .breathPhase: return [.amplitude]
        }
    }

    /// What this channel moves in the engine, read off `applyBioReactive` (see the file
    /// header for the measurement and for the one profile-dependent exception).
    ///
    /// Derived rather than written out since #560 — the words and the separator are unchanged.
    public var shapes: String {
        shapedParameters.map(\.channelWord).joined(separator: " · ")
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

    /// What a surface should show for this channel right now: the number, whether it is a
    /// measurement, and whether that measurement has stopped arriving (#500).
    ///
    /// ⭐ WHY A THIRD FACT. #497 made an unmeasured channel hand the engine its declared
    /// neutral, and #498 put the pair (value, measured) on screen so a neutral could not be
    /// read as a body sitting mid-scale. The pair still cannot separate a LIVE body from a
    /// frame that stopped arriving, and that gap is not hypothetical: `EngineBus.latestBio`
    /// is only ever ASSIGNED — nothing clears it, not `stop()`, not a lost pulse (its one
    /// writer is the `publish(bio:)` sink). `isMeasured` is a property of the FRAME, never of
    /// its age, so a frame from forty minutes ago reports `true` forever, under a header that
    /// says "Always on — body → timbre". That is the same ambiguity #497/#498 removed, one
    /// level up, introduced by the surface that removed it.
    ///
    /// ⚠️ AND THE VALUE IS STILL RIGHT, WHICH IS WHY `isHeld` MARKS RATHER THAN BLANKS. The
    /// sound producers poll `latestBio` and dedupe on `timestamp`, so a frozen source does not
    /// zero the timbre — it PARKS it at the last body and leaves it there. Blanking the number
    /// would claim the engine dropped the channel; it did not. The honest reading is "this is
    /// what the engine has, and it is no longer arriving".
    ///
    /// ⛔ AND THIS SAID "the FOUR sound producers", which is measured wrong and contradicted a
    /// correct line in `EchoelFXView` ("both sound producers poll `bus.latestBio` raw"). Four
    /// voices SUBSCRIBE; `PolySynthVoice.applyLatestIfFresh` returns at
    /// `guard bioModulationEnabled` before it ever reads the bus, and only `polyVoice` has a
    /// reachable writer for that flag — so TWO reach the frame (`bioVoice`, `polyVoice`). The
    /// PARKING argument does not depend on the count, which is exactly why the wrong number
    /// survived: it was decoration on a sound sentence. Full measurement at the ⛔ on
    /// `EchoelFXView.alwaysOnNote`.
    ///
    /// ⭐ THE THRESHOLD IS ASKED, NOT RESTATED (#416/#426). `isHeld` is the exact negation of
    /// `EngineBus.usableBio()`'s two comparisons against `frame.source.freshnessWindow` — the
    /// same line the COMPOSER uses to decide whether a take has a body at all. So a held row is
    /// a state that prints `body=0` in the generate breadcrumb, and retuning a source's window
    /// moves both together instead of leaving a screen behind.
    ///
    /// ⚠️ ONE-DIRECTIONAL, NOT AN EQUIVALENCE — the first version wrote "precisely the state".
    /// `body=0` is `usableBio() == nil`, which is also true with NO frame at all and with a
    /// stale frame whose channels were never measured; neither of those shows "held". So
    /// held ⇒ `body=0`, and the converse is false.
    ///
    /// ⚠️ NON-FINITE AGE READS AS HELD, deliberately. A NaN age fails both comparisons, so the
    /// negation is `true` — the direction that claims LESS liveness. A frame stamped in the
    /// future beyond the 1 s skew tolerance is likewise held, because `usableBio()` rejects it
    /// and the composer is already treating it as no body.
    public func reading(in frame: BioSampleFrame?, now: TimeInterval) -> AlwaysOnBioReading {
        guard let frame else {
            return AlwaysOnBioReading(value: 0.5, isMeasured: false, isHeld: false)
        }
        let measured = isMeasured(in: frame)
        let age = now - frame.timestamp
        // Both halves ASKED, neither restated: this row must agree with `usableBio()` exactly,
        // or the strip says "held" while the composer still plays the frame (or the reverse).
        // The skew half was a literal `-1` here until #545 while the doc block eight lines up
        // already called it "the 1 s skew tolerance" — the prose named a constant that did not
        // exist yet.
        let usable = age <= frame.source.freshnessWindow
            && age >= -BioSource.futureSkewTolerance
        return AlwaysOnBioReading(value: value(in: frame),
                                  isMeasured: measured,
                                  isHeld: measured && !usable)
    }
}

/// What one always-on channel shows at a moment in time — the three facts that must travel
/// together, because any two of them read as something the third contradicts (#498, #500).
///
/// `isHeld` is only ever true together with `isMeasured`: an unmeasured channel already shows
/// "—", and calling that "held" would add a word without adding a fact.
public struct AlwaysOnBioReading: Equatable, Sendable {
    /// The number the engine is receiving — the `…ForSound` accessor, or the declared neutral
    /// 0.5 when there is no frame at all.
    public let value: Float
    /// Whether `value` is a measurement rather than the engine's declared neutral.
    public let isMeasured: Bool
    /// Whether that measurement has aged out of its own source's freshness window — the
    /// engine still has it, the body is no longer sending it.
    public let isHeld: Bool

    public init(value: Float, isMeasured: Bool, isHeld: Bool) {
        self.value = value
        self.isMeasured = isMeasured
        self.isHeld = isHeld
    }
}

/// One engine parameter the always-on bio path writes, named once so the CHANNEL rows and the
/// SOUND PANEL can describe the same fact from opposite directions (#560).
///
/// ⭐ WHY THE INVERSE DIRECTION IS WORTH A TYPE. The channel rows say "coherence moves filter ·
/// brightness · harmonicity · noise". A player is not standing in the Bio panel when the
/// question arrives — they are in Sound & texture, watching a number they set drift, and the
/// question is "which of THESE does my body move?". Both readings come from this one set, so
/// they cannot drift into naming different parameters; a hand-written second sentence is
/// exactly the #416 defect, and on this subject the repo has already had to retract copy twice
/// (#496 for over-claiming, #546 for a stage that cannot sound).
///
/// ⚠️ THE CASE ORDER IS THE SOUND PANEL'S TOP-TO-BOTTOM ORDER (Tone → Filter → Space &
/// vibrato), because `soundPanelSentence` reads them in `allCases` order and a player scans the
/// sentence against the panel. The per-channel order is separate and lives on
/// `AlwaysOnBioChannel.shapedParameters`.
public enum BioShapedParameter: String, CaseIterable, Identifiable, Sendable {
    case brightness
    case harmonicity
    case noiseLevel
    case filterCutoff
    case vibrato
    case amplitude

    public var id: String { rawValue }

    /// The compact word the channel rows use. These four spellings are the ones that shipped
    /// before #560 and they are preserved character for character — the strings are rendered
    /// to a user by `EchoelFXView.AlwaysOnBioView` and by the Bio panel strip.
    public var channelWord: String {
        switch self {
        case .brightness:   return "brightness"
        case .harmonicity:  return "harmonicity"
        case .noiseLevel:   return "noise"
        case .filterCutoff: return "filter"
        case .vibrato:      return "vibrato"
        case .amplitude:    return "level"
        }
    }

    /// The Sound panel's OWN row labels for this parameter — the words a player can actually
    /// find on that screen. Empty when the panel has no row for it.
    ///
    /// ⛔ `amplitude` IS EMPTY AND THAT IS A MEASUREMENT, NOT AN OVERSIGHT. The breath swell
    /// rides `EchoelDDSP.amplitude` — the envelope's output inside the voice — and the Level
    /// group's "Output" row is `SynthPatch.outputLevel`, a per-patch loudness trim that
    /// `applyBioReactive` never touches. Listing "Output" here would point a player at a
    /// control the body does not move, which is the same class of error as claiming a channel
    /// the engine does not receive (#496). Breath is still named in the Bio panel, where the
    /// claim is about the CHANNEL rather than about a row on this screen.
    ///
    /// ⚠️ `vibrato` IS ONE PARAMETER WITH TWO ROWS. `applyBioReactive` scales `vibratoDepth`
    /// AND `vibratoRate` from the same heart-rate factor, so splitting it into two cases would
    /// suggest a player could see them move independently — they cannot.
    public var soundPanelRows: [String] {
        switch self {
        case .brightness:   return ["Brightness"]
        case .harmonicity:  return ["Harmonics"]
        case .noiseLevel:   return ["Noise"]
        case .filterCutoff: return ["Cutoff"]
        case .vibrato:      return ["Vibrato depth", "Vibrato rate"]
        case .amplitude:    return []
        }
    }

    /// Every parameter at least one live body channel writes, in Sound-panel order.
    ///
    /// Derived from the channels rather than listed again: a channel that stops shaping a
    /// parameter drops it from here in the same edit, and a parameter no channel writes can
    /// never appear.
    public static var shapedByTheBody: [BioShapedParameter] {
        let live = Set(AlwaysOnBioChannel.allCases.flatMap(\.shapedParameters))
        return allCases.filter { live.contains($0) }
    }

    /// The Sound panel's line: which rows ON THAT PANEL the body moves while a session runs.
    ///
    /// ⭐ IT SAYS "around the values you set" ON PURPOSE, and that is the #556 law in the
    /// player's language: these rows are ANCHORS. `applyBioReactive` recomputes each of them
    /// per render block from its `bioBase*` anchor, so a number that drifts is not a bug and
    /// not the automation the panel's other strip describes — it is the body. Answering that
    /// once, where the numbers are, is the whole point of the line.
    ///
    /// ⚠️ IT CLAIMS NO EFFECT SIZE. #497 measured two of these deviations at 25 % and 0.92 dB —
    /// loud enough to matter, small enough that a sentence is not a hearing test. "Move around"
    /// is the strongest verb the measurement supports.
    public static var soundPanelSentence: String {
        let rows = shapedByTheBody.flatMap(\.soundPanelRows)
        let list: String
        switch rows.count {
        case 0:  return "Your body is not shaping any control on this panel right now."
        case 1:  list = rows[0]
        default: list = rows.dropLast().joined(separator: ", ") + " and " + (rows.last ?? "")
        }
        return "Your body also shapes this sound while a session runs: \(list) move around the "
            + "values you set here. Open Bio to watch the four channels doing it."
    }
}
