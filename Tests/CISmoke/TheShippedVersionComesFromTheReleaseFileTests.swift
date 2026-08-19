// TheShippedVersionComesFromTheReleaseFileTests.swift
// Echoel — #635: the deploy loop's version plumbing, as an executable law.
//
// WHAT THIS GUARDS. The TestFlight loop is tokenless: bumping `.deploy/release` and pushing
// IS the deploy. Two numbers reach the founder's phone from that push, and both are written
// into `project.yml` by `.github/workflows/testflight.yml` — a founder-gated file this bundle
// may read but never edit. They arrive by DIFFERENT routes, and the first draft of this
// header flattened both into "a grep/sed pair", which the bullet under it already refuted:
//
//   · the MARKETING version is DERIVED from a file —
//       `grep -m1 -oE 'v[0-9]+\.[0-9]+\.[0-9]+' .deploy/release`
//     then applied by `sed s/MARKETING_VERSION: "[0-9.]*"/…/ project.yml`.
//   · the BUILD number is TAKEN from the run — `BUILD_NUMBER: ${{ github.run_number }}` —
//     and applied by a different sed against `CURRENT_PROJECT_VERSION`. No grep anywhere.
//
// ⛔ EVERY FAILURE MODE OF THAT CHAIN IS SILENT. The workflow wraps the version derivation in
// `if [ -n "$DEPLOY_VER" ]`, so a `.deploy/release` with no `vX.Y.Z` does not fail the deploy —
// it ships whatever literal is sitting in `project.yml`, today `10.79.372`, thirty-eight
// releases behind. The `sed` is likewise a no-op if `project.yml` ever spells the key
// differently (unquoted, or with a suffix): green run, green upload, stale version on the
// device, and nothing anywhere says so. The founder would read the header of a build he was
// asked to probe and see a version that is not the one he was sent.
//
// ⚠️ THE FIRST-MATCH LAW IS NOT COSMETIC. `grep -m1` takes the first `vX.Y.Z` in the WHOLE
// file, not the one on line 1 — the release notes routinely name predecessors, and that is why
// `.deploy/release` says in its own prose that predecessors are written WITHOUT the `v`.
// One `v` typed into a note above the intended version silently ships that older version.
// Claim 5 proves both halves of this on synthetic input, so claim 2 cannot be vacuous.
//
// KIND (§1): SOURCE-TEXT SCAN over three files (`.deploy/release`, `project.yml`,
// `.github/workflows/testflight.yml`) plus one pure re-implementation of the shell
// derivation. Nothing here runs a workflow, and nothing here proves a build shipped —
// it proves what the workflow would READ.
//
// GRADING (#433 / §3). **The file does not exist on the parent (6ae549c), so NO assertion has
// a verdict there** — §3's escape hatch applies and this is hand-transcription, not a delta.
// Transcribed: the three files it reads are byte-identical on parent and worktree, so all six
// claims would be green there too. In §3's four categories: **0 REGRESSIONS · 0 red-by-
// ANCHOR-ABSENCE · 6 COUNTERWEIGHTS**, of which claim 5 is additionally a **FORWARD** guard —
// it drives `deriveVersion`, a function this commit creates, so it could never have been red.
// Stated up front because booking a counterweight as a regression is the flattering-direction
// defect §3 names. (An earlier draft invented the labels "pin" and "fixture"; §3 has four
// categories and inventing a fifth is how a grading paragraph stops being comparable.)
//
// ⚠️ CLAIM 6 IS EXPECTED TO GO RED ONE DAY, AND THAT IS THE POINT (#364 — it forbids
// nothing). `github.run_number` does not increment on a re-run, so re-running a failed
// TestFlight deploy uploads a DUPLICATE build number and App Store Connect rejects it. The
// repair lives in a founder-gated file. When it lands, this claim goes red and its message
// names the prose that must move in the same commit.

import Foundation
import XCTest

