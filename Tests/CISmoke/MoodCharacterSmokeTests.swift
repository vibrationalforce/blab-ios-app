// MoodCharacterSmokeTests.swift
// Echoel — the FACTORY mood library stays a set of distinct characters as it grows
// (founder 2026-07-29, "noch mehr optionen … sei creativ"), in the BLOCKING bundle.
//
// WHY THIS EARNS A GATE. Adding presets is the easiest change in this repo to make and the
// easiest to get quietly wrong: a preset is eight numbers, nothing about it can fail to
// compile, and a new one that happens to sit next to an existing one produces a LONGER menu
// that sounds the SAME. That is not hypothetical — it is the complaint that produced #81
// ("erst individuell → dann alles gleich") and #125. The compiler cannot see it, and a
// reviewer reading a diff of eight float literals cannot see it either.
//
// THE MISTAKE THIS FILE MADE FIRST, kept here because it is the interesting part. The
// original version measured plain Euclidean distance over all 8 dimensions and passed. It
// was wrong: `darkness` and `romance` are not read continuously by the composer. Their ONLY
// reads in the entire engine are `mood.darkness > 0.6` (`BioComposer.composeHarmonic`,
// octave shift) and `mood.romance > 0.5` (adds the 7th) — verified by grepping every `.darkness`
// and `.romance` in `Sources/`. So two moods can differ by 0.43 of darkness and generate
// identical notes, and the first draft of "Glass" was exactly that: a clone of "Hypnotic"
// wearing a different darkness number, sailing through the test written to catch it.
//
// Hence two measures, deliberately not one:
//   · RAW — the parameters are genuinely spread. Catches a copied preset with one edit.
//   · EFFECTIVE — spread on what the engine ACTS on. Catches the clone the raw one misses.
// Both bars are calibrated to the library that already shipped, so neither imposes a spacing
// the curated moods themselves would fail.
//
// SCOPE, stated because the header would otherwise overclaim: this covers `MoodPreset.factory`
// ONLY. `MoodPreset.community` renders in the same menu and is NOT gated — the bundled
// `aurora-calm.json` sits well inside both bars of factory `Calm`. Community moods are
// curated by hand on the way in; that is a different process, not a hole this test plugs.
//
// And the honest limit: distance is a stand-in for "sounds different", not a measurement of
// it. Read a pass as "no accidental clone", never as "these sound different" — that stays a
// device judgement.

import XCTest
@testable import Echoelmusic

final class MoodCharacterSmokeTests: XCTestCase {

    // MARK: - Bars (calibrated to the shipped set, see the notes on each)

    /// RAW bar. The tightest pair among the 8 shipped moods is Calm ↔ Dreamy at 0.4123, so
    /// 0.40 says "no closer than the set already was" without retro-breaking it. A floor,
    /// not a target — raising it later means re-spacing moods people have already saved.
    private let minimumRawSeparation: Float = 0.40

    /// EFFECTIVE bar, measured with `darkness`/`romance` collapsed to the thresholds the
    /// composer reads. The shipped floor here is Dreamy ↔ Romantic at 0.2557 — much tighter
    /// than the raw floor, which is itself the point: two of the eight dials are nearly
    /// inert, so real spacing has to come from the other six.
    private let minimumEffectiveSeparation: Float = 0.25

    // MARK: - Metrics

    /// The 8 dimensions as written, in a fixed order.
    private func rawDims(_ m: MoodPreset) -> [Float] {
        [m.liveliness, m.darkness, m.tension, m.romance,
         m.weird, m.virtuosity, m.syncopation, m.humanize]
    }

    /// The 8 dimensions as the COMPOSER sees them: `darkness` and `romance` replaced by the
    /// booleans it actually branches on. Everything else passes through untouched.
    ///
    /// ⚠️ If either threshold in `BioComposer.composeHarmonic` moves, this must move with it,
    /// or the gate goes back to measuring a number nobody hears.
    private func effectiveDims(_ m: MoodPreset) -> [Float] {
        [m.liveliness,
         m.darkness > 0.6 ? 1 : 0,      // BioComposer: octave shift, strict >
         m.tension,
         m.romance > 0.5 ? 1 : 0,       // BioComposer: adds the 7th, strict >
         m.weird, m.virtuosity, m.syncopation, m.humanize]
    }

    private func distance(_ a: [Float], _ b: [Float]) -> Float {
        zip(a, b)
            .reduce(Float(0)) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
            .squareRoot()
    }

    private func assertAllPairsSeparated(
        by bar: Float,
        using dims: (MoodPreset) -> [Float],
        measure: String
    ) {
        let all = MoodPreset.factory
        for i in all.indices {
            for j in all.indices where j > i {
                let d = distance(dims(all[i]), dims(all[j]))
                XCTAssertGreaterThanOrEqual(
                    d, bar,
                    """
                    "\(all[i].name)" and "\(all[j].name)" are only \(d) apart (\(measure)). \
                    Two menu entries that produce near-identical takes make the library \
                    longer without making it richer — move one of them further out rather \
                    than lowering this bar.
                    """)
            }
        }
    }

    // MARK: - The two that cannot be seen in a diff

