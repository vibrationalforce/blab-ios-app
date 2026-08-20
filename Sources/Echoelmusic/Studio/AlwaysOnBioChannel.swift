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

/// The ONE spelling of the mid-sentence demo subject — the phrase every surface uses to say
/// that a reading came from `BioSimulator` and not from a person.
///
/// ⭐ WHY A CONSTANT AND NOT TEN LITERALS, and the reason is stronger than ordinary #416:
/// **one of the ten was invisible to `git grep`.** `autoModeHint` split the phrase MID-PHRASE
/// across two literals to fit the line limit — `"… of the simulated demo " + "source, not your
/// body"` — so a search for the contiguous phrase returned nine and the tenth was policed by
/// nothing. The usual #416 argument is "two spellings drift"; the measurement here is that the
/// repo's own tool for checking this family could not see one of the sites at all.
/// ⛔ THE FIRST DRAFT OF THIS PARAGRAPH SAID "three of the nine were split" AND THAT WAS WRONG
/// IN BOTH NUMBERS — written from the shape of the diff instead of from a count. Two others
/// (`breathVoiceCaption`, `autoModeCaption`) break at a line boundary with the phrase intact
/// INSIDE one literal, so grep found them; only `autoModeHint` broke the phrase itself. The
/// count was ten, the invisible one was one. Corrected before the commit rather than after,
/// which is the only difference between this and the entries this file keeps retracting.
///
/// ⚠️ THIS OWNS ONE OF FOUR DOCUMENTED FORMS, and saying so is the point — a type claiming to
/// own the vocabulary while owning a quarter of it is the over-claim this whole family keeps
/// retracting. The census (spelled identically in `AlwaysOnBioRow`, `BioMetricInfo` and
/// `EchoelFXView`): element LABEL (`"Bio source: simulated demo, not your body"`) · spoken
/// PREFIX (`"Simulated demo, "`) · section HEAD (`"demo values, not your body"`) · and this
/// mid-sentence SUBJECT. **The label form is NOT hoistable here and that is measured, not
/// assumed:** its three sites are `Studio/BioStripView.swift`,
/// `Sources/EchoelmusicWatch/EchoelWatchApp.swift` and
/// `Sources/EchoelmusicWidgets/EchoelBioWidget.swift`, and `project.yml` gives the watch and
/// widget targets only their own directory plus `Core/BioFeedbackManager.swift` — neither
/// compiles this file. Hoisting it would mean moving copy into `Core/`, which is a different
/// decision and needs its own slice.
///
/// ⚠️ THREE SENTENCES DELIBERATELY DO NOT USE THIS and each names a different reason, so the
/// next session does not "finish the migration" into a regression:
///   · `BioShapedParameter.soundPanelSentence`'s empty-list branch and
///     `BioMusicDirector`'s explanation title say "The simulated demo source is/is doing …" —
///     the subject continues into a VERB, so the ", not your body" clause would be
///     ungrammatical there.
///   · `TempoFollowLabel.unlockHint` says "tap to let the simulated demo source drive it
///     again" — same shape, the clause cannot sit before "drive".
///   · `AutomationStatus` says "… is the simulated demo source, not automation and not your
///     body", a THREE-way contrast this two-way phrase cannot express.
/// A fourth, `FXModulation`/`EchoelFXView`, uses the short "simulated demo" inside a chip
/// label with no room for a clause. All five are honest; none is a missed site.
public enum BioProvenanceCopy {

    /// Mid-sentence: "… follows **the simulated demo source, not your body**".
    public static let demoSubject = "the simulated demo source, not your body"

