// ResetSoundClearsWhatTheLaunchLineReportsTests.swift
// Echoel — #400. Until this slice, the only complete sound reset was deleting the app.
//
// ⭐ THIS FILE GUARDS A PAIR, NOT A FUNCTION. #401 made the next "es klingt schief" answerable
// from one launch log line; #400 makes it FIXABLE without a reinstall. Those two only work
// together if they describe the SAME set of persisted values — a breadcrumb that reports a
// value the reset cannot clear sends the founder back to deleting the app, and a reset that
// clears a value the breadcrumb never named cannot be reasoned about from a log at all. The
// first test below is the join: every label in `SoundReset.entries` must actually be emitted by
// `logLaunchMusicalIdentity`. Add a value to one and not the other and the blocking bundle
// goes red.
//
// ⭐ MOSTLY REAL BEHAVIOUR. `SoundReset.clear(in:)` takes the store as a parameter and
// `SessionContext.init` takes one too, so "what does a reset actually leave behind" is
// decidable here against a scratch suite — no simulator state, no process defaults, nothing
// that leaks between runs.
//
// ⛔ WHAT IT CANNOT PROVE. That the re-apply in `resetSoundToDefaults()` makes the change
// AUDIBLE — that it reaches an attached voice and that the player hears factory. Every engine
// call in that function needs a device pass. What is settled here is that the right keys go,
// the user's work stays, and the door exists.

import Foundation
import XCTest
@testable import Echoelmusic

final class ResetSoundClearsWhatTheLaunchLineReportsTests: XCTestCase {

    private let suiteName = "com.echoelmusic.tests.soundreset"

    private func scratchDefaults() throws -> UserDefaults {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        return try XCTUnwrap(UserDefaults(suiteName: suiteName), """
        could not open a scratch `UserDefaults` suite, so this file would otherwise have to \
        write into the process's own defaults — which is how a test starts depending on the \
        order it runs in.
        """)
    }

    override func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - The join with #401

    /// ⭐ THE ASSERTION THIS FILE EXISTS FOR: the reset and the launch breadcrumb describe one
    /// set of values. Comments are stripped first, so this file's own subject and the long
    /// rationale blocks beside the emitter cannot stand in for the code.
    ///
    /// ⛔ IT SCANS THE `launch/musical:` LINE SPECIFICALLY, NOT THE WHOLE FILE, and the
    /// difference is not pedantry: the `generate[…]` breadcrumb also carries `key=`, `tuning=`
    /// and `a4=`, so a whole-file search would have gone on passing for those three after the
    /// launch line lost them — which is the one failure this test is here to catch.
    func testEveryResetLabelIsAValueTheLaunchLineReports() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        let source = try XCTUnwrap(lines.first { $0.contains("launch/musical:") }, """
        no line in `EchoelStudioView` emits the `launch/musical:` breadcrumb any more.

        That line is #401 — the one place a "es klingt schief" report can be read back from. \
        Without it this reset can still run, but nobody can tell which stored value made the \
        instrument sound wrong, which is the situation that produced #400 in the first place.
        """)

