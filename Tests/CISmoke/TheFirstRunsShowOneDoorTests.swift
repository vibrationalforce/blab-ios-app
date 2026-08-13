// TheFirstRunsShowOneDoorTests.swift
// Echoel — #568, cycle C4 of the 2026-08-13 handover ("FIRST RUN = f(engineState)").
//
// WHAT THE SLICE DOES. Below `SessionMaturity.simplifiedBelow` launches that reached the
// studio, the front-plate chip strip carries the Sound chip alone instead of eight. The
// transport, the tempo field and the waveform are not chips and are untouched; the chrome
// doors (pulse pill → Bio, header clips tile → Video, `quickActionRow`, `quickDoorRow`) stay
// mounted at every maturity. Hidden panels stay in code — the calm-shell precedent (#157).
//
// ⚠️ THE LIMIT, PER ASSERTION:
//   · claims 1–3 are END-TO-END BEHAVIOUR over `SessionMaturity`, a public Foundation-only
//     value type. That is the strong kind and it is where the policy actually lives.
//   · claims 4–6 are SOURCE SCANS. `visibleChips`, `maturityChips` and `startControlRow` are
//     `private` members of a `View` no test bundle can instantiate, so what a scan can carry
//     is that the wiring exists and has the right SHAPE — not that a pixel moved.
//   · DEVICE PROBE, open: does a fresh install actually reach audible, bio-driven sound in
//     ≤ 3 actions, and does one chip read as calm rather than as broken? Nothing here can
//     answer either; both are founder questions and are registered as such.
//
// ⭐ WHY CLAIM 4 IS THE ONE THAT MATTERS. `visibleChips` appends the active menu so the strip
// never shows an unselected state. If that append is taken over the UNFILTERED `studioChips`,
// the code still compiles, the policy still "exists", and it evaporates the first time the
// user taps the pulse pill — the one door a new user is most likely to press. That is a
// silent, total defeat of the slice with no other gate able to see it, which is exactly the
// class #408 and the `scrollTo(.id)` guard next door were written for.
//
// ⚠️ HONEST GRADING (§3). This file does NOT compile against the parent (`81f76c2`):
// `SessionMaturity` does not exist there and claims 1–3 name it, so **no assertion has a
// verdict on the parent** and the grading below is hand-transcribed logic, not a run.
//   · ONE ABSENCE, REPORTED ONCE (#486): the missing type is a single fact, not three findings.
//   · claims 1–3 are FORWARD guards over the type this commit creates. Booking them as
//     regressions would be the flattering-direction defect (#433).
//   · claim 4 is a FORWARD guard over a member this commit creates — but its FAILURE MODE is
//     a future regression, not this commit's diff, which is the whole reason it is written.
//   · `testTheAppearanceCounterIsWrittenOncePerProcess` is also a FORWARD guard (it pins text
//     this commit writes), even though it sits beside the counterweights.
//   · `testTheAlwaysOnActionRowsAreStillOutsideThePlate` and
//     `testTheStandingStripStillDeclaresAllEight` are COUNTERWEIGHTS — transcribed green on
//     BOTH trees, and that is the point: they pin the premises that make the policy safe
//     (nothing was stranded, the strip was not re-sorted).
//   · ⭐ #571 ADDED TWO METHODS AND MOVED TWO NEEDLES; graded against ITS parent (`254bf7a`,
//     i.e. this file as #568 shipped it): `testAnInstallThatPredatesTheCounterIsTreatedAs
//     Experienced` and `testThePriorStateEvidenceIsAPrefixNothingRegisters` are REGRESSIONS —
//     `SessionMaturity.seed` and `priorStatePrefix` do not exist there, so the file does not
//     compile against that parent either. Claim 4's `studioAppearances` needle became
//     `Self.launchMaturity` (the render source moved), and claim 5's needle was widened to
//     `SessionMaturity.next(after:` because the ARGUMENT legitimately changed — that widened
//     needle is green on both trees and is now a counterweight rather than a forward guard.
//   · STRIPPER: PROPHYLAKTISCH — 0 of 17 needle verdicts flip, measured raw vs. stripped on
//     both trees. ⛔ The first draft of this header claimed TRAGEND ("`studioChips` also occurs
//     in `visibleChips`' doc comment"). Wrong, and wrong in the flattering direction (#433):
//     `declarationBody` anchors on the DECLARATION, so the doc comment ABOVE it is outside the
//     extracted body by construction. The stripper is kept anyway for one honest reason — the
//     `studioChips` needle in claim 4 is an ABSENCE, the fragile kind, and the day someone
//     writes "we no longer read `studioChips` here" INSIDE that body, a raw scan goes red on
//     correct code (#367).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheFirstRunsShowOneDoorTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// The real strip, in the real order (`EchoelStudioView.studioChips`). Written out rather
    /// than read from the enum because `StudioMenu` is `private` — and writing it out is also
    /// what lets claim 6 notice a re-sort.
    private static let strip = ["sound", "effects", "mix", "master",
                                "mood", "composition", "field", "export"]

    // MARK: - claim 1 (END-TO-END) — the policy, at both ends of the threshold

    func testTheFirstRunsCarryTheSoundChipAlone() {
        for n in 0..<SessionMaturity.simplifiedBelow {
            let m = SessionMaturity(appearances: n)
            XCTAssertTrue(m.isLearning, "appearance \(n) is below the threshold and must be learning")
            XCTAssertEqual(m.visibleChipIDs(from: Self.strip), ["sound"], """
                At \(n) appearances the strip is \(m.visibleChipIDs(from: Self.strip)) instead \
                of the Sound chip alone. C4's whole instruction is "ONE panel (Sound)" for a \
                fresh install; a strip that still carries seven settings surfaces has not \
                simplified anything, it has only added a code path that says it did.
                """)
        }
    }

    func testAnExperiencedInstallGetsTheWholeStripBackUnchanged() {
        for n in [SessionMaturity.simplifiedBelow, SessionMaturity.simplifiedBelow + 1, 999] {
            let m = SessionMaturity(appearances: n)
            XCTAssertFalse(m.isLearning, "appearance \(n) is at or above the threshold")
            XCTAssertEqual(m.visibleChipIDs(from: Self.strip), Self.strip, """
                At \(n) appearances the strip is not the full eight in their original order. \
                The reduced surface has to EXPIRE on its own — there is no "finish onboarding" \
                control anywhere, so a policy that fails to hand the instrument back leaves \
                the user permanently inside the first run.
                """)
        }
    }

    // MARK: - claim 2 (COUNTERWEIGHT, END-TO-END) — it fails OPEN, never to an empty bar

    /// The strip is the app's primary navigation. If a future rename makes the keep-list match
    /// nothing, the user must get everything rather than nothing: an un-simplified instrument
    /// is a cosmetic miss, an empty navigation bar is a broken one.
    func testAStripThatMatchesNothingComesBackWhole() {
        let renamed = ["timbre", "fx", "levels"]          // as if every case had been renamed
        let m = SessionMaturity(appearances: 0)
        XCTAssertTrue(m.isLearning)
        XCTAssertEqual(m.visibleChipIDs(from: renamed), renamed, """
            A strip containing none of the keep ids came back as \
            \(m.visibleChipIDs(from: renamed)) instead of whole. The keep-list is a set of raw \
            values that lives in a DIFFERENT file from the enum it names, so it can go stale \
            without anything failing to compile — and the failure it would then cause is a \
            front plate with no chips at all.
            """)
        XCTAssertEqual(SessionMaturity(appearances: 0).visibleChipIDs(from: []), [])
    }

    /// Removing entries is allowed; re-sorting them is not. The strip order is the signal
    /// chain and a founder-facing decision (`studioChips`' own note says so).
    func testThePolicyRemovesButNeverReorders() {
        let reversed = Array(Self.strip.reversed())
        let mature = SessionMaturity(appearances: 42)
        XCTAssertEqual(mature.visibleChipIDs(from: reversed), reversed, """
            The mature path did not return its input untouched. It must be the identity — any \
            other behaviour means the policy re-sorts a strip whose order is deliberate.
            """)
    }

    // MARK: - claim 3 (END-TO-END) — the counter cannot trap and cannot get stuck

    func testTheCounterClampsAndSaturates() {
        XCTAssertEqual(SessionMaturity(appearances: -7).appearances, 0, """
            A negative appearance count was not clamped. Negative is the one value that cannot \
            self-heal: it keeps `isLearning` true for longer than the threshold says, and no \
            amount of using the app repairs it.
            """)
        XCTAssertEqual(SessionMaturity.next(after: 0), 1)
        XCTAssertEqual(SessionMaturity.next(after: -3), 1, "a corrupt stored value must recover, not stay negative")
        XCTAssertEqual(SessionMaturity.next(after: Int.max), Int.max, """
            `next(after:)` trapped or wrapped at `Int.max`. This value comes out of \
            `UserDefaults`, which any process can be made to hold anything — a crash on launch \
            is the worst possible way to be wrong about a cosmetic threshold.
            """)
        XCTAssertEqual(SessionMaturity.next(after: Int.max - 1), Int.max)
    }

    // MARK: - claim 4 — the append must operate on the FILTERED strip

    /// See the ⭐ note in the header: appending to `studioChips` instead of `maturityChips`
    /// compiles, type-checks, and silently undoes the whole slice the first time a chrome door
    /// selects a menu.
    func testTheActiveMenuIsAppendedToTheFilteredStrip() throws {
        let body = try declarationBody(of: "private var visibleChips: [StudioMenu]")
        XCTAssertTrue(body.contains("maturityChips"), """
            `visibleChips` no longer reads `maturityChips`. If the first-run policy was moved \
            somewhere else, move this guard with it in the SAME commit (#456) — do not delete \
            it, it is the only thing standing between the policy and a silent no-op.
            """)
        XCTAssertFalse(body.contains("studioChips"), """
            `visibleChips` reads `studioChips` directly again. That is the exact defeat this \
            guard exists for: the strip would be filtered until the pulse pill or the clips \
            tile selects a menu, at which point the append hands back all eight chips and the \
            first-run surface disappears through the door a new user presses first.
            """)
        let policy = try declarationBody(of: "private var maturityChips: [StudioMenu]")
        XCTAssertTrue(policy.contains("SessionMaturity("), """
            `maturityChips` no longer constructs a `SessionMaturity`. The threshold and the \
            keep-list live in that type on purpose (#416); a second copy inline here is the \
            defect whether or not the two agree today.
            """)
        // ⚠️ THE NEEDLE MOVED WITH THE CODE (#571, same commit — #456). It was
        // `studioAppearances`, the live `@AppStorage` property. The strip now renders from
        // `launchMaturity`, a `static let` frozen for the process, because reading the live
        // counter made the eight chips POP into place mid-launch on the run that crosses the
        // threshold — the increment happens in `onAppear`, after the first body evaluation.
        XCTAssertTrue(policy.contains("Self.launchMaturity"), """
            `maturityChips` no longer reads `launchMaturity`. If it went back to the live \
            `@AppStorage` counter, the strip changes width DURING the third launch. If the \
            frozen value was renamed, move this needle with it in the same commit.
            """)
    }

    // MARK: - claim 4b (END-TO-END) — an update must not un-teach an experienced user

    /// ⛔ THE CASE #568 SHIPPED WITHOUT. The counter is newer than the app, so on every device
    /// that already has Echoel the key is ABSENT — and `UserDefaults.integer(forKey:)` answers
    /// 0 for "absent" exactly as it does for "opened zero times". Read that way, the update
    /// would have taken seven chips away from every existing user for three launches. To
    /// somebody who has been playing for months that is not onboarding, it is a broken update.
    func testAnInstallThatPredatesTheCounterIsTreatedAsExperienced() {
        XCTAssertEqual(SessionMaturity.seed(stored: nil, hasPriorState: true),
                       SessionMaturity.simplifiedBelow, """
            An install with prior state but no counter was not seeded past the threshold. That \
            is the upgrade path: absent must mean "we only started counting now", never "this \
            person has never opened the app".
            """)
        XCTAssertFalse(SessionMaturity(appearances: SessionMaturity.seed(stored: nil,
                                                                        hasPriorState: true)).isLearning)
        XCTAssertEqual(SessionMaturity.seed(stored: nil, hasPriorState: false), 0, """
            A genuinely fresh install was seeded past zero, so nobody would ever see the \
            first-run surface the whole cycle exists to build.
            """)
        XCTAssertTrue(SessionMaturity(appearances: SessionMaturity.seed(stored: nil,
                                                                       hasPriorState: false)).isLearning)
        for stored in [0, 1, 2, 7] {
            XCTAssertEqual(SessionMaturity.seed(stored: stored, hasPriorState: true), stored, """
                A counter that already exists (\(stored)) was overwritten by the seed. Re-seeding \
                a counting install would restart, or skip, the first runs on every launch — the \
                prior-state evidence is only ever a tie-breaker for "no value at all".
                """)
        }
        XCTAssertEqual(SessionMaturity.seed(stored: -4, hasPriorState: false), 0,
                       "a corrupt stored value must clamp, not persist as negative")
    }

    /// The seed's evidence must be read from a key nothing pre-registers, or it answers "prior
    /// state" on a fresh install and the first-run surface never appears for anyone.
    func testThePriorStateEvidenceIsAPrefixNothingRegisters() throws {
        XCTAssertEqual(SessionMaturity.priorStatePrefix, "studio.", """
            The prior-state evidence prefix moved. It works because NOTHING calls \
            `UserDefaults.register(defaults:)` for a `studio.` key — the app's only three \
            registrations are feature flags — so such a key exists if and only if ordinary use \
            wrote it. A prefix that something registers would make every fresh install look \
            experienced, silently.
            """)
        let code = try studioCode()
        XCTAssertTrue(code.contains("object(forKey: SessionMaturity.defaultsKey)"), """
            The launch seed no longer asks `object(forKey:)`. `integer(forKey:)` cannot tell an \
            absent key from a stored zero, and that distinction IS the upgrade path.
            """)
    }

    // MARK: - claim 5 (COUNTERWEIGHT) — nothing was stranded, and the counter counts once

    /// The reduced strip removes SETTINGS surfaces, never capabilities. Record, keep-last,
    /// MIDI export and Save live in `quickActionRow`, one line under the transport and outside
    /// the plate entirely — if that ever moves INTO a panel, this slice starts hiding the
    /// ability to save a take from exactly the users least able to find it again.
    func testTheAlwaysOnActionRowsAreStillOutsideThePlate() throws {
        let row = try declarationBody(of: "private var startControlRow: some View")
        for member in ["quickActionRow", "quickDoorRow", "BodyTempoField", "PlaybackToggleButton"] {
            XCTAssertTrue(row.contains(member), """
                `startControlRow` no longer renders `\(member)`. C4 reduces the CHIP STRIP and \
                nothing else; the transport, the tempo field and the always-on action tiles are \
                what make the reduced surface honest rather than crippling.
                """)
        }
    }

    func testTheAppearanceCounterIsWrittenOncePerProcess() throws {
        let code = try studioCode()
        XCTAssertTrue(code.contains("if !appearanceCounted {"), """
            The appearance counter is no longer guarded by `appearanceCounted`. `onAppear` can \
            fire more than once for a re-inserted root view, and an unguarded increment would \
            age the install by two per launch — the reduced surface would then expire after \
            roughly one and a half real first runs.
            """)
        // The ARGUMENT is deliberately not part of this needle (#571 changed it from the live
        // `@AppStorage` property to the frozen `launchMaturity`, and both are correct inputs).
        // What must not change is that the increment goes through the saturating helper.
        XCTAssertTrue(code.contains("SessionMaturity.next(after:"), """
            The counter no longer increments through `SessionMaturity.next(after:)`. A bare \
            `+= 1` traps on an `Int.max` stored value; this is a crash-on-launch shape, not a \
            style preference.
            """)
    }

    // MARK: - claim 6 (COUNTERWEIGHT) — the underlying strip is untouched

    /// The policy filters a strip it does not own. If `studioChips` itself were edited to
    /// implement C4, the change would be permanent instead of expiring, and `SaveDoorNaming`'s
    /// guard over `.export` would go green for a reason that no longer exists (§4).
    func testTheStandingStripStillDeclaresAllEight() throws {
        let code = try studioCode()
        guard let line = code.split(separator: "\n").first(where: { $0.contains(".sound, .effects") }) else {
            XCTFail("""
                the explicit `studioChips` array is gone from \(Self.studio). The first-run \
                policy filters that array — if the strip is built some other way now, re-anchor \
                this guard AND `SaveDoorNamingTests` in the same commit (#454).
                """)
            return
        }
        for chip in [".mix", ".master", ".mood", ".composition", ".field", ".export"] {
            XCTAssertTrue(line.contains(chip), """
                `\(chip)` left the standing strip: \(line.trimmingCharacters(in: .whitespaces))
                #568 hides chips for the first runs by FILTERING this array at render time. \
                Deleting one here is a different, permanent decision and needs its own reason.
                """)
        }
    }

    // MARK: - source access

    private struct FirstRunAnchorMissing: Error { let reason: String }

    private func studioCode() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path),
            "Sources/ not present in this checkout")
        let url = root.appendingPathComponent(Self.studio)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FirstRunAnchorMissing(reason: """
                \(Self.studio) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }

    /// The brace-matched body following `key`. Brace-matched rather than "to the next
    /// declaration": this file is 10 000 lines and deriving scope from FILE ORDER is a mistake
    /// this repo has paid for more than once (#408).
    private func declarationBody(of key: String) throws -> String {
        let text = try studioCode()
        guard let start = text.range(of: key) else {
            throw FirstRunAnchorMissing(reason: """
                \(Self.studio) no longer declares `\(key)`. Re-anchor this scan — a silent skip \
                here would leave the first-run policy unguarded (#454).
                """)
        }
        guard let open = text[start.upperBound...].firstIndex(of: "{") else {
            throw FirstRunAnchorMissing(reason: "no opening brace after `\(key)`")
        }
        var depth = 0
        var i = open
        var out = ""
        while i < text.endIndex {
            let c = text[i]
            if c == "{" { depth += 1 }
            if c == "}" {
                depth -= 1
                if depth == 0 { return out }
            }
            out.append(c)
            i = text.index(after: i)
        }
        throw FirstRunAnchorMissing(reason: "unbalanced braces after `\(key)` in \(Self.studio)")
    }
}