    /// Sentence-initial, for a claim that OPENS with the subject. **Derived, never re-spelled**
    /// — a second literal here would be exactly the drift the enum exists to prevent, and the
    /// capitalisation is the only difference. Callers add their own trailing punctuation.
    public static let demoSubjectSentenceInitial: String =
        demoSubject.prefix(1).uppercased() + demoSubject.dropFirst()
}

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
    /// ⭐ AND SINCE #643 IT NAMES WHOSE CHANNELS THEY ARE. "Four body channels shape the
    /// instrument's own timbre while a session runs" is a PRESENT-TENSE claim about a current
    /// reading, and while the demo generator drives it is false — no body is involved. Same
    /// defect the FX headers carried until #641/#642, on the surface that makes the promise
    /// most plainly. The channel list, the tail and the deictic half are byte-identical across
    /// both branches; only the SUBJECT moves, which is what keeps the guard's four-name
    /// assertions running over one shared string.
    ///
    /// ⚠️ REQUIRED ARGUMENT, NO DEFAULT (#431/#440/#443): a defaulted `synthetic:` would let a
    /// new call site render the body claim over a demo session without appearing in any diff.
    public static func alwaysOnSentence(synthetic: Bool) -> String {
        let opening = synthetic
            ? "four channels from " + BioProvenanceCopy.demoSubject + ", shape "
            : "four body channels shape "
        return "Separately from these routes, "
            + opening
            + "the instrument's own timbre while a session runs: coherence, HRV, heart rate and "
            + "breath phase. Routes here add effect parameters on top."
    }

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
    /// ⭐ #643 gave it the same conditional subject as its sibling, for the same reason and
    /// from the same flag. See `alwaysOnSentence` — the argument is there, once.
    public static func bioPanelSentence(synthetic: Bool) -> String {
        let opening = synthetic
            ? "Four channels from " + BioProvenanceCopy.demoSubject + ", shape "
            : "Four body channels shape "
        return opening
            + "the instrument's own timbre while a session runs: coherence, HRV, heart rate and "
            + "breath phase — the four rows below. To add your own routes onto effect parameters, "
            + "open Effects › All parameters."
    }

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
    /// says "Always on — body → timbre" (conditional since #641 — "Always on — simulated demo
    /// → timbre" while the demo generator drives). That is the same ambiguity #497/#498 removed, one
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
            // `isSynthetic: false` and not "unknown": with no frame the row renders "—" and
            // asserts nothing about a body, so there is no fabrication to mark. The three-state
            // encoding the CROSS-PROCESS payloads use (`BioVitals.synthetic`, `BioPeek`) exists
            // because a WRITER may not have said; here the reader holds the frame itself.
            return AlwaysOnBioReading(value: 0.5, isMeasured: false, isHeld: false,
                                      isSynthetic: false)
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
                                  isHeld: measured && !usable,
                                  // Asked of the FRAME, exactly like `value` and `isMeasured` —
                                  // the row never reads the bus itself. ⛔ The first draft said
                                  // "all FOUR facts come from one snapshot and cannot describe
                                  // two different instants"; `isHeld` also depends on `now`,
                                  // read at draw time, and this file's own row documents a
                                  // bounded ~1 s lag against `usableBio()`. Three of four.
                                  // ⭐ Migrated to `BioSource.isSynthetic` in #641's review
                                  // pass. The FX section HEADER above these rows asks the same
                                  // question of the same frame; while this said `== .fallback`
                                  // and the header said `.isSynthetic`, the two agreed only
                                  // because the property IS that comparison — one edit apart
                                  // from diverging inside one section (#416). This is exactly
                                  // the "old code gets converted when its own file is next
                                  // opened for a real reason" the property's doc asks for.
                                  isSynthetic: frame.source.isSynthetic)
    }
}

