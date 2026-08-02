// DetunedInstrumentSaysSoTests.swift
// Echoel — a detuned instrument must SAY it is detuned, on the panel a launch opens. BLOCKING. #325.
//
// THE EVIDENCE, because #325 stood open as "a judgement call" for weeks and what closed it was
// not an argument. On 2026-08-02 the founder reported "es klingt sehr unharmonisch" and sent a
// screen recording of v10.79.366 in which the concert pitch walks 440 → 483,4352 → 500,0000 Hz
// while the header chip strip is scrolled and the keypad never opens (#391/#392 closed that
// cause). `session.a4Hz` is PERSISTED, so it survived relaunch; 483 Hz is 158 cents sharp, and
// for the whole session nothing on screen said so. The cause is fixed elsewhere. This guards the
// part that makes the SYMPTOM legible while it is happening.
//
// ⛔ AND THE BANNER AS IT SAT WOULD NOT HAVE HELPED. Its condition was `tuningID != "edo12"` —
// the tone SYSTEM. The tone system was standard through that entire session, so a mounted
// version of the old banner would have been silent exactly when it was needed. Dooring it and
// widening it are ONE change, not a fix plus a bonus, and that is why
// `testTheBannerCoversTheConcertPitchAndNotOnlyTheToneSystem` is the first test in this file:
// the mount is worth nothing without it.
//
// ⚠️ WHY A SOURCE SCAN. The behaviour is a conditional `@ViewBuilder` inside a `@MainActor`
// view with the whole session graph behind it; there is no local toolchain and no simulator, and
// the blocking bundle is `Tests/CISmoke`. House pattern. A green here means the banner is WIRED
// and where — never that a founder saw it.
//
// NEEDS-FOUNDER-VERIFY: set A4 to something other than 440 in the header strip. The Sound panel
// must show a "Non-standard concert pitch: A4 = … Hz" line with a "Standard" button; the button
// must return it to 440 AND the take must audibly retune. Then set the tone system to a
// non-12-TET one at A4 = 440 and confirm the line names the SYSTEM and not the pitch.

import Foundation
import XCTest

final class DetunedInstrumentSaysSoTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    // MARK: - The widening, which is the half that answers the founder's report

    /// ⭐ THE CONDITION IS THE FEATURE. A banner that renders is not a banner that warns; what
    /// decides whether the founder's 500 Hz session would have been visible is which facts the
    /// `if` reads. Both halves are asserted, because dropping either one silently returns this
    /// to a state that looks fine in review.
    func testTheBannerCoversTheConcertPitchAndNotOnlyTheToneSystem() throws {
        let body = try memberBody(startingWith: "private var nonStandardTuningBanner: some View",
                                  in: Self.studio)
        XCTAssertTrue(body.contains(where: {
            $0.contains("if toneSystemIsNonStandard || concertPitchIsNonStandard {")
        }), """
            the tuning banner's condition changed (#325).

            It must fire on EITHER a non-12-TET tone system OR a concert pitch away from 440. \
            The version that sat unpresented until 2026-08-02 checked only the tone system — \
            and would have been silent through the founder's entire 483–500 Hz session, which \
            is the exact case it now exists for. If the condition genuinely had to change, say \
            what replaces the concert-pitch half.
            banner: \(body.prefix(6).map { $0.trimmingCharacters(in: .whitespaces) })
            """)

        let code = try codeLines(Self.studio)
        let pitch = code.filter { $0.contains("private var concertPitchIsNonStandard: Bool") }
        XCTAssertEqual(pitch.count, 1, """
            expected exactly one `concertPitchIsNonStandard` declaration, found \(pitch.count). \
            The banner, its headline and its reset all read this one property so they cannot \
            disagree about what "standard" means.
            """)
        XCTAssertTrue(pitch[0].contains("abs(session.a4Hz - 440)"), """
            `concertPitchIsNonStandard` no longer measures `session.a4Hz` against 440:
            \(pitch[0].trimmingCharacters(in: .whitespaces))

            That property is the only thing standing between a persisted wrong reference and a \
            silent instrument-wide detune.
            """)
    }

    // MARK: - The door

    /// ⛔ MOUNTED IN `soundPanel` SPECIFICALLY, NOT "referenced somewhere". `displayedMenu`
    /// falls back to `.sound`, so this is the panel an untouched launch shows — which is what
    /// makes the banner reach a player who has not gone looking. Mounted in any other panel it
    /// would be a warning behind a chip, i.e. the doorless state with extra steps.
    func testTheBannerIsMountedOnThePanelAnUntouchedLaunchShows() throws {
        let panel = try memberBody(startingWith: "private var soundPanel: some View",
                                   in: Self.studio)
        XCTAssertTrue(panel.contains(where: {
            $0.trimmingCharacters(in: .whitespaces) == "nonStandardTuningBanner"
        }), """
            `nonStandardTuningBanner` is no longer mounted in `soundPanel` (#325).

            It was doorless from 2026-07-09 to 2026-08-02 — the commit that moved the tuning \
            CONTROLS into the header chrome moved the WARNING out of the app, and nothing \
            noticed for three weeks. If it moved to another panel, move this assertion with it \
            and check that panel is still what `displayedMenu` shows by default; if it was \
            removed, `NoDoorlessStudioViewsTests.knownOrphans` needs the entry back with the \
            reason.
            """)

        // The default matters as much as the mount: put it on a panel nobody lands on and the
        // guard above still passes while the warning is effectively hidden again.
        let code = try codeLines(Self.studio)
        XCTAssertTrue(code.contains(where: {
            $0.contains("private var displayedMenu: StudioMenu { activeMenu ?? .sound }")
        }), """
            the front plate no longer defaults to `.sound`, so mounting the tuning banner there \
            no longer puts it in front of a player who just opened the app. Re-decide where the \
            banner lives in the same commit rather than leaving it on a panel nobody reaches.
            """)
    }

    // MARK: - The button has to actually undo it

    /// A "Standard" button that changes a stored value without pushing it into the voices is
    /// the #114 defect: `session.a4Hz` restores from `UserDefaults`, but nothing hears it until
    /// somebody calls `applyConcertPitch`. Both halves, plus the tone-system half, or the
    /// control lies in exactly the situation it exists to rescue.
    ///
    /// ⛔ `pianoRoll.musicalA4Hz = 440` is in this list because the first version of it left
    /// that line out while the member's own doc claimed parity with `handleCompositionEdit`'s
    /// `"a4"` case — which pushes it. A guard that asserts four fifths of a documented parity
    /// lets the fifth be deleted and stay green, which is worse than not claiming parity: the
    /// note grid would silently keep painting the old reference's colours.
    func testTheResetWritesTheValueAndPushesItToTheVoices() throws {
        let reset = try memberBody(startingWith: "private func resetTuningToStandard()",
                                   in: Self.studio)
        let trimmed = reset.map { $0.trimmingCharacters(in: .whitespaces) }
        for needle in ["tuningID = \"edo12\"", "applyTuning()",
                       "session.a4Hz = 440", "applyConcertPitch(440)",
                       "pianoRoll.musicalA4Hz = 440", "recomposeIfRunning()"] {
            XCTAssertTrue(trimmed.contains(needle), """
                `resetTuningToStandard` no longer contains `\(needle)` (#325).

                The button must do what the header strip's own edit does: write the value AND \
                push it (`applyConcertPitch` / `applyTuning`), then recompose. Writing it alone \
                leaves the voices on the old reference — a control that reports success and \
                changes nothing audible, which is worse than no control.
                reset: \(trimmed)
                """)
        }
    }

    /// ⭐ THE RECOMPOSE BELONGS TO THE PITCH HALF, AND ONLY TO IT. `handleCompositionEdit`'s
    /// `"a4"` case recomposes; its `"tuning"` case does not. A reset that recomposes
    /// unconditionally is therefore MORE destructive than the header control it mirrors — it
    /// discards the running take when a player fixes only the tone system, at the moment they
    /// reached for it because something already sounded wrong. Structural, not textual: the
    /// call must sit at the same nesting as the other writes in the pitch branch.
    func testTheRecomposeRidesThePitchHalfAndNotTheToneSystem() throws {
        let reset = try memberBody(startingWith: "private func resetTuningToStandard()",
                                   in: Self.studio)
        let indent = { (line: String) in line.prefix { $0 == " " }.count }

        let recomposes = reset.filter { $0.trimmingCharacters(in: .whitespaces) == "recomposeIfRunning()" }
        XCTAssertEqual(recomposes.count, 1, """
            expected exactly one `recomposeIfRunning()` in `resetTuningToStandard`, found \
            \(recomposes.count). One per dimension re-generates the take twice for a single \
            tap; zero leaves a running take on the old reference.
            """)

        guard let pitchWrite = reset.first(where: {
            $0.trimmingCharacters(in: .whitespaces) == "pianoRoll.musicalA4Hz = 440"
        }), let recompose = recomposes.first else { return }

        XCTAssertEqual(indent(recompose), indent(pitchWrite), """
            `recomposeIfRunning()` is no longer in the same block as the concert-pitch writes \
            (#325 Nachlese). At the function's own level it fires for a tone-system-only reset \
            too, where `handleCompositionEdit`'s `"tuning"` case deliberately does not \
            recompose — the button would then destroy a take the header Picker preserves.
            reset: \(reset.map { $0.trimmingCharacters(in: .whitespaces) })
            """)
    }

    // MARK: - House rules this banner now has to obey, because it is reachable

    /// The Hz is a user-visible decimal, so it goes through `EchoelDecimalText` like every
    /// other one (#267). A hard-coded `%.2f` prints "443.25" in a panel where every neighbouring
    /// number prints "443,25" for a German player — and this line is read precisely when
    /// somebody is trying to decide whether a number is wrong.
    func testTheHertzUsesTheHouseDecimalSeparator() throws {
        let title = try memberBody(startingWith: "private var nonStandardTuningTitle: String",
                                   in: Self.studio)
        XCTAssertTrue(title.contains(where: {
            $0.contains("EchoelDecimalText.string(session.a4Hz, decimals: 2)")
        }), """
            the tuning banner's Hz no longer goes through `EchoelDecimalText` (#267). It is a \
            user-visible decimal on a line whose job is to make a number checkable; printing a \
            point where the rest of the panel prints a comma undermines exactly that.
            title: \(title.map { $0.trimmingCharacters(in: .whitespaces) })
            """)
    }

    /// ⛔ THE 34 pt BUTTON WAS ONLY NOBODY'S PROBLEM WHILE IT HAD NO DOOR. `TapTargetFloorTests`
    /// pins the same 34 as a defect on the two preset overflow menus (60 % of the HIG 44×44
    /// floor by area) and fixes them with an outset; here the control is a `Button` with room
    /// around it, so it takes the frame instead. `minHeight`, not `height`: a fixed one clips
    /// the label at large Dynamic Type sizes, which is the #353 class this repo has now paid
    /// for six times.
    func testTheResetButtonClearsTheTapTargetFloorAndStillGrows() throws {
        let body = try memberBody(startingWith: "private var nonStandardTuningBanner: some View",
                                  in: Self.studio)
        XCTAssertTrue(body.contains(where: { $0.contains("frame(minHeight: 44)") }), """
            the tuning banner's "Standard" button lost its `frame(minHeight: 44)` (#325).

            Below 44 pt it is under the HIG floor, and with a FIXED height its label clips once \
            the player raises the text size — the two failure modes this repo guards separately \
            elsewhere, both landing on one control that only became reachable on 2026-08-02.
            """)
        XCTAssertFalse(body.contains(where: { $0.contains("frame(height: 34)") }), """
            the tuning banner's button is back to a fixed `frame(height: 34)`. See above: that \
            is simultaneously under the tap-target floor and a Dynamic Type clip.
            """)
    }

    // MARK: - Source helpers

    /// Lines of a member, from the line that starts with `prefix` to the closing `}` at that
    /// line's OWN indentation. Structural, not a line count.
    private func memberBody(startingWith prefix: String, in path: String) throws -> [String] {
        let lines = try codeLines(path)
        guard let start = lines.firstIndex(where: { $0.contains(prefix) }) else {
            XCTFail("""
                `\(prefix)` is gone from \(path). If it was renamed, move this guard with it — \
                do not leave a check for a member that no longer exists.
                """)
            return []
        }
        let indent = lines[start].prefix { $0 == " " }.count
        let close = lines[(start + 1)...].firstIndex {
            $0.trimmingCharacters(in: .whitespaces) == "}"
                && $0.prefix { c in c == " " }.count == indent
        } ?? lines.endIndex
        return Array(lines[start..<close])
    }

    /// Every line that is not a whole-line comment. Load-bearing here more than usual: the
    /// banner carries a long ⭐/⛔ block that quotes `tuningID != "edo12"`, the measured Hz
    /// values and `session.a4Hz` verbatim while explaining them, so a scan that read prose
    /// would find every needle in the explanation rather than in the code.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
                source tree not present at \(sources.path) — this test inspects source text, so \
                it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }
}
