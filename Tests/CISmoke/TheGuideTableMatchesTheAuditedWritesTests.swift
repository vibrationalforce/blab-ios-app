// TheGuideTableMatchesTheAuditedWritesTests.swift
// Echoel — #638: the bio guide's four-row body→sound table disagreed with the app's own
// audited truth table on THREE of its four rows, and both are rendered to the same user.
//
// WHAT THIS GUARDS. `BioSoundMapping.all` is the static map behind "How your body shapes the
// sound" in `BioMetricsGuideView` (two doors on the bio strip: the ⓘ and the activity light).
// `AlwaysOnBioChannel.shapedParameters` is the SAME question answered for the always-on rows in
// the Bio panel and the FX sheet, and it was audited against `applyBioReactive` at #546/#560.
// Two spellings of one decision (#416) — and before #638 they disagreed on:
//   · **heartRate** — the guide claimed "quickens the filter sweep". That sweep is the
//     heart-rate LFO DELETED at #331; its tombstone is still in `applyBioReactive` ("AN LFO
//     STOOD HERE AND IS DELETED") and `filterLFORate` has no bio writer at all. The guide was
//     the last surface in the app still selling it. It also OMITTED the live HR → brightness
//     term, so one row managed an over-claim and an under-claim at once.
//   · **breath** — "deeper breathing widens the filter's movement" rides `breathDepth`, which
//     has no producer: both `BioParams` construction sites pass the literal `0.5`. The engine
//     says so at that line — *"must not be claimed as live in any user-facing copy"* — and the
//     copy used the word "deeper", i.e. the exact channel nothing measures.
//   · **hrv** — "Reverb & sense of space", the #546 mapping. That half is pinned by
//     `DisabledReverbIsNotClaimedLiveTests`, which owns the reverb decision; this file does not
//     restate it (#416).
//
// ⛔ AND THE FIRST DRAFT OF THE #638 REPAIR PUT A FOURTH ONE IN. It rewrote HRV's row as "opens
// the filter a little further" — but HRV never touches `filterCutoff`: `targetCutoff` is a
// function of coherence alone, in BOTH branches. HRV moves `brightness`, the spectral-shape
// exponent (`computeShapeAmplitudes` divides each partial by `n^(1.5 − brightness)`). A slice
// correcting a false mapping wrote a new false mapping in the same commit, and the audited
// table two directories away already said `case .hrv: return [.brightness]`. **That is the
// reason this file exists rather than a fifth careful comment.**
//
// KIND (§1): **END-TO-END BEHAVIOUR.** `BioSoundMapping`, `AlwaysOnBioChannel` and
// `BioShapedParameter` are all `public` Foundation-only value types, so this bundle drives the
// real producers and compares them. No source-text scanning, no needles. That the founder READS
// the corrected sentences and finds them clearer is a DEVICE PROBE and stays open.
//
// THE INVARIANT, deliberately one-directional: a guide row may not name a parameter its own
// channel does NOT shape. It is NOT required to name every parameter it does shape — user copy
// legitimately says "swell" where the engine says `amplitude`, and demanding the engine's
// vocabulary would make the guide worse, not truer (#364). Over-claiming is the failure this
// repo keeps paying for; under-claiming in plainer words is good writing.
//
// GRADING (#433 / §3), driven against the parent (64caba2) and this tree:
//   · **2 REGRESSIONS** — `heartRate` and `breath` both contained "filter" on the parent while
//     their channels exclude `filterCutoff`. ONE finding (#486): the table had drifted from the
//     audited one.
//   · **2 COUNTERWEIGHTS** — `coherence` and `hrv` pass on both trees. `coherence` is the row
//     that was always right and is what makes this a comparison rather than a blanket ban;
//     `hrv` passes on the parent only because "reverb" is not a `channelWord`, which is
//     exactly why the reverb decision stays in its own file.
//   · **1 COUNTERWEIGHT** — the id join (four rows, four channels, all found). It is the
//     assertion that stops the loop passing over an empty set (#454).
//   · No stripper: this file reads no source text, so the §2 raw-vs-stripped measurement does
//     not apply. Said explicitly rather than omitted, because every sibling in this family
//     reports one.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheGuideTableMatchesTheAuditedWritesTests: XCTestCase {

    /// The join between the two vocabularies.
    ///
    /// ⚠️ THREE OF FOUR IDS MATCH AND ONE DOES NOT — written out rather than papered over with
    /// a `rawValue` lookup that would silently return nil. `BioSoundMapping` calls the fourth
    /// channel `"breath"`, `AlwaysOnBioChannel` calls it `"breathPhase"`. That is a second small
    /// #416 drift inside the very pair this file exists to reconcile, and it is a finding, not a
    /// detail: a future `Dictionary(uniqueKeysWithValues:)` join keyed on `id` would drop the
    /// breath row and this guard would pass over three of four. Registered here; unifying the
    /// spelling touches persisted-adjacent vocabulary and is its own slice.
    private static let join: [(mappingID: String, channel: AlwaysOnBioChannel)] = [
        ("heartRate", .heartRate),
        ("hrv",       .hrv),
        ("coherence", .coherence),
        ("breath",    .breathPhase),
    ]

    func testTheJoinCoversEveryGuideRow() {
        XCTAssertEqual(Set(BioSoundMapping.all.map(\.id)), Set(Self.join.map(\.mappingID)), """
            The guide's rows and this file's join have drifted apart. Every row must be \
            compared against a channel or the loop below passes over the ones it cannot find \
            — the #454 shape: not a red gate, a guard that is green because it looked at \
            nothing.
            """)
        XCTAssertEqual(Self.join.count, AlwaysOnBioChannel.allCases.count, """
            There are \(AlwaysOnBioChannel.allCases.count) always-on channels and \
            \(Self.join.count) joined rows. If a fifth channel was added, the guide needs a \
            fifth row before this comparison means anything.
            """)
    }

    func testNoRowNamesAParameterItsChannelDoesNotShape() {
        for (id, channel) in Self.join {
            guard let row = BioSoundMapping.all.first(where: { $0.id == id }) else {
                XCTFail("no guide row with id \"\(id)\" — see testTheJoinCoversEveryGuideRow")
                continue
            }
            let shaped = Set(channel.shapedParameters)
            let excluded = BioShapedParameter.allCases.filter { !shaped.contains($0) }
            let copy = "\(row.target) \(row.direction)".lowercased()

            for parameter in excluded {
                XCTAssertFalse(copy.contains(parameter.channelWord), """
                    The guide's "\(row.source)" row names "\(parameter.channelWord)", but \
                    `AlwaysOnBioChannel.\(channel).shapedParameters` does not include \
                    `.\(parameter)` — so the app tells the same user two different things about \
                    the same body signal, in two sheets one chip apart.
                    Row target:    \(row.target)
                    Row direction: \(row.direction)
                    Shaped:        \(shaped.map(\.channelWord).sorted().joined(separator: " · "))
                    If the ENGINE changed, update `shapedParameters` first (it is the audited \
                    one, checked against `applyBioReactive` at #546/#560) and let this guard \
                    pull the copy along. If the COPY is right and the audited table is stale, \
                    say so at `shapedParameters` in the same commit rather than loosening this \
                    assertion — a table that agrees with nothing is what #638 removed.
                    """)
            }
        }
    }

    /// The one-directional half, stated as a test so nobody "fixes" the asymmetry later.
    ///
    /// A row is NOT required to use the engine's word for what it does shape. The breath row
    /// says "swells and settles" where `BioShapedParameter.amplitude.channelWord` says "level",
    /// and that is better copy for a sheet whose whole job is plain language. This asserts only
    /// that every row still says SOMETHING in both fields — the floor, not the vocabulary.
    func testEveryRowStillSaysSomething() {
        for row in BioSoundMapping.all {
            XCTAssertFalse(row.target.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(row.id) has no target label")
            XCTAssertFalse(row.direction.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(row.id) has no direction phrase")
        }
    }
}