/// What one always-on channel shows at a moment in time — the FOUR facts that must travel
/// together, because any three of them read as something the fourth contradicts
/// (#498, #500, #634).
///
/// ⛔ This headline said "three" for the length of one review cycle after `isSynthetic` landed,
/// with the correction sitting thirty lines below inside the new field's own doc. That is the
/// root CLAUDE.md lesson in miniature — *die Überschrift ist Teil der Behauptung* — and the
/// summary line is the one a reader trusts without scrolling.
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
    /// Whether the frame came from the DEMO generator (`.fallback`) rather than a body (#634).
    ///
    /// ⭐ WHY A FOURTH FACT, on a type whose doc says three "must travel together". The first
    /// three answer *is this number real, and is it still arriving* — both questions ABOUT A
    /// MEASUREMENT. None of them can distinguish a measurement from a fabrication, because
    /// `isMeasured` asks the frame's own `hasMeasured…` gates, which are tests on the NUMBER,
    /// never on its origin. `BioSimulator` satisfies every one of them by construction, so
    /// under Simulation all four channels reported `isMeasured == true`, drew a full-opacity
    /// accent bar, and told VoiceOver "Coherence at 62 percent" — directly beneath the panel
    /// sentence that promises "Four BODY channels shape the instrument's own timbre".
    ///
    /// ⛔ AND `isHeld` IS NOT A NEAR-MISS FOR IT. A demo frame is FRESH: it arrives about once
    /// a second, so `isHeld` is false the whole time. The one fact that would have hinted at
    /// something is the one the demo never trips.
    ///
    /// This completes on the always-on rows the law #627/#629/#632 built on the strip, the
    /// header pill, the metric sheet, the Live-Colabo rows, the widget and the watch.
    public let isSynthetic: Bool

    /// ⚠️ `isSynthetic` has NO DEFAULT, deliberately (#431/#440/#443): a defaulted argument
    /// that no call site writes appears in no diff, and this type has exactly two production
    /// construction sites — both in `reading(in:now:)` a few lines up. Requiring it is what
    /// made the compiler point at both.
    public init(value: Float, isMeasured: Bool, isHeld: Bool, isSynthetic: Bool) {
        self.value = value
        self.isMeasured = isMeasured
        self.isHeld = isHeld
        self.isSynthetic = isSynthetic
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
    /// ⭐ #640 MADE THE SUBJECT AN ARGUMENT, and the argument is REQUIRED rather than defaulted
    /// (#431/#440/#443: a defaulted parameter no call site writes appears in no diff, so the
    /// next surface that renders this line would silently inherit the body claim). The demo
    /// generator drives the same four channels through the same `applyBioReactive` anchors —
    /// the MECHANISM is identical, so the second half of the sentence is unchanged. What is
    /// false under the demo is only the SUBJECT: it is not your body doing it.
    ///
    /// ⚠️ THE REAL-BODY STRING IS BYTE-IDENTICAL to what shipped before this slice, and that is
    /// deliberate: `TheBodyShapedRowsAreNamedOnceTests` pins the row names inside it character
    /// for character, and the ordinary path must not pay for the demo path's honesty.
    public static func soundPanelSentence(synthetic: Bool) -> String {
        let rows = shapedByTheBody.flatMap(\.soundPanelRows)
        let subject = synthetic
            ? BioProvenanceCopy.demoSubjectSentenceInitial + ","
            : "Your body"
        let list: String
        switch rows.count {
        case 0:  return synthetic
            ? "The simulated demo source is not shaping any control on this panel right now."
            : "Your body is not shaping any control on this panel right now."
        case 1:  list = rows[0]
        default: list = rows.dropLast().joined(separator: ", ") + " and " + (rows.last ?? "")
        }
        return "\(subject) also shapes this sound while a session runs: \(list) move around the "
            + "values you set here. Open Bio to watch the four channels doing it."
    }
}

