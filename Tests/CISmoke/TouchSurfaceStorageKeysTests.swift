// TouchSurfaceStorageKeysTests.swift
// Echoel — the play surface's persisted settings survive every rename, in the BLOCKING bundle.
//
// A rename is the cheapest change in an app and one of the most dangerous, because the same
// word lives in two places with completely different lifetimes: on screen, where changing it
// costs nothing, and in a PERSISTENCE KEY, where changing it silently discards everything the
// user already dialled in. No error, no warning, no crash — the setting is simply gone and
// reads as a factory default. This repo has paid for that class twice (#163, #170).
//
// Written during the "Field" rename (#223), which moved the visible strings and deliberately
// left the `touch.*` keys alone: the prefix is STORAGE, not vocabulary.
//
// ⚠️ NAMED FOR THE INVARIANT, NOT THE CHANGE. The first version of this file was called
// `FieldRenameSmokeTests` — and it asserts nothing about that rename; its methods would be
// byte-identical had #223 never happened. In six months, when nobody remembers #223, a file
// named for a change but testing an invariant reads as dead weight and gets deleted. This
// name survives the next rename, which is exactly when it is needed most.
//
// HONEST SCOPE, because the first version overclaimed. Roughly six of these assertions are
// genuinely new; the rest is a PROMOTION of coverage that already existed in
// `Tests/EchoelmusicTests/StudioDefaultKeysTests.swift` — which lives in the NON-BLOCKING
// bundle, so it could go red for a day without stopping anything. Promotion is the point, but
// it has a price worth stating: several defaults are now pinned in two files, and a founder
// default change reddens both while only one of them gates.
//
// WHAT THIS STILL CANNOT SEE, and it is the actual #163/#170 shape: a USE-SITE drift. If
// someone edits a view to `@AppStorage("field.level")` and leaves `StudioDefaultKeys` alone,
// this file stays green and the setting is lost. The defence against that is the shared-key
// rule — every `touch.*` key declared in one place and referenced by symbol, never re-typed —
// which is why `touch.patchID` and `touch.showGrid` were promoted out of raw literals in the
// same commit. Two keys living at their use sites was not a detail: they were the two most
// exposed to the very failure this file names, and the first version of it covered neither.

import XCTest
@testable import Echoelmusic

final class TouchSurfaceStorageKeysTests: XCTestCase {

