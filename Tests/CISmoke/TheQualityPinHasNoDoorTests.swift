// TheQualityPinHasNoDoorTests.swift
// Echoel — a doc comment that names the user and the use case for a branch that never runs. #727.
//
// WHAT WAS WRONG. `ResourceGovernor.isAutomatic` is `public var … = true` and its doc said a
// performer "can pin a tier (e.g. force High for a show)". Comments stripped, the name occurs
// THREE times in `Sources/`: the declaration, **`manualTier`'s** `didSet`, and the `guard` in
// `recompute()`. No writer, no binding, no control in any shipped path.
//
// ⛔ TWO PARTS OF THAT SENTENCE WERE WRONG WHEN #728 SHIPPED IT (#729). It said "its own
// `didSet`" — `isAutomatic`'s own `didSet` is `didSet { recompute() }` and does not contain
// the name; the third occurrence belongs to `manualTier`. And it cited
// `git grep -c isAutomatic -- Sources` for the number THREE: that flag counts LINES and
// strips nothing, so it prints the code occurrences PLUS every comment line quoting them —
// the recipe contradicted the number it was cited for, the `EchoelModalBank` shape, one
// commit after this file quoted that lesson.
//
// ⚠️ NO RAW COUNT IS WRITTEN DOWN HERE ON PURPOSE. #729's own first draft replaced the
// recipe with the measured value 7 and made it 8 in the same commit, by adding these very
// lines. A count that this file's OWN prose moves is a date, not a fact; only the code
// occurrence count is stable, and the way to get it is to strip comments first:
//     python3 - <<'EOF'
//     import sys; sys.path.insert(0,'scripts'); import doctor
//     t=open('Sources/Echoelmusic/Core/ResourceGovernor.swift').read()
//     print(doctor._code_only(t).count('isAutomatic'))
//     EOF
//
// ⚠️ AND IT GOES ONE STEP FURTHER THAN THE BREATH-PLAY FINDING (#724/#725), which is why it is
// its own guard rather than a second claim there. There, a permanently-true flag meant the
// feature ALWAYS ran. Here, no shipped path sets the flag false, so the
// `guard isAutomatic else { apply(…manualTier) }` branch never runs in the product — and
// `manualTier`, whose only read lives inside it, cannot affect the app. The manual-override
// half of a live class is unreachable, and the doc described it to a performer in the present
// tense.
//
// ⛔ SCOPE MATTERS AND #727 DROPPED IT MID-SENTENCE (#728). Its measurement said "across
// `Sources/`" and its conclusions then said "no writer", "permanently true", "can never affect
// anything" — repo-wide claims from a directory-wide measurement, the shape this repo names
// after `EchoelModalBank`. There IS one writer:
// `Tests/EchoelmusicTests/PollingLoopTests.testResourceGovernor_publishesTheCeilingForAPinnedTier`
// pins `isAutomatic = false` and steps `manualTier` so its `bioHz` assertion is
// device-independent. The branch is therefore not dead code — it is the only deterministic way
// to drive this class. ⚠️ That suite is compiled by NO gate (#208), so nothing goes red when it
// breaks; that is a reason to NAME the writer, not to overlook it.
//
// ⭐ THE AUTOMATIC HALF IS LIVE, WHICH IS WHY CLAIMS 4 AND 5 EXIST. `EchoelmusicApp` constructs
// the governor, `MetalBioView` takes it from `@Environment`, `ExternalStageBridge` wires it,
// and CLAUDE.md records `bioHz` → `OSCSender` as its one wired consumer. Nothing here argues
// for deletion — what is missing is the DOOR. Without the counterweights, "remove the unused
// manual-tier code" would pass claims 1-3 and quietly answer a founder question.
//
// ⚠️ IT FORBIDS NOTHING (#364). Pinning a tier for a show is a real live-performance need;
// whether it should exist is the founder's call. (⛔ #727 wrote "two lines from working" and
// that was an unmeasured number inside a block about unmeasured numbers: `manualTier` defaults
// to `.balanced`, so a bare toggle pins BALANCED and cannot "force High" — the example given
// three lines away. A working pin needs the toggle, a `QualityTier` picker AND a reachable
// panel, and the presentation-modifier ceiling makes the last one the expensive part.) On
// the day a writer appears, claim 2 goes red BY DESIGN and its message names the ⛔ block in
// `ResourceGovernor.swift` that must move in the same commit (#456).
//
// ⛔ CLAIM 2 SCANS FOR THE NAME, NOT FOR WRITE SHAPES — the #725 lesson, paid for one slice
// ago. `ResourceGovernor` is `@MainActor @Observable`, so the realistic door is
// `@Bindable var g = governor` + `Toggle(…, isOn: $g.isAutomatic)`, i.e. the text
// `$g.isAutomatic` — which a needle list of `isAutomatic =`, `$isAutomatic`,
// `isAutomatic.toggle()` all miss. Enumerating write shapes is a guess about the future; the
// name is not. Zero occurrences outside the declaring file today, so the total scan is green.
//
// ⚠️ A MISSING ANCHOR FAILS, A MISSING TREE SKIPS (#454), and the walk asserts it actually saw
// the declaring file — a rename would otherwise leave claim 2 reporting "no writers" for a
// flag that still exists.
//
// ⚠️ HONEST GRADING (#433/#464/#486). This file names no symbol the slice adds, so it compiles
// against both trees and every assertion has a verdict. Hand-transcribed (a Python rebuild of
// `SourceText.codeOnly` driven against `git show <parent>:` and the worktree) — a CI round
// trip is a lottery ticket, not a check (#686):
//   · Against `bf069b8` — the tree BEFORE #727 built the doc block: **1 REGRESSION**, claim 1,
//     the promise "can pin a tier" present and unretracted; claim 1b red there too but by
//     ANCHOR ABSENCE — one absence, reported once (#486), not a second finding.
//   · ⛔ AGAINST THE ACTUAL PARENT THERE ARE NONE, and #728's header did not say so (#729).
//     `bf069b8` is the GRANDparent. Driven against `bedfd37`, every claim is green: #728 was
//     a pure prose-and-guard rewrite. "1 REGRESSION" is a true statement about a tree that is
//     named — and the number a reader carries away is not that commit's.
//   · **4 COUNTERWEIGHTS** green on both trees: no writer outside the file (2), the
//     unreachable branch still exists (3), the automatic half is still constructed (4) and
//     consumed (5). Green on both is the point, not padding (#343). Six test methods.
//   · Against `8af1934`, THIS slice's parent: **all six green**, ZERO regressions — #729 is a
//     prose repair plus one withdrawal, and it says so rather than borrowing an older tree's
//     number. Driven with a Python transcription of `SourceText.codeOnly` over
//     `git show 8af1934:` and the worktree; the walk saw 369 files and the declaring file on
//     both. The repaired claim 1 was additionally probed on two DELIBERATELY broken trees:
//     a re-wrap that splits the quote off the marker line is GREEN under the new block rule
//     and RED under #728's same-line rule (the defect), and a fresh promise placed away from
//     any retraction is RED under both (#367 — it can still fail for its named reason).
//   · SOURCE-TEXT SCAN throughout (§1). Nothing here drives the governor: `recompute()` is
//     private and the class is `@MainActor`.
//
// ⚠️ IS THE STRIPPER LOAD-BEARING? Required by `Tests/CISmoke/CLAUDE.md` §2, and #725 omitted
// it. Measured today: **PROPHYLAKTISCH — 0 of 5 verdicts flip**.
//
// ⛔ #728 PRINTED THAT SAME LABEL WHILE IT WAS FALSE, AND ITS OWN SLICE IS WHAT MADE IT FALSE
// (#729). `isAutomatic` occurs MORE times raw in `ResourceGovernor.swift` than the THREE in
// code — the ⛔ blocks quote it, and the exact raw figure moves whenever anyone edits them,
// so the occurrence-count claim #728 wrote was red without `codeOnly` — `TRAGEND (1 of 6)`,
// in the flattering direction, and the counterfactual paragraph below names claims 3 and 5
// as the protected ones and never names the only one that actually was. The label is true
// again only because #729 withdrew that claim (see below); saying so is the point, because
// a measurement that becomes true by deleting its subject is not the same as one that was
// right. COUNTERFACTUALLY the stripper is still load-bearing for two claims: raw text contains
// `guard isAutomatic else` in a COMMENT (this file's own header quotes it, and so does the ⛔
// block in `ResourceGovernor.swift`), so without `codeOnly` claim 3 would stay green if the
// real branch were deleted and the prose kept — the precise scenario it exists for. Likewise
// raw `ResourceGovernor` matches `AdaptiveQuality.swift`, `EngineBus.swift` and
// `PollingLoop.swift`, all of which name it only in comments, so claim 5 would pass on prose.
// Claim 1 reads RAW text on purpose: the retraction quotes the withdrawn phrase, and the
// stripper would blank the very line the per-line `SAID` exemption exists to recognise.
//
// ⚠️ AND THE LIMIT FIRST. This proves no line in `Sources/` can turn automatic governing off,
// and that the prose agrees. It proves nothing about thermal behaviour on a device.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheQualityPinHasNoDoorTests: XCTestCase {

    private struct QualityAnchorMissing: Error, CustomStringConvertible {
        let reason: String
        var description: String { "quality-pin anchor missing: \(reason)" }
    }

    private static let governorRelative = "Echoelmusic/Core/ResourceGovernor.swift"
    private static let governor = "Sources/" + governorRelative

    // MARK: - 1: the doc no longer promises a performer control

    /// ⛔ THE EXEMPTION IS BLOCK-SCOPED, NOT LINE-SCOPED (#729). #728 required `SAID` on the
    /// SAME raw line as the phrase, and the one line that satisfies both is 89 characters
    /// wide against a wrap that sits near 96 — an ordinary re-wrap pushing the quote onto the
    /// next line would have made this red on a correct tree. That is the exact failure §6 of
    /// #728 cited when it SHORTENED claim 1b's needle; the repair was applied to 1b and not
    /// to claim 1, which is the more exposed of the two. A quote is exempt if the retraction
    /// marker stands on its own line or within the three lines above it.
    func testTheDocNoLongerPromisesAPin() throws {
        let phrase = "can pin a tier"
        let raw: String = try rawText(Self.governor)
        let lines: [String] = raw.components(separatedBy: "\n")
        let offenders: [String] = lines.indices
            .filter({ i in
                guard lines[i].contains(phrase) else { return false }
                let from = max(0, i - 3)
                return !lines[from...i].contains(where: { $0.contains("THIS LINE SAID") })
            })
            .map({ lines[$0] })
        XCTAssertTrue(offenders.isEmpty, """
            `ResourceGovernor` promises again that a performer "\(phrase)", outside a \
            retraction:
            \(offenders.joined(separator: "\n"))
            Nothing in `Sources/` writes `isAutomatic`, so the branch that would honour a pin \
            never runs. If a control HAS been built, claim 2 is red in this same run and the \
            ⛔ block above the declaration is the work.
            """)
    }

    /// 1b — without this, deleting the whole ⛔ block passes every other claim while the
    /// measurement that justifies keeping the code is gone: "kept the LINE, lost the FACT" (#343).
    func testTheRetractionItselfIsStillOnRecord() throws {
        let raw: String = try rawText(Self.governor)
        // The needle lives on ONE line by construction — a two-line quote matches nothing and
        // is red on a correct tree (#725 made exactly that mistake and caught it in simulation).
        XCTAssertTrue(raw.contains("THIS LINE SAID"), """
            The ⛔ retraction above `isAutomatic` is gone from \(Self.governor).

            If a door was built, that block SHOULD change — but then claim 2 is red too and \
            the replacement text is the work. If it was merely deleted, nothing records that \
            the manual-override branch is unreachable.
            """)
    }

    // MARK: - 2: THE FINDING — nothing outside the declaring file names the flag

    func testNothingOutsideTheDeclaringFileNamesTheFlag() throws {
        let writers: [String] = try filesNaming("isAutomatic")
        XCTAssertTrue(writers.isEmpty, """
            `isAutomatic` is now named outside `ResourceGovernor.swift`, in: \
            \(writers.joined(separator: ", ")).

            That is GOOD NEWS if it is a real door — this guard does NOT forbid building one \
            (#364); its red is what tells you one was built. \
            It fires on a mere READ too, deliberately: a needle list of write shapes misses \
            `$g.isAutomatic`, the `@Observable` binding that is the likeliest door of all \
            (#725). The repair is not to relax this: move the ⛔ block above the declaration \
            in `ResourceGovernor.swift` in the SAME commit (#456).
            """)
    }

    // ⛔ CLAIM 2b IS WITHDRAWN ONE COMMIT AFTER IT WAS WRITTEN (#729), and the reason is
    // #364 rather than a typo. It asserted that `isAutomatic` occurs EXACTLY THREE times in
    // the declaring file's code, to catch a door built inside the one file claim 2 skips.
    // Simulated against the worktree, it goes red on two ordinary, CORRECT edits:
    //   · simplifying `manualTier`'s `didSet { if !isAutomatic { recompute() } }` to
    //     `didSet { recompute() }` — a legitimate simplification, since `recompute()` already
    //     gates on the flag — drops the count to 2, and the message would report "the flag or
    //     its gate was removed". Neither was.
    //   · the standard `oldValue` de-duplication on `isAutomatic`'s OWN `didSet` raises it to
    //     4, and the message would report "a door built inside the declaring file". False.
    // Both are #367 in its stated mirror form: red for a reason other than the one the message
    // gives — and the prescribed repair ("move the ⛔ block, do not change this number") is
    // wrong for both. A guard that reds correct work gets deleted and takes the law with it
    // (#364), so the LAW is kept in prose here and in the ⛔ block above the declaration: the
    // one file claim 2 skips is a Foundation-only model file with no SwiftUI import, where the
    // realistic door shapes claim 2 hunts for cannot occur.
    //
    // ⚠️ AND THE #416 CITATION IT CARRIED WAS INVERTED. It justified the number by saying it
    // "asserts the same THREE the ⛔ block states — one number, one definition (#416)". #416
    // forbids the second spelling; the claim WAS the second spelling, and with its message it
    // made five.

    // MARK: - 3: COUNTERWEIGHT — the branch the finding is about still exists

    /// Without this, deleting the manual-override branch would pass claims 1-2 trivially and
    /// answer a founder question ("should a performer be able to pin a tier?") by removal.
    func testTheUnreachableManualBranchStillExists() throws {
        let code: String = try codeOf(Self.governor)
        XCTAssertTrue(code.contains("guard isAutomatic else"), """
            `recompute()` no longer guards on `isAutomatic`.

            Deleting it does two things. It breaks \
            `PollingLoopTests.testResourceGovernor_publishesTheCeilingForAPinnedTier`, the one \
            test proving `bioHz` reaches `PollingRateCeiling` — and that suite is compiled by \
            NO gate (#208), so nothing else would tell you. And it decides a founder question \
            by cleanup: pinning a tier for a show is a real live-performance need. If the \
            branch was merely reformatted, re-anchor this needle on the new spelling — an \
            unanchored scan is the #367 defect.
            """)
        XCTAssertTrue(code.contains("AdaptiveQuality.settings(for: manualTier)"), """
            The unreachable branch no longer applies `manualTier`, so the second half of the \
            finding (a property whose only read is inside a branch that never runs) can no \
            longer be stated from this file.
            """)
    }

    // MARK: - 4/5: COUNTERWEIGHTS — the automatic half really is live

    /// The finding is "no door", not "dead class". If the governor stopped being constructed,
    /// this would be a different and much larger finding.
    func testTheGovernorIsStillConstructedAtLaunch() throws {
        let app: String = try codeOf("Sources/Echoelmusic/EchoelmusicApp.swift")
        XCTAssertTrue(app.contains("ResourceGovernor()"), """
            `EchoelmusicApp` no longer constructs a `ResourceGovernor`.

            The whole finding rests on this class being LIVE with one half unreachable. If it \
            is no longer built at launch, the ⛔ block above `isAutomatic` overstates what is \
            running and must be rewritten, not this assertion.
            """)
    }

    func testTheGovernorStillHasAConsumer() throws {
        let consumers: [String] = try filesNaming("ResourceGovernor")
        XCTAssertFalse(consumers.isEmpty, """
            No file outside `ResourceGovernor.swift` names the type at all.

            Its live consumers are the reason "the automatic half is live" is written above \
            (`MetalBioView` via `@Environment`, `ExternalStageBridge.wire`, and the app \
            entry point). With none, this is not a missing door — it is an unreachable class, \
            a different finding that belongs in CLAUDE.md's doorless register.
            """)
    }

    // MARK: - helpers

    /// Files under `Sources/` whose code (comments stripped) names `needle`, excluding the
    /// declaring file by exact relative path — `hasSuffix` would also excuse a future
    /// `LegacyResourceGovernor.swift` anywhere in the tree.
    private func filesNaming(_ needle: String) throws -> [String] {
        let base = try repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: base.path) else {
            throw QualityAnchorMissing(reason: "cannot walk Sources/")
        }
        var hits: [String] = []
        var seen = 0
        var sawDeclaringFile = false
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            seen += 1
            if rel == Self.governorRelative {
                sawDeclaringFile = true
                continue
            }
            let text: String = SourceText.codeOnly(
                try String(contentsOf: base.appendingPathComponent(rel), encoding: .utf8))
            if text.contains(needle) { hits.append(rel) }
        }
        guard seen > 200 else {
            throw QualityAnchorMissing(reason: """
                only \(seen) Swift files walked under Sources/; the tree holds well over three \
                hundred, so this walk saw a partial checkout and would report a green it did \
                not earn (#454)
                """)
        }
        guard sawDeclaringFile else {
            throw QualityAnchorMissing(reason: """
                \(Self.governorRelative) was not among the \(seen) files walked — it moved or \
                was renamed. This FAILS rather than skips: a rename would otherwise leave \
                claim 2 reporting "no writers" for a flag that still exists (#454)
                """)
        }
        return hits.sorted()
    }

    private func codeOf(_ relativePath: String) throws -> String {
        SourceText.codeOnly(try rawText(relativePath))
    }

    private func rawText(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw QualityAnchorMissing(reason: """
                \(relativePath) is not present while `Sources/` is — the anchor moved. A \
                missing TREE skips (see `repoRoot`); a missing ANCHOR fails (#454)
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources").path) else {
            throw XCTSkip("source tree not present under \(root.path)")
        }
        return root
    }
}