        for entry in SoundReset.entries {
            XCTAssertTrue(source.contains("\(entry.label)="), """
            `SoundReset` clears "\(entry.label)", but the launch breadcrumb never reports it.

            Those two have to name the same values. #401 exists so the next "es klingt schief" \
            can be read off ONE log line; a value this reset clears but that line never mentions \
            is invisible in exactly the moment it matters. Either add it to \
            `logLaunchMusicalIdentity()` or take it out of `SoundReset.entries`.
            """)
        }
    }

    /// The reset must not be EMPTY of the things the founder's own report pointed at. Pinned by
    /// name rather than by count: a count would stay green while ten labels were swapped for ten
    /// others, and "tuning" going missing is the specific regression that would make this whole
    /// slice useless against the reported symptom.
    func testTheValuesMostLikelyToSoundWrongAreCovered() {
        let labels = Set(SoundReset.entries.map(\.label))
        for expected in ["key", "tuning", "a4", "genre", "preset", "touchPatch"] {
            XCTAssertTrue(labels.contains(expected), """
            "\(expected)" is no longer in `SoundReset.entries`.

            The founder's 2026-08-05 report was that the instrument sounded OUT OF TUNE and that \
            only a reinstall cured it. Key, tuning system and concert pitch are the three values \
            that can produce that symptom directly; genre, preset and the Field voice are the \
            three that decide what a note sounds like at all. A reset missing any of them cannot \
            replace the reinstall it exists to replace.
            """)
        }
    }

    // MARK: - What it must NOT touch

    /// ⛔ THE BOUNDARY. A reset that eats the user's saved work is the reinstall wearing a
    /// button — the exact thing #400 is a reaction to.
    func testTheResetCannotReachTheUsersWork() {
        for key in SoundReset.keys {
            let lowered = key.lowercased()
            for forbidden in ["artist", "autosave", "project", "patches", "recording", "export"] {
                XCTAssertFalse(lowered.contains(forbidden), """
                the reset key "\(key)" looks like it belongs to the user's WORK, not to the \
                instrument's settings (it contains "\(forbidden)").

                Saved patches, projects, takes, the autosave slot and the artist name are the \
                things a player would lose by reinstalling — keeping them is the entire reason \
                this reset exists instead of a "delete the app" support answer.
                """)
            }
        }
    }

    /// And the same boundary as behaviour, because a name check only catches a key that is
    /// honestly named. A planted work key must survive a full clear.
    func testAClearLeavesAPlantedWorkKeyAlone() throws {
        let defaults = try scratchDefaults()
        defaults.set("the user's saved library", forKey: "echoel.patches.v1")
        defaults.set("E~", forKey: "echoel.artistName")

        for key in SoundReset.keys { defaults.set("something the user changed", forKey: key) }
        SoundReset.clear(in: defaults)

        XCTAssertEqual(defaults.string(forKey: "echoel.patches.v1"), "the user's saved library", """
        a sound reset removed a key that does not belong to it. This test plants a stand-in for \
        the patch library specifically because a future edit to `SoundReset.keys` is far more \
        likely to be too WIDE than too narrow.
        """)
        XCTAssertEqual(defaults.string(forKey: "echoel.artistName"), "E~", """
        the reset removed the artist name. That is the player's identity, not a sound setting, \
        and `SessionContext` deliberately does not expose its key for this reason.
        """)
    }

    // MARK: - The clear itself

    /// Every key gone, and gone means ABSENT — not "set to a default value". A key written back
    /// as a literal default is how a reset silently stops matching a fresh install the day that
    /// default changes.
    func testEveryMusicalKeyIsAbsentAfterAClear() throws {
        let defaults = try scratchDefaults()
        for key in SoundReset.keys { defaults.set("changed by the user", forKey: key) }

        SoundReset.clear(in: defaults)

        for key in SoundReset.keys {
            XCTAssertNil(defaults.object(forKey: key), """
            "\(key)" survived the sound reset.

            It is listed in `SoundReset.entries`, so the player was told it would go back to \
            factory. One surviving key is the whole defect: the founder's install needed a \
            REINSTALL precisely because one persisted value could not be reached any other way.
            """)
        }
    }

    /// Running it on a store that never held the keys must be a no-op, so a fresh install and a
    /// reset install end up in the same state. `removeObject` already behaves this way; the test
    /// pins it because a future "write the default instead of removing" refactor would not.
    func testClearingATouchedNothingStoreChangesNothing() throws {
        let defaults = try scratchDefaults()
        SoundReset.clear(in: defaults)
        for key in SoundReset.keys {
            XCTAssertNil(defaults.object(forKey: key),
                         "a reset on an untouched store invented a value for \"\(key)\".")
        }
    }

    // MARK: - The half a key-clear cannot do

    /// ⭐ CLEARING IS NOT ENOUGH, AND THIS IS THE PROOF. `SessionContext` reads its three values
    /// once in `init`, so a live instance keeps reporting the old concert pitch after a clear —
    /// and its own `didSet` would write that stale value straight back on the next edit.
    @MainActor
    func testSessionResetPutsTheTrioBackToFactory() throws {
        let defaults = try scratchDefaults()
        let session = SessionContext(defaults: defaults)
        session.keyRoot = 7
        session.keyScale = .major
        session.a4Hz = 432
        session.artistName = "Someone"

        SoundReset.clear(in: defaults)
        XCTAssertEqual(session.a4Hz, 432, """
        this assertion is the POINT of the test, not a mistake: after clearing the stored keys \
        the live object still holds 432. If it ever reports 440 here, `SessionContext` has \
        gained a store observer and `resetMusicalIdentity()` may no longer be needed — check \
        before deleting it.
        """)

        session.resetMusicalIdentity()
        XCTAssertEqual(session.a4Hz, SessionContext.defaultA4Hz, "concert pitch did not return to factory")
        XCTAssertEqual(session.keyRoot, SessionContext.defaultKeyRoot, "key root did not return to factory")
        XCTAssertEqual(session.keyScale, SessionContext.defaultKeyScale, "key scale did not return to factory")
        XCTAssertEqual(session.artistName, "Someone", """
        `resetMusicalIdentity()` overwrote the artist name. It resets the SOUND; the player's \
        name is not part of it.
        """)
    }

    /// And a fresh `SessionContext` built on the reset store must agree — otherwise "factory"
    /// means one thing after a reset and another after a relaunch.
    @MainActor
    func testAFreshSessionOnAResetStoreAgreesWithTheResetOne() throws {
        let defaults = try scratchDefaults()
        let first = SessionContext(defaults: defaults)
        first.a4Hz = 415
        first.keyRoot = 3

        SoundReset.clear(in: defaults)
        first.resetMusicalIdentity()

        let relaunched = SessionContext(defaults: defaults)
        XCTAssertEqual(relaunched.a4Hz, first.a4Hz, "a relaunch after a reset would sound different")
        XCTAssertEqual(relaunched.keyRoot, first.keyRoot, "a relaunch after a reset would be in a different key")
    }

    /// The same half-fix one layer down (slice 2). `MixerStore` reads its four levels once in
    /// `init`, so a clear leaves the live store still returning the old value — and `didSet`
    /// would write it straight back on the next unrelated edit.
    ///
    /// ⚠️ THE FIRST ASSERTION IS DELIBERATELY THE "WRONG" ONE, like its `SessionContext` twin: it
    /// pins that a clear alone does NOT cure a muted role. If it ever fails, `MixerStore` has
    /// gained a store observer and `resetToUnity()` may be redundant — check before deleting it.
    ///
    /// ⚠️ AND THE EXPECTED VALUES ARE THE LITERAL `1.0`, NOT `MixerStore.defaultLevel` — do not
    /// "tidy" them into the constant. The `SessionContext` twin reads its constants because there
    /// the question is "did the reset and the initializer agree"; here the question is whether the
    /// factory value is still UNITY, and a test written against the constant answers yes no matter
    /// what the constant becomes.
    @MainActor
    func testMixResetPutsEveryFaderBackToUnity() throws {
        let defaults = try scratchDefaults()
        let mixer = MixerStore(defaults: defaults)
        // ⚠️ ALL FOUR ARE MOVED OFF UNITY, not just two. The first version touched `bass` and
        // `lead` only, so no assertion about `pad` or `drums` could fail — including `drums`, the
        // one the sibling test below exists to protect. A test named "every fader" that exercises
        // half of them is the #376 trap wearing a plural.
        mixer.bass = 0        // the #399 signature: a whole role silently muted
        mixer.pad = 0.25
        mixer.lead = 0.4
        mixer.drums = 0.1     // no door since #166/#167 — unreachable except through this reset

        SoundReset.clear(in: defaults)
        XCTAssertEqual(mixer.bass, 0, """
        the live mixer picked up the cleared store on its own. See the note above before \
        removing `resetToUnity()` from the reset — this assertion is the point of the test.
        """)

        mixer.resetToUnity()
        XCTAssertEqual(mixer.bass, 1.0, "the bass fader did not return to unity")
        XCTAssertEqual(mixer.pad, 1.0, "the pad fader did not return to unity")
        XCTAssertEqual(mixer.lead, 1.0, "the lead fader did not return to unity")
        XCTAssertEqual(mixer.drums, 1.0, """
        the drums level did not return to unity. It has no door left (#166/#167), so this reset \
        is the ONLY way a player can ever move it — a value stuck here is stuck for good.
        """)

        let relaunched = MixerStore(defaults: defaults)
        XCTAssertEqual(relaunched.bass, mixer.bass, """
        a relaunch after a reset would mix differently: the live store says unity and the \
        persisted store says something else. #399 is exactly this shape — a level that held \
        steady for a whole session and was indistinguishable from a broken engine.
        """)
        XCTAssertEqual(relaunched.pad, mixer.pad, "a relaunch after a reset would mix differently")
        XCTAssertEqual(relaunched.lead, mixer.lead, "a relaunch after a reset would mix differently")
        XCTAssertEqual(relaunched.drums, mixer.drums, "a relaunch after a reset would mix differently")
    }

    /// The doorless one. `mixer.drums` has had no control since #166/#167 deleted the drums, so a
    /// value dialled down in July can neither be seen nor changed by any player — which makes it
    /// the one level that MUST be in the reset, not the one that is safe to leave out.
    func testTheDoorlessDrumLevelIsClearedToo() {
        let userMix = SoundReset.entries.first { $0.label == "userMix" }
        XCTAssertNotNil(userMix, """
        the mixer levels are no longer part of the sound reset. #399 found a bass fader persisted \
        at 0.00 for an entire session on a shipped build — that is the #400 defect one layer down, \
        and it is why slice 2 exists.
        """)
        // ⛔ THE LITERAL FIRST, AND THAT ORDER IS THE WHOLE POINT. The set-equality below is true
        // BY CONSTRUCTION — `SoundReset` writes `keys: MixerStore.storageKeys` — so on its own it
        // can only catch someone re-typing a subset as literals, which is not the edit this test's
        // name warns about. The edit it warns about is `drums` being dropped from
        // `MixerStore.storageKeys` while finishing the dead-drum cleanup (#167 shipped; #268 is
        // still open on `LaneVoiceKind.drums`). That moves BOTH sides together and would sail past
        // a set comparison, leaving the one unreachable level surviving a factory reset for good.
        XCTAssertTrue(Set(userMix?.keys ?? []).contains("mixer.drums"), """
        "mixer.drums" is no longer cleared by the sound reset.

        Its door was deleted with the drums (#166/#167), so nothing else in the app can show or \
        change that value. If it was dropped as part of finishing that cleanup, the honest order \
        is: clear it for everyone FIRST (so no install carries a stale level), then remove the key.
        """)
        XCTAssertEqual(Set(userMix?.keys ?? []), Set(MixerStore.storageKeys), """
        the reset no longer clears every mixer key. `MixerStore.storageKeys` is the single source; \
        listing a subset here is how a level would quietly survive a factory reset.
        """)
    }

    // MARK: - Source scans: the literals, and the door

    /// The four keys `SoundReset` spells out as literals are declared with a raw literal at
    /// their use site too. That duplication is acknowledged in `SoundReset`'s own header and its
    /// real fix is promotion into `StudioDefaultKeys`; until then this scan is what keeps a
    /// rename at the use site from silently turning one line of the reset into a no-op.
    func testTheLiteralKeysStillMatchTheirDeclarationSite() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        let source = lines.joined(separator: "\n")

        for key in ["toneSystemID", "studio.presetIndex", "studio.articulation"] {
            XCTAssertTrue(source.contains("\"\(key)\""), """
            `SoundReset` clears "\(key)", but no `@AppStorage` in `EchoelStudioView` declares \
            that string any more.

            Either the key was renamed and the reset now clears nothing, or the setting is gone \
            and the reset should stop mentioning it. Both are silent failures on device: the \
            player taps Reset, the app says nothing, and the value they were trying to escape \
            is still there.
            """)
        }
    }

    /// ⭐ A CORRECT RESET NOBODY CAN REACH IS THE SAME DEFECT WITH EXTRA STEPS — every test
    /// above would stay green while the app shipped without a button.
    ///
    /// ⛔ A SOURCE SCAN, with the limits that implies: it proves the call and the row are
    /// written, not that the row renders. Reachability of `savePanel` itself is another file's
    /// job (`NoDoorlessStudioViewsTests`).
    func testTheResetHasADoorAndTheDoorIsInThePanel() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/EchoelStudioView.swift")

        XCTAssertTrue(lines.contains { $0.contains("SoundReset.clear(") }, """
        nothing in `EchoelStudioView` calls `SoundReset.clear` any more, so the reset is a \
        correct core with no caller — and the only complete sound reset is deleting the app \
        again (#400).
        """)
        XCTAssertTrue(lines.contains { $0.contains("soundResetRow") && !$0.contains("private var") }, """
        `soundResetRow` is declared but never composed into a panel. That is the doorless-view \
        failure this repo has paid for repeatedly: the code exists, the guard is green, and no \
        player can reach it.
        """)
        XCTAssertTrue(lines.contains { $0.contains("session.resetMusicalIdentity()") }, """
        the reset no longer pushes the factory key and concert pitch into the live \
        `SessionContext`. Clearing the keys alone leaves the old A4 SOUNDING until the next \
        launch — see `testSessionResetPutsTheTrioBackToFactory`, which pins exactly that.
        """)
        XCTAssertTrue(lines.contains { $0.contains("mixer.resetToUnity()") }, """
        the reset no longer pushes unity into the live `MixerStore`. Same half-fix as the line \
        above, one layer down: the levels are cached in stored properties, so a muted role stays \
        muted until the next launch and `didSet` re-persists it in the meantime.
        """)
    }

    /// ⛔ THE GUARD THAT WAS MISSING, and the defect it now catches shipped for one commit. The
    /// scan above only asks whether `mixer.resetToUnity()` APPEARS — and the first version of
    /// slice 2 satisfied that while leaving the felt sub at the old level, because `SubBassVoice`
    /// has no per-note velocity for the compose-time path to scale and therefore takes its level
    /// on the AUDIO side. A player with `mixer.bass` persisted at 0.00 (the #399 signature) would
    /// have tapped Reset, watched every other role return to unity, and still had a silent sub
    /// until the next relaunch. Found by a reviewer, not by a test — hence this one.
    ///
    /// ⚠️ IT IS WINDOWED TO THE FUNCTION, deliberately. A whole-file search would have passed on
    /// the day the bug existed: `mixBinding` and the Mix panel's own reset each carry an identical
    /// pair of lines, so the strings were in the file the whole time. That is the exact shape of a
    /// test that cannot fail for its own name.
    func testTheResetPushesTheBassLevelIntoTheFeltSub() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        guard let start = lines.firstIndex(where: { $0.contains("private func resetSoundToDefaults") }) else {
            return XCTFail("`resetSoundToDefaults` is gone — if the reset moved, move this guard with it.")
        }
        let end = lines[start...].firstIndex { $0.contains("reset/sound:") }
            ?? Swift.min(start + 60, lines.count - 1)
        let window = lines[start...end].joined(separator: "\n")

        XCTAssertTrue(window.contains("mixer.resetToUnity()"), """
        `resetSoundToDefaults()` no longer puts the mixer back to unity, so a role muted at 0.00 \
        survives a factory reset — the #399 defect, untouched by the thing built to fix it.
        """)
        XCTAssertTrue(window.contains("subBass.mixLevel = mixer.bass"), """
        the reset sets the mixer to unity but never pushes the bass level into the felt sub.

        `mixer.resetToUnity()` writes the store DIRECTLY, bypassing `mixBinding`, and \
        `recomposeIfRunning()` cannot cover the gap: the sub takes its level on the audio side \
        because it has no per-note velocity to scale. The Mix panel's own reset says this in as \
        many words — "a new mutator must push both lines below". This is a new mutator.
        """)
        XCTAssertTrue(window.contains("laneVoiceRack.setBassMixLevel(mixer.bass)"), """
        the reset does not push the bass level into the lane rack's subs, which share the Bass \
        bus. Half a fan-out is the same defect as none: one sub returns to unity, the others \
        stay where the user left them.
        """)
    }

    /// It must NOT be an `.alert`. The two-tap confirmation is a deliberate response to the
    /// 10.76.34 black screen: the root body's presentation chain is at the metadata limit, and
    /// "add one more modal" is the one change that has taken this app down at first render.
    ///
    /// ⛔ THE FIRST VERSION OF THIS TEST COULD NOT FAIL FOR ITS OWN NAME. Its only assertion was
    /// that the string `soundResetArmed` appears somewhere — and `@State private var
    /// soundResetArmed = false` satisfies that on its own, with no warning, even after someone
    /// rips out the two-tap logic and adds `.alert(…)` as a 15th modifier. The name promised a
    /// count; the body checked a spelling. Found in review — it is the `#376` trap this bundle
    /// has already documented twice, committed a third time by the file that cites it.
    func testTheConfirmationDidNotBecomeAnotherModal() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/EchoelStudioView.swift")

        XCTAssertTrue(lines.contains { $0.contains("soundResetArmed") }, """
        the two-tap arm/confirm state is gone — see the count assertion below for why that \
        matters. Reuse a slot or confirm inline; do not add a modal.
        """)

        // ⚠️ FILE-WIDE, DELIBERATELY, and the decomposition is what makes the number meaningful:
        // 14 sit on the root body's chain, `.sheet(item: $visualShare)` sits INSIDE the
        // fullScreenCover's content, and one `.fileImporter` hangs off a different view. Only the
        // first group counts against the metadata limit — but a file-wide count is the one a
        // source scan can take honestly, and any new modal lands in it whichever group it joins.
        let modals = lines.filter {
            $0.contains(".sheet(") || $0.contains(".fullScreenCover(")
                || $0.contains(".alert(") || $0.contains(".confirmationDialog(")
                || $0.contains(".fileImporter(") || $0.contains(".popover(")
        }
        XCTAssertEqual(modals.count, 16, """
        `EchoelStudioView` now has \(modals.count) presentation-modifier call sites, not 16.

        If this GREW, read the black-screen law before doing anything else: the aggregate generic \
        type of the root body is at the SwiftUI metadata-decoder limit, and the 10.76.34 crash was \
        this chain growing by three — SIGSEGV at first render, before any view appears, presenting \
        as a black screen. An `AnyView` split does NOT save it; only reverting the count did. \
        Reuse an existing slot, or consolidate the chain into one `.sheet(item:)` enum FIRST.

        If it SHRANK, that is the safe direction — update this number, the `CHAIN LENGTH` comment \
        in `EchoelStudioView`, and the two counts in `CLAUDE.md` in the same commit. They are \
        supposed to be one fact; they have been three different numbers before.

        Found: \(modals.map { $0.trimmingCharacters(in: .whitespaces).prefix(48) })
        """)
    }

    /// A destructive control with a glyph-sized hit area is the #394 defect, and this one is
    /// smaller AND more destructive than the loudness Reset that fix was written for.
    /// `TapTargetFloorTests` is deliberately an anchored list rather than a sweep, so it has no
    /// case for this row — the guard lives here, next to the thing it guards.
    func testTheResetRowIsAReachableTapTarget() throws {
        let lines = try codeLines("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        guard let start = lines.firstIndex(where: { $0.contains("private var soundResetRow") }) else {
            return XCTFail("`soundResetRow` is gone — if the reset moved, move this guard with it.")
        }
        let window = lines[start..<min(start + 40, lines.count)].joined(separator: "\n")

        XCTAssertTrue(window.contains("minHeight: 44"), """
        the reset row no longer declares a 44 pt minimum height.

        `.buttonStyle(.plain)` makes the hit area the GLYPH RUN — about 90 × 14 pt at this font. \
        That is under the HIG 44 floor and under WCAG 2.5.8's 24, on a control that wipes the \
        instrument's settings and sits one line above "Diagnostics".
        """)
        XCTAssertTrue(window.contains("contentShape("), """
        the reset row no longer declares a `contentShape`, so the 44 pt frame is empty space that \
        does not accept taps — the frame alone does not extend the hit area under `.plain`.
        """)
    }

    // MARK: - Source access

    /// Every non-empty line of `path` with comments removed — whole-line AND trailing. The
    /// quote-parity check approximates "is this `//` inside a string literal" and fails in both
    /// directions. Same helper as `FieldSoundSurvivesRelaunchTests`.
    private func codeLines(_ path: String) throws -> [String] {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = root.appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("""
            \(url.path) is not present — the scanning half of this file reads source text, so it \
            SKIPS rather than reporting a green it did not earn. The behavioural tests above ran.
            """)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { Self.stripComment(String($0)) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func stripComment(_ line: String) -> String {
        var quotes = 0
        var previous: Character?
        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]
            if ch == "\"" { quotes += 1 }
            if ch == "/", previous == "/", quotes % 2 == 0 {
                return String(line[line.startIndex..<line.index(before: index)])
            }
            previous = ch
            index = line.index(after: index)
        }
        return line
    }
}
