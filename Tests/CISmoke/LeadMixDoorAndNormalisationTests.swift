// LeadMixDoorAndNormalisationTests.swift
// Echoel — #255. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ THE ONE PAIRING THIS FILE EXISTS FOR: `MixerStore.lead` is PERSISTED (`"mixer.lead"`), and
// #255 deleted the Mix board's "Lead" field — its only door — on the founder's call ("Lead kann
// raus aus dem Mix"). A persisted value with no door is not neutral: it freezes at whatever the
// player last dialled, and `MixerStore.combined` multiplies it into the velocity the moment a
// genre produces a `.lead`-role note again (#243/#196). An install sitting at 0.30 would then
// attenuate that new lead by 70 %, silently, with nothing able to undo it.
//
// So the removal is only half a slice. The other half is `normaliseDoorlessLeadMix()`, the same
// shape as `normaliseUnreachableDonutMode()` (#227) one store down. This file pins that the two
// halves can never drift apart — in EITHER direction:
//
// ⭐ AND THAT SENTENCE DESCRIBED ONLY THIS STORE. The donut twin it names had NO pairing guard of
// its own — measured, not remembered — until `VisualFineTuneReflowsTests`
// `.testTheDonutNormalisationExpiresExactlyWhenTheDoorReturns`, which is written from this file's
// shape. That is why the cross-reference is worth carrying: a guard saying "same shape as X" reads
// as a standing claim that X is guarded too, and nobody had checked.
// (⛔ The first draft said "for two months". Unprovable here: this clone is shallow and `545b19e`
// is its graft root, so `git log -S` reports BOTH files as first appearing in that one deploy
// commit. The present state is measurable; the duration is not — the `presetRow` lesson in
// CLAUDE.md, hit again one file over.)
//
//   · door removed, normalisation missing  → the stale-value trap above
//   · door restored, normalisation left in → every launch stamps the fader back to unity, so the
//     control moves, persists, and is silently undone on the next start. That is a lying control
//     by this repo's own #135/#164/#227 standard — the exact class #255 was meant to remove.
//
// ⚠️ WHAT THIS FILE CANNOT REACH, so the coverage is not overread: it cannot instantiate
// `EchoelStudioView` (the members are `private`), cannot prove the field is visually gone, and
// cannot prove the normalisation actually runs at launch. It reads SOURCE TEXT for the two
// tokens and pins their exclusivity. That is weaker than a behavioural test and stronger than
// nothing — and it is the only level at which a `private` view member is checkable from here.

import Foundation
import XCTest
@testable import Echoelmusic

final class LeadMixDoorAndNormalisationTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// EXACTLY ONE of the two must be present. Written as one assertion rather than two so the
    /// failure message can state which side of the pairing broke — a pair of independent
    /// assertions would report "missing normalisation" for a commit that legitimately restored
    /// the door, and send the next session to add back the very thing it should delete.
    func testTheLeadFaderAndItsNormalisationAreMutuallyExclusive() throws {
        let code = try source(Self.studio)
        let hasDoor = code.contains("mixBinding(\\.lead)")
        let hasNormalisation = code.contains("normaliseDoorlessLeadMix()")

        XCTAssertNotEqual(hasDoor, hasNormalisation, """
            The Lead mix door and its launch normalisation are out of step. \
            door=\(hasDoor) normalisation=\(hasNormalisation).
            Both present: the fader writes `mixer.lead`, and the next launch stamps it back to \
            unity — a control that moves, persists and is silently undone. Delete \
            `normaliseDoorlessLeadMix()` and the line that calls it, in the SAME commit that \
            restores the door (its own doc comment says so).
            Neither present: `mixer.lead` is persisted with no door and no normalisation, so a \
            value dialled before #255 is frozen forever and will attenuate the first lead a \
            future genre produces (`MixerStore.combined`).
            """)
    }

    /// The normalisation can only clear a value it can still find. Same reason the donut guard
    /// pins its key (#227) — a rename here looks harmless because the default is where we want
    /// everyone, but it strands exactly the installs the normalisation exists for.
    func testThePersistedLeadKeyIsStillTheOneOlderInstallsWroteTo() throws {
        let store = try source("Sources/Echoelmusic/Core/MixerStore.swift")
        XCTAssertTrue(store.contains("\"mixer.lead\""), """
            The `mixer.lead` key moved. An install that stored e.g. 0.30 before #255 can no \
            longer be normalised, and no control in the UI can reach that value either.
            """)
    }

    /// Unity must stay the value the normalisation writes AND the value a never-set install
    /// reads, or the two disagree and a fresh install differs from a normalised one.
    ///
    /// ⛔ `@MainActor` IS LOAD-BEARING, and its absence is what made the first version of this
    /// file fail the blocking gate (`30677811229`). `MixerStore` is `@MainActor @Observable`, so
    /// constructing it — and reading `.lead` — from a nonisolated test method is an isolation
    /// error under `-swift-version 6`. Only THIS method touches the store; the two source-text
    /// tests above stay nonisolated deliberately, rather than annotating the whole class, so the
    /// isolation says exactly which assertion needs the main actor. The sibling pattern is
    /// `AutosaveSlotTests` / `FXSpreadRowTests`, which annotate at class level because every one
    /// of their methods touches an isolated type.
    ///
    /// And the wider lesson, because it cost a red gate: **a green Xcode Compile Check proves
    /// nothing about a new test file.** That gate runs `xcodebuild build` on a scheme whose
    /// build targets are `Sources/` only — `Tests/CISmoke` compiles solely in the CI/CD
    /// Pipeline. CLAUDE.md says this in full; I pushed before it had reported.
    @MainActor
    func testAnUnsetLeadReadsAsUnity() throws {
        // `try XCTUnwrap`, not `!` — force-unwrap is banned repo-wide, and a nil suite here
        // would crash the whole bundle instead of failing one assertion.
        let empty = try XCTUnwrap(
            UserDefaults(suiteName: "echoel.test.leadmix.\(UUID().uuidString)"),
            "could not create an isolated defaults suite")
        let store = MixerStore(defaults: empty)
        XCTAssertEqual(store.lead, 1.0, accuracy: 0.0001,
                       "a never-set lead level must read as unity — the genre's own balance")
    }

    // MARK: - helpers

    private func source(_ path: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                Source tree not reachable from the test bundle — skipping rather than reporting \
                a green this file did not earn.
                """)
        }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