final class TheShippedVersionComesFromTheReleaseFileTests: XCTestCase {

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func text(_ relative: String) throws -> String {
        let url = repoRoot().appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("""
                \(relative) is missing. This guard covers the only path a build reaches the \
                founder's device by; a missing file is a RED, never a skip — a skip would \
                report a healthy deploy chain for a chain it never looked at.
                """)
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The shell pipeline `grep -m1 -oE 'v[0-9]+\.[0-9]+\.[0-9]+' FILE | head -1 | tr -dc '0-9.'`,
    /// re-implemented: take the FIRST match in file order, drop its leading `v`.
    /// ⚠️ `-m1` itself is spelled differently by the two greps — GNU stops after the first
    /// matching LINE, BSD (which is what a macOS runner actually runs) after the first MATCH —
    /// and the difference is invisible here because `head -1` collapses both to the same
    /// single token. The doc used to assert the GNU reading as if it were the runner's.
    /// Returns the version without its `v`, plus the 1-based line it came from.
    private func deriveVersion(from file: String) -> (version: String, line: Int)? {
        guard let re = try? NSRegularExpression(pattern: "v[0-9]+\\.[0-9]+\\.[0-9]+") else {
            return nil   // a literal pattern; unreachable, but never force-try in this repo.
        }
        for (index, line) in file.components(separatedBy: "\n").enumerated() {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let m = re.firstMatch(in: line, range: range),
                  let r = Range(m.range, in: line) else { continue }
            return (String(line[r].dropFirst()), index + 1)
        }
        return nil
    }

    // MARK: - Claim 1 — the derivation finds a version at all

    func testTheReleaseFileYieldsAVersion() throws {
        let release = try text(".deploy/release")
        guard let derived = deriveVersion(from: release) else {
            XCTFail("""
                `.deploy/release` contains no `vX.Y.Z`. The workflow guards its sed with \
                `if [ -n "$DEPLOY_VER" ]`, so this does NOT fail the deploy — it ships \
                `project.yml`'s literal MARKETING_VERSION instead, silently and with a green \
                run. Put the version back on line 1 in the form `build: vX.Y.Z — …`.
                """)
            return
        }
        XCTAssertEqual(derived.version.split(separator: ".").count, 3,
                       "Derived version '\(derived.version)' is not three dot-separated parts.")
    }

    // MARK: - Claim 2 — it comes from line 1, which is where the file says it must

    func testTheDerivedVersionComesFromLineOne() throws {
        let release = try text(".deploy/release")
        guard let derived = deriveVersion(from: release) else { return }   // claim 1 owns this
        XCTAssertEqual(derived.line, 1, """
            The first `vX.Y.Z` in `.deploy/release` is on line \(derived.line), not line 1, \
            so the deploy would ship `\(derived.version)`. `grep -m1` reads the WHOLE file: a \
            `v` typed in front of a predecessor version inside the notes wins over the one on \
            line 1. Write predecessors without the `v` — the file's own prose says so.
            """)
    }

    // MARK: - Claim 3 — the workflow still derives it that way, and derive/patch stay paired

    func testTheWorkflowStillUsesThisDerivation() throws {
        let wf = try text(".github/workflows/testflight.yml")
        let grepAnchor = #"grep -m1 -oE 'v[0-9]+\.[0-9]+\.[0-9]+' .deploy/release"#
        let sedAnchor = #"MARKETING_VERSION: \"[0-9.]*\""#
        let greps = wf.components(separatedBy: grepAnchor).count - 1
        let seds = wf.components(separatedBy: sedAnchor).count - 1

        // ⚠️ NOT a count pin (#364). The first draft asserted `== 2` — "compile_check + ios" —
        // and would therefore have gone RED on this same slice's own second-ranked proposal
        // (dropping the compile_check job from the deploy path), while the thing this claim is
        // NAMED for — the ios job still deriving the version this way — stayed true. Its repair
        // message was wrong too: it told a future session to re-derive claims 1, 2 and 5, which
        // removing a job does not touch. The real invariant is the PAIRING: at least one job
        // derives, and every job that patches `project.yml` derives its value the same way.
        XCTAssertGreaterThanOrEqual(greps, 1, """
            `testflight.yml` no longer derives the version from `.deploy/release` at all. \
            Claims 1, 2 and 5 model THAT derivation and would be guarding a pipeline that is \
            gone — re-derive them against the new one in the same commit.
            """)
        XCTAssertEqual(greps, seds, """
            `testflight.yml` derives the version \(greps) time(s) but patches `project.yml` \
            \(seds) time(s). Those must pair: a job that patches without deriving writes a \
            stale value, and a job that derives without patching builds a version nobody \
            sees. Removing a job is fine — removing one half of its pair is not.
            """)
    }

    // MARK: - Claim 4 — the sed target still exists, spelled the way the sed expects

    func testProjectYmlStillMatchesTheSedTarget() throws {
        let proj = try text("project.yml")
        let matching = proj.components(separatedBy: "\n").filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("MARKETING_VERSION: \""), t.hasSuffix("\"") else { return false }
            let value = t.dropFirst("MARKETING_VERSION: \"".count).dropLast()
            return !value.isEmpty && value.allSatisfy { $0.isNumber || $0 == "." }
        }
        // ⚠️ ZERO is the hazard, not "more than one" (#367). An earlier draft asserted `== 1`
        // and justified it with "more than one means the targets can drift apart" — which the
        // sed cannot do: it carries no address and no `/g`, so it rewrites the first match on
        // EVERY line, and two such lines would both receive the same version. The false
        // rationale also made the claim forbid correct work: a per-target MARKETING_VERSION on
        // the Watch or Widgets target is a legitimate future edit, not a defect.
        XCTAssertGreaterThanOrEqual(matching.count, 1, """
            `project.yml` has NO line spelled `MARKETING_VERSION: "<digits and dots>"`, but \
            the workflow's `sed s/MARKETING_VERSION: "[0-9.]*"/…/` needs exactly that quoted, \
            digits-only form — unquote the value or give it a suffix and the sed becomes a \
            silent no-op. This is the loudest of the silent failures: green run, green upload, \
            stale version in the app header, and nothing anywhere says so.
            """)
    }