/// The two `bioPanel` rows' spoken hints and captions, with their subject named (#648).
///
/// ⛔ BOTH ROWS DISCRIMINATED ON ONE AXIS AND NOT ON THE SOURCE. `BreathVoiceRow` already
/// branched on whether breath was measured, and `AutoModeRow` on whether a source was running —
/// so each looked carefully written, and each then said "your body" over the demo generator.
/// Under Simulation `usableBio()` is non-nil, so `AutoModeRow`'s enabled branch renders and
/// promises to steer the mood "toward your measured coherence, HRV and heart rate". A row that
/// conditions on one thing reads as conditioned on everything, which is why this class survived
/// five slices of the same family.
///
/// ⭐ NEITHER ROW NEEDS A NEW READ. Both already hold `EngineBus` and already call
/// `usableBio()` exactly once; the frame they already had now feeds the hint too, where the
/// hint used to be a fixed string. So both rows gain honesty and no churn.
/// ⛔ The first draft of this paragraph said "each row ends up with ONE call where it had two"
/// and cited #646's straddle. Measured on the parent: each row made exactly ONE call already.
/// There was no straddle here to close. Carrying the previous slice's lesson into a place it
/// does not fit is the same error class this family keeps correcting in its user-facing copy —
/// a mechanism has to be measured, not recognised.
///
/// ⚠️ COMPOSED FROM A SHARED SUBJECT, NOT ENUMERATED. Breath-measured × source is four
/// combinations and heart/coherence × source is two; writing six literals is how two of them
/// drift. Only the SUBJECT is shared — never a whole sentence, which is the collapse #634b had
/// to retract.
///
/// ⭐ THE REGISTERED MIGRATION IS DONE (#649) — and the register that carried it was WRONG
/// TWICE, which is why the retraction stays instead of the note being deleted. It said "SIX
/// code sites"; a driven count found **TEN**. It said "only FOUR are verbatim-substitutable";
/// driven against every pair, only **TWO** are — nine of the ten real-body branches do not
/// contain the phrase at all (they say "your pulse", "four body channels", "your measured body
/// state"), so substituting a shared subject there would have forced the FOUNDER'S wording to
/// change shape. That is the over-correction this family forbids, and a register claiming four
/// would have invited it. **The hoist that WAS right is the other direction:** every DEMO
/// branch now renders `BioProvenanceCopy.demoSubject`, and every real-body branch is untouched
/// and byte-identical. ⚠️ The paragraphs below are kept verbatim as the record of what the
/// register claimed before it was measured; read them as history, not as instructions.
///
/// ⚠️ MIGRATION REGISTERED, DELIBERATELY NOT DONE HERE — for SLICE DISCIPLINE, and that is the
/// whole reason. ⛔ An earlier version said "guards pin those literals verbatim, so a migration
/// must move the guards in the same commit (#456)", and a reviewer DROVE it false: every
/// assertion over those sites is on the RENDERED OUTPUT of a pure function, which a
/// `subject(synthetic:)` migration leaves byte-identical. The only verbatim SOURCE pins in the
/// bundle are over the prefix and section-head forms, which these sites do not use. The law
/// broken was this repo's own: *a "do not do X" note whose stated reason is checkable and false
/// is worse than none — the next session refutes it in one grep and does X.*
/// ⚠️ SIX code sites, not seven, and only FOUR are verbatim-substitutable: `AutomationStatus`
/// carries a DIFFERENT sentence ("…not automation and not your body") and
/// `BioShapedParameter.soundPanelSentence` is sentence-INITIAL and capitalised, so both need a
/// transform rather than a substitution. The seventh in the register is a doc comment — the
/// same prose-corrupts-its-own-count defect as the retracted recipe below.
/// ⛔ A `git grep` RECIPE STOOD HERE AND WAS WRONG THE MOMENT IT WAS WRITTEN — it claimed this
/// file held three hits, and the recipe LINE ITSELF matched, so the true count was four the
/// instant the comment existed (two before the commit). It also missed that one of the hits it
/// counted is the DEFINITION below, not an un-migrated site, and that `BioShapedParameter`
/// spells the capitalised variant, which the quoted needle never matches. This is CLAUDE.md's
/// `EchoelModalBank` lesson verbatim: *a note that QUOTES a grep ages faster than one that
/// states a fact, because every comment written about the thing corrupts its own evidence.*
/// ⛔ "THREE FORMS, THREE JOBS" STOOD HERE AND IT WAS A DIFFERENT THREE FROM THE DOCUMENTED
/// ONE. The census spelled identically in `AlwaysOnBioRow`, `BioMetricInfo` and `EchoelFXView`
/// is: element LABEL (`"Bio source: simulated demo, not your body"` — strip · widget · watch) ·
/// spoken PREFIX (`"Simulated demo, "`) · section HEAD (`"demo values, not your body"`). I kept
/// the first two and silently substituted "mid-sentence subject" for the third — which makes
/// this helper a de-facto FOURTH spelling while claiming to be one of three. Stated openly
/// instead: **this IS a fourth form**, and it earns its place because a subject that continues
/// into a subordinate clause is a grammatical job the other three cannot do (the label ends a
/// sentence, the prefix starts one, the head names a section). Collapsing any of the four is
/// #634b. ⚠️ The guard's form-ban therefore covers three spellings, not two — the section head
/// was unguarded while this comment claimed completeness.
public enum BioPanelRowCopy {

    /// The mid-sentence subject of a claim about whose reading drives something.
    static func subject(synthetic: Bool) -> String {
        synthetic ? BioProvenanceCopy.demoSubject : "your body"
    }

