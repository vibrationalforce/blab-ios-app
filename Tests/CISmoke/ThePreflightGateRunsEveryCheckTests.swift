// ThePreflightGateRunsEveryCheckTests.swift
// Echoel — #1034. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// WHAT THIS RECORDS. `scripts/preflight-check.sh` is the written-down deploy checklist:
// 11 sections, 45 verdict calls (22 pass + 8 warn + 15 fail, counted 2026-09-06). Until
// this commit it reached exactly ONE of them and then died, on every machine, always with
// exit 1. Three defects, all of the same family — the instrument did not tell the truth:
//
//   1. `set -e` + `((PASSED++))`. The arithmetic-command form returns the value BEFORE the
//      increment, so the very first `pass()` — with PASSED still 0 — evaluates to 0, bash
//      calls that a non-zero exit status, and `set -e` kills the script. Measured: it
//      printed "[PASS] Package.swift exists" and stopped. The other 44 verdicts never ran.
//   2. `REQUIRED_LANES=("beta" "beta_watchos" "beta_tvos" "beta_visionos")` — NOT ONE of
//      those four lanes has ever existed in this Fastfile. The real names are
//      `setup_signing` / `upload` / `upload_watchos` / … So the moment defect 1 was fixed,
//      the script produced four phantom FAILs, which is the WORSE state: a gate that runs
//      and lies reads as a real problem, where a gate that never spoke reads as nothing.
//   3. `swift package describe` ran unguarded and reported a missing TOOLCHAIN as "Swift
//      package has errors". Every web session and this container have no `swift`. The
//      XcodeGen and Fastlane sections twelve lines below already treated an absent tool as
//      a WARN, so the file contradicted itself.
//
// ⚠️ THE PROPORTION MATTERS, and claim 5 is why this file is a record and not an alarm.
// Measured: `grep -rl preflight-check .github/` → 0, and no script and no slash command
// calls it either (`/testflight-deploy` carries its own hand-written checklist). This
// script has ZERO callers. So the lying gate never blocked a deploy and never let a bad
// one through — it lied to a human standing at a terminal, who would have read exit 1 as
// "something is broken" and had no way to see that 44 checks simply never ran. Delete
// claim 5 and this finding changes severity; that is exactly why it is pinned.
//
// ⛔ THIS GUARD FORBIDS NOTHING (#364). Claim 3 does not freeze the lane LIST — it derives
// the expected names from the script itself and asks the Fastfile whether each one is real.
// Renaming a lane, adding one, or dropping one stays legal; what stops being legal is the
// two files disagreeing. Claim 5 goes red the day someone WIRES this script into CI, and a
// red there is good news — its message names the prose to pull along in the same commit
// (#456).
//
// ⚠️ WHY THIS FILE READS ITS TARGET RAW. `SourceText.codeOnly` is a SWIFT stripper; in bash
// the comment character is `#` and `//` never appears, so running it here would mangle the
// file. Adding a shell stripper would break the one-stripper rule (#453). Instead every
// needle that must not match a comment is LINE-ANCHORED (`^\s*`), which a `#`-comment
// mention cannot satisfy because the `#` comes first. Verified against the file's own
// comment blocks, which quote the retracted `((PASSED++))` form on purpose.
//
// ⚠️ HONEST LIMITS. This proves what the SCRIPT SAYS, never that a deploy is safe. It does
// not run the script (no bash guarantee inside XCTest here) and it cannot know whether the
// 45 checks are the RIGHT 45 — only that they are now reachable and that the two files they
// straddle agree. Whether TestFlight accepts the build is measured on Apple's side.
//
// ⚠️ ONE PROSE LINE IS WORTH KNOWING ABOUT AND IS DELIBERATELY NOT EDITED HERE. CLAUDE.md's
// TestFlight paragraph says "preflight confirms App Store Connect secrets are present and
// valid". Two separate things: (a) while the counter bug stood, that section never ran at
// all, so the sentence described a check that had not happened; (b) even now the script
// only greps testflight.yml for the four secret NAMES — a reference is not a validity
// proof, which lives with Apple. The sentence is not FALSE today (its real evidence is the
// four successful runs it also names), so correcting it would spend from the 938 bytes of
// headroom under the 150,000 B ceiling on a claim that already holds. Recorded here
// instead, where the next reader of this script will find it.
//
// ⭐ GRADING (§3). Needles transcribed in Python against both trees. Claims 2, 3 and 4 are
// FORWARD — each is red at the parent commit by the exact defect it names. Claims 1 and 5
// are COUNTERWEIGHTS, green at the parent too, and that is the point: they record a
// standing state rather than creating one.