    /// THE ONE THAT MATTERS. Every shared preference behind the play surface, pinned to the
    /// string it has always been stored under.
    ///
    /// ⚠️ If a key rename is ever genuinely wanted, it needs a migration that reads the old
    /// key and writes the new one. Editing the literal is not a migration, and deleting this
    /// test is not one either.
    func testThePlaySurfaceKeepsItsStorageKeys() {
        XCTAssertEqual(StudioDefaultKeys.touchMorphDepth.key, "touch.morphDepth")
        XCTAssertEqual(StudioDefaultKeys.touchSlideVibrato.key, "touch.slideVibrato")
        XCTAssertEqual(StudioDefaultKeys.touchSlideChorus.key, "touch.slideChorus")
        XCTAssertEqual(StudioDefaultKeys.touchGlide.key, "touch.glide")
        XCTAssertEqual(StudioDefaultKeys.touchLevel.key, "touch.level")
        XCTAssertEqual(StudioDefaultKeys.touchLife.key, "touch.life")
        XCTAssertEqual(StudioDefaultKeys.touchSyncStrength.key, "touch.sync.strength")
        XCTAssertEqual(StudioDefaultKeys.touchSyncGrid.key, "touch.sync.grid")
        // The two promoted out of raw `@AppStorage` literals during the rename. `patchID` is
        // the surface's VOICE — the most user-visible thing it persists.
        XCTAssertEqual(StudioDefaultKeys.touchPatchID.key, "touch.patchID")
        XCTAssertEqual(StudioDefaultKeys.touchShowGrid.key, "touch.showGrid")
        // SELF-PLAY (#224). Prefixed `field.*` rather than `touch.*` — deliberately, and it is
        // the one place in this file where a NEW prefix is correct rather than a drift: every
        // key above describes how the surface answers a FINGER, and these describe what it
        // does when there is none. Pinned from the first commit, before any of them are in the
        // wild, because that is the only moment the choice is still free.
        XCTAssertEqual(StudioDefaultKeys.fieldAutoPlayMotion.key, "field.autoPlay.motion")
        XCTAssertEqual(StudioDefaultKeys.fieldAutoPlayDensity.key, "field.autoPlay.density")
        XCTAssertEqual(StudioDefaultKeys.fieldAutoPlaySpan.key, "field.autoPlay.span")
        XCTAssertEqual(StudioDefaultKeys.fieldAutoPlayCentre.key, "field.autoPlay.centre")
        XCTAssertEqual(StudioDefaultKeys.fieldAutoPlayBand.key, "field.autoPlay.band")
        XCTAssertEqual(StudioDefaultKeys.fieldAutoPlayBandDrift.key, "field.autoPlay.bandDrift")
        XCTAssertEqual(StudioDefaultKeys.fieldAutoPlayVoices.key, "field.autoPlay.voices")
        XCTAssertEqual(StudioDefaultKeys.fieldAutoPlayPeriod.key, "field.autoPlay.period")
        // The arp's rhythm (#253 A7, + `push` with #258). Nested one level deeper than its siblings
        // on purpose: these FIVE belong to `RoleRhythm.Params`, which will be persisted per ROLE
        // (pad, bass, lead) once A3–A5 land, and `field.autoPlay.arpRhythm.*` is the shape that
        // extends to `role.pad.rhythm.*` without any of these keys having to move.
        XCTAssertEqual(StudioDefaultKeys.fieldArpRhythmCharacter.key,
                       "field.autoPlay.arpRhythm.character")
        XCTAssertEqual(StudioDefaultKeys.fieldArpRhythmGate.key, "field.autoPlay.arpRhythm.gate")
        XCTAssertEqual(StudioDefaultKeys.fieldArpRhythmAccent.key, "field.autoPlay.arpRhythm.accent")
        XCTAssertEqual(StudioDefaultKeys.fieldArpRhythmEvolve.key, "field.autoPlay.arpRhythm.evolve")
        XCTAssertEqual(StudioDefaultKeys.fieldArpRhythmPush.key, "field.autoPlay.arpRhythm.push")
    }

    /// ⭐ THE ONE ASSERTION THAT MAKES #253 A7 A UI SLICE AND NOT A RE-VOICING.
    ///
    /// A2 shipped the arp's rhythm with NO writer, so `FieldAutoPlay.Params.init`'s default *is*
    /// what the instrument currently sounds like. A7 put four rows in front of it and #258 a fifth
    /// (Laid back) — and if any
    /// default here disagreed with that default, every existing user's arp would change the moment
    /// they updated, in a slice whose whole point is to make the setting reachable. Nobody would
    /// see it in the diff: two files, two plausible numbers.
    ///
    /// So this compares against the `Params` default ITSELF rather than against literals. Change
    /// the arp's shipped sound and this goes red until both sides move together — which is the
    /// only honest way to change it.
    func testTheArpRhythmRowsStartOnExactlyWhatTheArpAlreadyPlays() {
        let shipped = FieldAutoPlay.Params().arpRhythm
        XCTAssertEqual(StudioDefaultKeys.fieldArpRhythmCharacter.value, shipped.character)
        XCTAssertEqual(Float(StudioDefaultKeys.fieldArpRhythmGate.value), shipped.gate)
        XCTAssertEqual(Float(StudioDefaultKeys.fieldArpRhythmAccent.value), shipped.accent)
        XCTAssertEqual(Float(StudioDefaultKeys.fieldArpRhythmEvolve.value), shipped.evolve)
        // #258: the same law for the Push key. It matters MORE here than for the other four,
        // because this row arrived AFTER people had been playing the arp — a non-zero default
        // would have moved every existing user's timing on update, in a slice whose whole point
        // is to make an existing behaviour reachable.
        XCTAssertEqual(Float(StudioDefaultKeys.fieldArpRhythmPush.value), shipped.push)
        // And the defaults must be inside the ranges the rows offer, so no dial starts on a value
        // it cannot be returned to. Gate's floor is `minGate`, not 0 — a gate of 0 is a click.
        XCTAssertGreaterThanOrEqual(Float(StudioDefaultKeys.fieldArpRhythmGate.value),
                                    RoleRhythm.minGate)
        XCTAssertLessThanOrEqual(Float(StudioDefaultKeys.fieldArpRhythmGate.value),
                                 RoleRhythm.maxGate)
        for v in [StudioDefaultKeys.fieldArpRhythmAccent.value,
                  StudioDefaultKeys.fieldArpRhythmEvolve.value] {
            XCTAssertGreaterThanOrEqual(v, 0)
            XCTAssertLessThanOrEqual(v, 1)
        }
    }