    /// `BreathVoiceRow`'s spoken hint. Describes what ARMING will do, so it is answerable even
    /// with nothing measured — the tone still sounds, its colour just will not move.
    ///
    /// ⚠️ NO TERMINAL FULL STOP on any of the three, matching the two shipped hints this slice
    /// replaced and every other `.accessibilityHint` in the app. The nil branch carried one for
    /// a review pass — three spoken strings on one control under two conventions.
    public static func breathVoiceHint(for frame: BioSampleFrame?) -> String {
        guard let frame else {
            return "Sounds a held tone. Nothing is measured yet, so its colour will not move"
        }
        // ⭐ ONE EXPRESSION, TWO STATES. Both branches said "Sounds a held tone whose colour
        // follows " and differed only in the subject, so the shared half is written once. This
        // is also what finally gives `subject(synthetic:)` a production caller — #648 created
        // it and wired it nowhere, which is dead code the repo's own rules forbid shipping.
        return "Sounds a held tone whose colour follows " + subject(synthetic: frame.source.isSynthetic)
    }

    /// `BreathVoiceRow`'s caption. Two axes: whose reading, and whether breath is arriving.
    public static func breathVoiceCaption(for frame: BioSampleFrame?) -> String {
        let head: String
        switch frame?.source.isSynthetic {
        case false: head = "A held tone whose colour follows your heart and coherence."
        case true:  head = "A held tone whose colour follows the heart and coherence of "
                         + BioProvenanceCopy.demoSubject + "."
        default:    head = "A held tone whose colour will follow a heart and coherence once "
                         + "something is measured."
        }
        guard frame?.hasMeasuredBreath == true else {
            return head + " No breathing measured yet — once it is, the inhale and exhale take "
                + "over the note."
        }
        guard frame?.source.isSynthetic == true else {
            return head + " Your inhale opens it, your exhale closes it."
        }
        return head + " Its simulated inhale opens it, its exhale closes it."
    }

    /// `AutoModeRow`'s spoken hint. The control is disabled without a source, but VoiceOver
    /// still reads a hint on a disabled control, so the nil state gets its own sentence.
    public static func autoModeHint(for frame: BioSampleFrame?) -> String {
        guard let frame else { return "Needs a running bio source before it can steer anything" }
        guard frame.source.isSynthetic else {
            return "Slowly steers the mood dials toward your measured body state"
        }
        return "Slowly steers the mood dials toward the measured state of "
            + BioProvenanceCopy.demoSubject
    }

    /// `AutoModeRow`'s caption, all three states.
    ///
    /// ⛔ THIS TOOK A `Bool` FOR ONE REVIEW PASS, justified as "reachable only with a frame in
    /// hand, so two states, not three" — which is true of TODAY'S caller and is precisely the
    /// argument #644 lost. `BioMetric.originNote(for:)` records that lesson in a file this slice
    /// reads: a `Bool` cannot separate "a real body" from "nothing measured", and the collapse
    /// ships as "your body" over an empty reading. Its three siblings here already take the
    /// frame; one 90-line enum with two conventions for one decision is how the next caller
    /// picks the wrong one. The nil sentence also stops being stranded in the view, pinned only
    /// by a source scan while everything else is driven.
    ///
    /// ⚠️ Names ONLY channels a producer actually feeds (coherence · HRV · heart rate). #496
    /// struck breath depth, LF/HF and any "trend"; this sentence must not grow them back.
    public static func autoModeCaption(for frame: BioSampleFrame?) -> String {
        guard let frame else {
            return "Needs a running bio source — choose one with the Bio source control above."
        }
        let head = frame.source.isSynthetic
            ? "Gently steers mood toward the measured coherence, HRV and heart rate of "
                + BioProvenanceCopy.demoSubject + ", when that reading is clearly settled "
                + "or clearly driving"
            : "Gently steers mood toward your measured coherence, HRV and heart rate when your "
                + "body is clearly settled or clearly driving"
        return head + " — over bars, not beats. Your own edits keep priority — edit a steered "
            + "dial and Auto lets that dial go for the rest of this session (switch Auto off "
            + "and on to hand it back)."
    }
}
