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
    func testAnUnsetLeadReadsAsUnity() {
        let empty = UserDefaults(suiteName: "echoel.test.leadmix.\(UUID().uuidString)")!
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