    /// What the arp panel shows on a FRESH INSTALL, which is a founder-visible decision and not an
    /// accident: the Evolve row is drawn only when the chosen character uses it, so the default
    /// character deciding that is worth pinning here — it fails the moment someone moves the
    /// default to `.dynamic` or `.flowing` and quietly changes the panel.
    ///
    /// ⚠️ THE COUNT CAME OUT OF THIS TEST'S NAME AND MESSAGE (#258). They said "three numeric rows,
    /// not four" — which was already loose (the Rhythm `Picker` it counted is not numeric) and went
    /// stale the moment the Laid-back row landed, without a single assertion changing. Nothing here
    /// can count rows: `fieldArpRhythmFields` is `private` inside a view. So the name now states the
    /// property that IS asserted. A number in a name that no assertion derives is the same class of
    /// claim this file's other rationale was deleted for.
    ///
    /// ⚠️ THE FIRST VERSION OF THIS TEST CLAIMED MORE THAN IT DELIVERS, and the claim is deleted
    /// rather than reworded down: it said `XCTAssertEqual(Set(usesIt), [.dynamic, .flowing])` stopped
    /// "a seventh character arriving with a silently-`false` answer". It cannot — add a seventh case
    /// returning `false` and the filtered set is unchanged and this stays green. What actually forces
    /// that decision is the exhaustive `switch` in `Character.usesEvolve`, and a `false` seventh
    /// character would produce a HIDDEN row, i.e. the correct behaviour. The flag's agreement with
    /// real output is proved in `RoleRhythmTests` (`testEvolveChangesExactlyTheCharactersThatClaimToUseIt`
    /// and, for the accent dial, `testAccentIsSubtleDescribesTheMeasuredSpreadAndNotAnIntention`) —
    /// duplicating that pin here bought nothing except a rationale describing a defence it did not
    /// provide, which is the failure class this repo pays for most often.
    func testTheArpPanelOpensWithThreeNumericRowsOnAFreshInstall() {
        XCTAssertFalse(StudioDefaultKeys.fieldArpRhythmCharacter.value.usesEvolve,
                       "the default character now uses Evolve — the panel shows a fourth row")
    }

    /// SELF-PLAY MUST BE OFF ON A FRESH INSTALL, and this is the assertion that gates it.
    ///
    /// Every other default in this file changes how the instrument ANSWERS. This one decides
    /// whether it plays on its own — so a default that armed it would mean an app that starts
    /// making music at a user who only opened it. `""` is not a case of `FieldAutoPlay.Motion`,
    /// which is why it reads as off; the second assertion pins that the enum really cannot
    /// decode it, because if a case named "" were ever added the first assertion alone would
    /// still pass while the field started playing.
    func testSelfPlayIsOffOnAFreshInstall() {
        XCTAssertEqual(StudioDefaultKeys.fieldAutoPlayMotion.value, "")
        XCTAssertNil(FieldAutoPlay.Motion(rawValue: StudioDefaultKeys.fieldAutoPlayMotion.value),
                     "the stored default must not decode to a motion — that IS the off state")
    }