    /// Raw spread: no preset is a copy of another with one number nudged.
    func testNoTwoFactoryMoodsAreNearDuplicatesInParameterSpace() {
        assertAllPairsSeparated(by: minimumRawSeparation, using: rawDims, measure: "raw")
    }

    /// THE ONE THAT ACTUALLY GUARDS THE EAR. Passing the raw bar while failing this one is
    /// precisely the "Glass was Hypnotic" defect — distinct on paper, identical in the notes.
    func testNoTwoFactoryMoodsCollapseOntoEachOtherInTheComposer() {
        assertAllPairsSeparated(by: minimumEffectiveSeparation,
                                using: effectiveDims, measure: "as the composer reads it")
    }

    /// The two measures must not be silently identical — if a refactor ever made
    /// `effectiveDims` return `rawDims`, both tests above would still pass and the real guard
    /// would be gone with nothing to show for it.
    func testTheEffectiveMeasureReallyDiffersFromTheRawOne() {
        let belowBothThresholds = MoodPreset(name: "a", darkness: 0.10, romance: 0.10)
        let alsoBelowBoth = MoodPreset(name: "b", darkness: 0.55, romance: 0.45)
        XCTAssertGreaterThan(distance(rawDims(belowBothThresholds), rawDims(alsoBelowBoth)), 0.4,
                             "these differ a lot on paper")
        XCTAssertEqual(distance(effectiveDims(belowBothThresholds), effectiveDims(alsoBelowBoth)), 0,
                       accuracy: 1e-6,
                       "…and not at all in the notes — that gap is the whole point of this file")
    }

    // MARK: - The library itself

    /// The characters the founder asked for are there. "Vast" carries the ask he wrote as
    /// "Space": in this app that word already names the spatial output stage (ADM-OSC,
    /// `ImmersiveStageView`) and is spoken for again by the coming sample engine, so the mood
    /// says the same thing about the NOTES under a name that cannot be misread. The original
    /// word survives as a searchable tag, which is where someone typing "space" will look.
    func testTheRequestedCharactersExist() {
        let names = Set(MoodPreset.factory.map { $0.name })
        for wanted in ["Vast", "Meditative", "Trippy", "Eclectic"] {
            XCTAssertTrue(names.contains(wanted), "the mood library lost \"\(wanted)\"")
        }
        XCTAssertTrue(MoodPreset.factory.contains { $0.matches("space") },
                      "the founder's own word must still find the mood it named")
        // Deliberately loose. A hard `>= 15` would turn the next "remove one" into a red
        // blocking gate — a founder decision failing a quality check. This only asserts the
        // set never quietly collapses back to a handful.
        XCTAssertGreaterThanOrEqual(MoodPreset.factory.count, 12,
                                    "the curated set should stay browsable")
    }

    /// NOT A STYLE RULE — a decision pinned where it will be read. "ARP" was in the founder's
    /// list of wanted moods, and it is the one item deliberately not built as one: an
    /// arpeggiator is a note GENERATOR (rate, direction, octave span, gate) and no dimension
    /// here can produce it, so a mood called "Arp" would be a control that lies about what it
    /// does. If this fails, the fix is not to delete it — it is to give the arp a real
    /// surface (`BreathArp` is already the engine) and let moods describe note character only.
    ///
    /// Matched on the whole name, not as a substring: "Harp" and "Sharp" are perfectly good
    /// mood names and must not fail a blocking gate with an accusation about arpeggiators.
    func testNoMoodPretendsToBeAnArpeggiator() {
        for m in MoodPreset.factory {
            let words = m.name.lowercased().split { !$0.isLetter }.map(String.init)
            XCTAssertFalse(words.contains("arp") || words.contains("arpeggiator"),
                           """
                           "\(m.name)" promises an arpeggiator, but MoodProfile has no \
                           dimension that generates one — give the arp its own control \
                           instead of a preset that cannot deliver it.
                           """)
        }
    }

    /// Ids must be unique AND stable: they key favourites and recents, so a duplicate or a
    /// malformed literal silently detaches a user's starred mood from the mood itself.
    func testFactoryIdsStayUniqueAndNonNil() {
        let ids = MoodPreset.factory.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count, "two moods share an id")
        let zero = UUID(uuid: (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0))
        XCTAssertFalse(ids.contains(zero),
                       "a mood fell back to the all-zero id — its UUID literal is malformed")
    }

    /// Every dimension in range, and nothing parked on the `darkness > 0.6` cliff. A mood
    /// written as exactly 0.60 reads as undecided, and flips a whole octave the day someone
    /// changes `>` to `>=`.
    func testEveryDimensionStaysInRangeAndOffTheOctaveCliff() {
        for m in MoodPreset.factory {
            for (index, v) in rawDims(m).enumerated() {
                XCTAssertTrue((0...1).contains(v),
                              "\(m.name) dimension \(index) is \(v), outside 0…1")
            }
            XCTAssertNotEqual(m.darkness, 0.6, accuracy: 0.005,
                              "\(m.name) sits on the darkness threshold — commit to a side")
            XCTAssertFalse(m.name.isEmpty)
            XCTAssertFalse(m.tags.isEmpty, "\(m.name) needs tags — search matches on them")
        }
    }
}