    // MARK: - Claim 5 — the derivation is the shell's, proven on synthetic input

    func testTheDerivationIgnoresBareVersionsAndObeysStrayVs() {
        let workaround = """
            build: v10.79.411 — headline
            notes: |
              Der Vorgänger ist 10.79.410 (2527) — davor 10.79.409.
            """
        XCTAssertEqual(deriveVersion(from: workaround)?.version, "10.79.411",
                       "A predecessor written WITHOUT the `v` must not win. That workaround " +
                       "is the documented way to name older builds in the notes; if this " +
                       "fails, the release file's prose is telling the founder a lie.")

        let hazard = """
            build: v10.79.411 — headline
            notes: |
              siehe v9.0.0
            """
        XCTAssertEqual(deriveVersion(from: hazard)?.version, "10.79.411",
                       "A stray `v` BELOW line 1 must lose — grep -m1 stops at the first " +
                       "matching LINE.")

        let tripped = """
            # siehe v9.0.0
            build: v10.79.411 — headline
            """
        XCTAssertEqual(deriveVersion(from: tripped)?.version, "9.0.0",
                       "A stray `v` ABOVE line 1's version must WIN — that is exactly the " +
                       "hazard claim 2 exists to catch. If this returns 10.79.411 the " +
                       "derivation has stopped copying the shell and claim 2 is vacuous.")

        XCTAssertNil(deriveVersion(from: "build: 10.79.411 — no v anywhere"),
                     "Without a `v` the shell derives nothing and the deploy silently keeps " +
                     "project.yml's literal. Claim 1 catches that on the real file.")
    }

    // MARK: - Claim 6 — the build number, and the re-run defect it carries

    func testTheBuildNumberIsStillTheRunNumber() throws {
        let wf = try text(".github/workflows/testflight.yml")
        XCTAssertTrue(wf.contains("BUILD_NUMBER: ${{ github.run_number }}"), """
            `BUILD_NUMBER` is no longer `github.run_number`. THIS GOING RED IS PROBABLY GOOD \
            NEWS (#364 — nothing here forbids the fix): `run_number` does NOT increment when a \
            run is re-run, so re-running a failed deploy uploads a duplicate build number and \
            App Store Connect rejects it, which is why a failed deploy has always needed a \
            fresh `.deploy/release` bump instead of a re-run. If that has been repaired, pull \
            the prose along in the same commit: this header, and the deploy-loop section of \
            `scratchpads/PLAN_TESTFLIGHT_LOOP_2026-08-19.md`.
            """)
    }
}