import Foundation
import XCTest
@testable import Echoelmusic

final class ThePreflightGateRunsEveryCheckTests: XCTestCase {

    private static let script = "scripts/preflight-check.sh"
    private static let fastfile = "fastlane/Fastfile"

    // MARK: - 1: the anchor

    /// Without this, every negative below is vacuous (#454): a deleted or rewritten script
    /// would make "contains no broken increment" trivially true.
    func testTheScriptExistsAndStillFailsFast() throws {
        let sh = try rawFile(Self.script)
        XCTAssertNotNil(sh.range(of: #"(?m)^set -e\s*$"#, options: .regularExpression), """
            `set -e` is gone from \(Self.script). That is not automatically wrong, but it \
            removes the premise of claim 2 — a bare `((X++))` is only fatal under `set -e`. \
            Re-anchor this file rather than letting its negatives pass empty.
            """)
        for helper in ["pass()", "warn()", "fail()"] {
            XCTAssertTrue(sh.contains(helper), """
                The `\(helper)` verdict helper is gone. This file is a statement about how \
                those three count; re-anchor it.
                """)
        }
    }

    // MARK: - 2: the finding — a counter must not be able to kill the run

    /// ⭐ `((X++))` returns the PRE-increment value. At 0 that is a non-zero exit status and
    /// `set -e` ends the script — on its own first success.
    func testNoCounterUsesTheBareArithmeticCommandForm() throws {
        let sh = try rawFile(Self.script)
        XCTAssertNil(sh.range(of: #"(?m)^\s*\(\([A-Za-z_]+\+\+\)\)\s*$"#,
                              options: .regularExpression), """
            A bare `((NAME++))` statement is back in \(Self.script). Under `set -e` this \
            aborts the whole run the first time the counter is 0 — which is the first \
            verdict of the first section. Use `NAME=$((NAME + 1))`; an assignment always \
            exits 0. (Line-anchored, so the retraction comment quoting the old form does \
            not trip this.)
            """)
        XCTAssertTrue(sh.contains("PASSED=$((PASSED + 1))"), """
            The assignment form of the PASSED counter is gone. If the counting was \
            reworked, re-anchor claim 2 — do not leave it asserting the absence of a form \
            nothing uses any more.
            """)
    }

    // MARK: - 3: the two files must agree about lane names

    /// ⭐ THE SELF-MAINTAINING ONE. Reads the names the script demands, asks the Fastfile
    /// whether each exists. Catches a phantom name AND a future rename, from either side.
    func testEveryRequiredLaneActuallyExistsInTheFastfile() throws {
        let sh = try rawFile(Self.script)
        let ff = try rawFile(Self.fastfile)

        guard let decl = sh.range(of: #"(?m)^REQUIRED_LANES=\([^)]*\)"#,
                                  options: .regularExpression) else {
            return XCTFail("""
                `REQUIRED_LANES=(...)` is gone from \(Self.script). If the Fastlane section \
                was removed, delete this claim in the same commit; if it was renamed, \
                re-anchor it. An unanchored scan is worse than no scan (#454).
                """)
        }
        // ⚠️ SPELLED OUT IN TYPED STEPS ON PURPOSE. The one-expression version of this —
        // `String(sh[decl]).split(whereSeparator:).map(String.init).filter { … }` — made the
        // compiler spend 591 ms type-checking a single line (observed as a `limit: 200ms`
        // warning in CI run 34063317322). A guard that slows every build of the bundle is a
        // cost the next reader pays without knowing why; each step now carries its type.
        let declaration: String = String(sh[decl])
        let separators: Set<Character> = ["(", ")", "=", "\"", " ", "\n"]
        let pieces: [Substring] = declaration.split(whereSeparator: { separators.contains($0) })
        var names: [String] = []
        for piece in pieces where piece != "REQUIRED_LANES" {
            names.append(String(piece))
        }

        XCTAssertFalse(names.isEmpty, """
            `REQUIRED_LANES` parsed to an empty list, so this claim would pass without \
            checking anything. Fix the parse, not the expectation.
            """)

        let missing = names.filter { name in
            ff.range(of: #"(?m)^\s*lane :\#(name)\b"#, options: .regularExpression) == nil
        }
        XCTAssertTrue(missing.isEmpty, """
            \(Self.script) demands lane(s) \(missing) that do not exist in \(Self.fastfile). \
            That is a permanent phantom FAIL: the gate reports a broken deploy path for a \
            deploy path that is fine. Either the lane was renamed (update the script) or \
            the name was never real (the #1034 case — four `beta*` lanes that had no \
            counterpart in any revision of the Fastfile).
            """)
    }

    // MARK: - 4: an absent tool is a WARN, never a FAIL

    /// The rest of the file already knew this for XcodeGen and Fastlane. The Swift block
    /// did not, so "no toolchain here" printed as "your package is broken".
    func testTheSwiftCheckIsGuardedByToolchainPresence() throws {
        let sh = try rawFile(Self.script)
        XCTAssertNotNil(sh.range(of: #"(?m)^if ! command -v swift &> /dev/null; then"#,
                                 options: .regularExpression), """
            The `command -v swift` guard is gone from \(Self.script). Without it, every \
            machine without a toolchain — every web session, and the CI container — reads \
            a missing tool as `[FAIL] Swift package has errors`. An absent tool is a WARN. \
            The XcodeGen and Fastlane sections in the same file are the pattern to copy.
            """)
        XCTAssertTrue(sh.contains("package validity UNMEASURED here"), """
            The WARN text for the missing toolchain is gone. The wording matters more than \
            it looks: UNMEASURED is the honest verdict, and it is what stops a reader \
            treating a skipped check as a passed one (#806).
            """)
    }

    // MARK: - 5: the counterweight — this gate has no callers

    /// A lying gate that nothing runs lied to a human, not to the deploy. Keeps the
    /// severity of claims 2–4 honest, and turns red the day someone wires it up.
    func testNothingInTheRepoRunsThisGateAutomatically() throws {
        let root = try repoRoot()
        let fm = FileManager.default
        var callers: [String] = []

        for dir in [".github/workflows", "scripts"] {
            let base = root.appendingPathComponent(dir)
            guard let items = try? fm.contentsOfDirectory(atPath: base.path) else { continue }
            for item in items {
                let path = base.appendingPathComponent(item)
                if path.lastPathComponent == "preflight-check.sh" { continue }
                guard let text = try? String(contentsOf: path, encoding: .utf8) else { continue }
                if text.contains("preflight-check") { callers.append("\(dir)/\(item)") }
            }
        }

        XCTAssertTrue(callers.isEmpty, """
            \(callers) now runs the preflight gate automatically. That is a real \
            improvement AND it changes what claims 2–4 are worth: a defect in this script \
            can now fail a build instead of only misleading a reader. Delete this claim and \
            correct the header block of this file plus the CI notes it points at, in the \
            SAME commit (#456).
            """)
    }

    // MARK: - helpers

    private struct DiagAnchorMissing: Error { let reason: String }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        return root
    }

    private func rawFile(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DiagAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or \
                moved. Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }
}