    /// The dials' own defaults must be a MUSICALLY SENSIBLE starting point, because the moment
    /// a motion is chosen they all take effect at once — nobody dials seven values before
    /// hearing anything. Two of them are load-bearing rather than taste:
    ///   · density 0 would be silence, so the default must not be near it;
    ///   · voices 1 is a single line — a chord by default would be a surprise, and every extra
    ///     voice is another note-on per cell.
    func testTheSelfPlayDialsStartSomewhereMusical() {
        XCTAssertEqual(StudioDefaultKeys.fieldAutoPlayDensity.value, 0.5)
        XCTAssertEqual(StudioDefaultKeys.fieldAutoPlayVoices.value, 1.0)
        XCTAssertEqual(StudioDefaultKeys.fieldAutoPlayPeriod.value, 16.0)
        XCTAssertGreaterThan(StudioDefaultKeys.fieldAutoPlayDensity.value, 0,
                             "density 0 is silence, not sparseness — see FieldAutoPlay")
        // Within `FieldAutoPlay`'s own caps, so the default can never be the clamped value.
        XCTAssertLessThanOrEqual(Int(StudioDefaultKeys.fieldAutoPlayVoices.value),
                                 FieldAutoPlay.maxVoices)
        XCTAssertLessThanOrEqual(Int(StudioDefaultKeys.fieldAutoPlayPeriod.value),
                                 FieldAutoPlay.maxPeriodSteps)
    }

    /// The defaults behind those keys are founder decisions, and a rename is not the moment
    /// to revisit them. Pinned separately from the keys because the two fail for different
    /// reasons: a changed key loses stored settings, a changed default changes how the
    /// instrument behaves on a fresh install — and only one of those is visible in a diff
    /// that claims to be "just a rename".
    ///
    /// Exact comparison, no `accuracy:`. These are constants compared to constants with no
    /// arithmetic in between; an accuracy overlay would falsely suggest drift is possible.
    func testTheRenameChangedNoDefaultBehindThoseKeys() {
        XCTAssertEqual(StudioDefaultKeys.touchMorphDepth.value, 0.6)
        XCTAssertEqual(StudioDefaultKeys.touchSlideVibrato.value, 0.35)
        XCTAssertEqual(StudioDefaultKeys.touchSlideChorus.value, 0.30)
        XCTAssertEqual(StudioDefaultKeys.touchGlide.value, 0.0)
        XCTAssertEqual(StudioDefaultKeys.touchLevel.value, 1.0)
        XCTAssertEqual(StudioDefaultKeys.touchLife.value, 0.35)
        // Sync OFF on a fresh install: the surface plays exactly where the finger lands until
        // someone asks for the grid. A rename must not quietly arm it.
        XCTAssertEqual(StudioDefaultKeys.touchSyncStrength.value, 0.0)
        // "" = follow the take's sound. A fresh install must not start on some stored patch.
        XCTAssertEqual(StudioDefaultKeys.touchPatchID.value, "")
        XCTAssertFalse(StudioDefaultKeys.touchShowGrid.value)
    }

    /// The default patch has now been renamed twice ("Echoel Touch" → "Echoel Synth" →
    /// "Echoel Field") and its id has never moved. That is what makes those renames free:
    /// `touch.patchID` stores the UUID, so a saved selection is bound to the patch and not to
    /// its label. Pinned because the next rename will be tempting to do the lazy way.
    ///
    /// The name assertion is the other half, and it is the one that caught a real defect: the
    /// surface was renamed to "Field" while this patch — applied at launch, shown as the
    /// selected chip on the panel titled "Field" — still read "Echoel Synth" on screen.
    func testTheDefaultPatchIsIdentifiedByIdAndNamedForTheSurface() {
        let patch = SynthPatch.factory.first { $0.id == SynthPatch.touchDefaultID }
        XCTAssertNotNil(patch, "the play surface's default patch is missing from the factory")
        XCTAssertEqual(patch?.name, "Echoel Field",
                       "the surface is called Field — its default voice must not still say Synth")
    }
}
