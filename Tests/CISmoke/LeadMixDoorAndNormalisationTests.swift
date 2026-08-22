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
// ⛔ AND THE "EITHER DIRECTION" ABOVE WAS FALSE FOR THIS FILE UNTIL #711 — measured in the review
// that added the cross-reference (#710 finding 1), repaired here one cycle later.
//   · WAS: raw source, no comment stripping, and a bare `contains("normaliseDoorlessLeadMix()")`.
//     That token appears FOUR times in `EchoelStudioView` — the call, the declaration, and two
//     prose comments. Deleting the CALL left three, so the pairing still read "normalisation
//     present" and the assertion PASSED. Simulated on a tree with the call removed: green. The
//     direction this file names first was the one it could not detect.
//   · IS: comments blanked (`codeOf`), the declaration excluded by its `func` keyword, and a
//     #367 anchor on the door needle's spelling. Driven against four trees, the same DISCIPLINE
//     as the donut twin but not the same set (⛔ "same four trees" is what this said, and the
//     twin's fourth is a `//` comment quoting the assignment, which is not one of these —
//     #712 review finding 5): real → green · call deleted → red · door restored with the
//     normalisation kept → red · both together → green.
//
// ⭐ AND #711 REPAIRED TWO DIRECTIONS, NOT ONE — the commit claimed only the first, which
// under-sells it (#712 review finding 7). Under the old raw logic the CORRECT re-door (fader
// restored AND the call deleted) was **RED**, because the two prose comments kept the
// normalisation side reading `true`. Its failure text then said "Delete `normaliseDoorlessLeadMix()`
// and the line that calls it" — which that commit had just done. An unfixable red on a correct
// tree is a #364 violation, and it sat in the guard that exists to permit exactly that change.
// ⭐ The lesson is not "raw text is sloppy". It is that a guard whose needle also matches the
// PROSE ABOUT ITSELF gets quieter the more carefully it is documented — this file gained its two
// explanatory comments honestly, and each one weakened it. The donut twin (#709) was written
// from this file's shape and hit the same wall one file over, which is how it was found at all.
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

    /// EXACTLY ONE of the two must be present. The PAIRING is one assertion rather than two so
    /// its failure message can state which side broke — a pair of independent assertions would
    /// report "missing normalisation" for a commit that legitimately restored the door, and send
    /// the next session to add back the very thing it should delete. (⛔ This said "written as
    /// one assertion" flat, and since #711 the method holds TWO: the #367 anchor comes first and
    /// fails under the same test name. The one-assertion rule is about the pairing, not the
    /// method — #712 review finding 8.)
    func testTheLeadFaderAndItsNormalisationAreMutuallyExclusive() throws {
        let code = try codeOf(Self.studio)

        // #367 anchor, and the one this claim lacked: the door needle has ZERO occurrences today
        // (that is the point — the door is gone), so nothing else can show its spelling is still
        // the live one. The witness is the two surviving `MixerStore` ROLE LEVELS — `\\.bass` and
        // `\\.pad`. Not "the remaining mix fields": the board has five strips, and Field, Click and
        // Voice each bind a different way, so this counts a narrower thing than its name suggests.
        //
        // ⚠️ WHAT IT DETECTS AND WHAT IT CANNOT (#712 review findings 3 and 4). It detects that
        // the needle's SPELLING has gone stale. It cannot force a restored fader to use that
        // spelling: a Lead field written `mixBinding(\\MixerStore.lead)` leaves this anchor happy
        // and `hasDoor` false, so the pairing would read green on a broken tree. That gap is
        // named rather than papered over — closing it means a semantic scan, not a longer needle.
        //
        // ⚠️ THRESHOLD IS 1, NOT 2, and the difference is a real tree. Today the count is exactly
        // 2, so `>= 2` had ZERO headroom: the founder call that removes one more role level — the
        // same shape as #255, which removed Lead — would turn this RED on a correct tree. One
        // surviving occurrence still proves the idiom is live, which is all this anchor claims.
        let idiom = code.components(separatedBy: "mixBinding(\\.").count - 1
        XCTAssertGreaterThanOrEqual(idiom, 1, """
            `mixBinding(\\.` appears \(idiom) time(s) in code — the house spelling for a mix ROLE \
            LEVEL is gone. The door needle below checks a form the file no longer uses, so a \
            restored Lead fader would not be spelled that way either and this pairing would sit \
            green through it. Re-derive the needle from how the surviving fields are written.
            """)

        let hasDoor = code.contains("mixBinding(\\.lead)")
        // The declaration carries the same token; the obligation is the CALL, so exclude it —
        // anchored on `func`, not on `private`, so dropping the access modifier cannot turn the
        // declaration into a phantom call site.
        let hasNormalisation = code
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .contains { line in
                line.contains("normaliseDoorlessLeadMix()")
                    && !line.contains("func normaliseDoorlessLeadMix")
            }

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

    /// `source(_:)` with comments blanked. Claim 1 needs this and the others do not: its
    /// normalisation needle is a bare token that ALSO appears in two prose comments in
    /// `EchoelStudioView`, which is why the raw form could not fail for its own stated reason.
    ///
    /// ⚠️ TWO RESIDUAL HOLES, named here so the cover is not overread (#712 findings 6 and 9).
    /// `SourceText.codeOnly` does NOT blank the body of a `"""` literal — its own header says so
    /// and says why the omission is deliberate; `EchoelStudioView` already writes such literals,
    /// so the token placed inside one would read as a live call. And the declaration exclusion
    /// matches `func normaliseDoorlessLeadMix` on ONE line: splitting `func` from the name
    /// defeats it. Both are unlikely shapes, neither is worth code today, and both would be
    /// invisible if this block did not exist.
    private func codeOf(_ path: String) throws -> String {
        SourceText.codeOnly(try source(path))
    }

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
