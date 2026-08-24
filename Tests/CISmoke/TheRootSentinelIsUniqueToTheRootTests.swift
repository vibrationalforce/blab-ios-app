// TheRootSentinelIsUniqueToTheRootTests.swift
// Echoel — #804. A guard that walks up to find the repo root is only as correct as its
// sentinel, and one of ours was not unique to the root.
//
// WHAT HAPPENED. Two guards in this bundle resolved the repo root by walking up from
// `#filePath` to the first directory containing `CLAUDE.md`. The walk STARTS in
// `Tests/CISmoke/`, and this directory has a `CLAUDE.md` of its own — the directory-scoped
// one that owns how a guard is written. So the very first hop matched and `repoRoot()`
// returned `Tests/CISmoke`. Everything downstream then read a tree that does not hold the
// files it was written for:
//   · `TheLawFileCitesGuardsThatExistTests` found 1 of its 4 always-loaded files (red since #800)
//   · `TheStoreTextClaimsOnlyWhatShipsTests` found no locale directory at all (red since #757)
// Both failed loudly, exactly as #454 intends. Nobody heard: CI/CD reports `failure` on every
// push (#396), so a red guard looks like the host dying, and neither suite was ever in a
// flushed subset (#445). That is the #655/#656 shape — red on a correct tree, invisible.
//
// WHY A GUARD AND NOT JUST A FIX. The repair is one word in each file. What is worth pinning
// is the PROPERTY, because the next root-walking guard will be written by someone who has not
// read this: **a sentinel must not exist anywhere on the walk except at its destination.**
// `Package.swift` satisfies that and is already the house choice (three guards used it while
// two did not); nothing checked that the two families agreed.
//
// WHAT THIS READS. Every `Tests/CISmoke/*.swift` file except this one, for the root-walk
// idiom: the receiver `dir` followed by `appendingPathComponent` and `.path`. That receiver
// name is what makes the needle narrow — it is the walk's loop variable, not a general path
// join, so this cannot fire on the hundreds of ordinary `appendingPathComponent` calls in
// the bundle. For each sentinel found it asserts the sentinel exists at the repo root and
// does NOT exist in either directory the walk passes through on its way there.
//
// ⛔ AND IT DELIBERATELY DOES NOT USE `SourceText.codeOnly`, WHICH #453 OTHERWISE REQUIRES.
// This is the one corpus where that stripper truncates. It carries block-comment state and
// does not know `"""`, so a `docs/**` written inside a failure message reads as `/*`, opens
// a block comment that never closes, and blanks the rest of the file. Measured when written:
// 8 files in this directory lose 943 lines that way — `TheStoreTextClaimsOnlyWhatShips` goes
// dark at its line 350 and its `repoRoot()` becomes invisible — against 0 files under
// `Sources/`, which is why no other guard has ever been bitten (guard files put long prose in
// `"""` messages; shipped code does not). A per-LINE prose filter carries no state and cannot
// be derailed. It is NOT a private stripper: it never rewrites text, it only decides whether
// a line is a `//` comment. Written down here because §6 says an exemption granted by
// accident is not an exemption. The `"""` gap itself is #659's known limitation and its
// repair is a bundle-wide migration, not this slice.
//
// ⚠️ THIS FILE EXCLUDES ITSELF, and that costs nothing: it derives the root by STRUCTURE, so
// it owns no sentinel to check. It has to, because its own failure messages spell the idiom
// out in prose — the #408 anchor-uniqueness trap, caught by driving rather than by review.
//
// ⚠️ IT FORBIDS NOTHING LEGITIMATE (#364). Changing sentinel, adding a root-walking guard,
// even adding a file named `Package.swift` somewhere harmless are all fine — only putting
// one ON THE WALK is not, and that is the defect itself.
//
// HOW THE ROOT IS FOUND HERE, deliberately differently: by STRUCTURE, not by sentinel. This
// file lives in `Tests/CISmoke/`, so the root is two directories up — no search, nothing to
// collide with. Claim 1 then checks that assumption instead of trusting it.
//
// LIMIT (§1): SOURCE-TEXT SCAN over the guard bundle plus filesystem existence checks. It
// proves where the walk can land, never that a guard's assertions are right.
//
// GRADING (§3) against the parent tree `92ddb00`:
//   · Claim 1 — COUNTERWEIGHT, green on both (the layout did not move).
//   · Claim 2 — COUNTERWEIGHT, green on both (`CLAUDE.md` does exist at the root too).
//   · Claim 3 — REGRESSION: on the parent, both files name `CLAUDE.md`, which is present in
//     `Tests/CISmoke/`. Two offenders, ONE root cause — reported as one finding (#486).
//
// ⚠️ THE DEVIATION ABOVE IS LOAD-BEARING, MEASURED, NOT ASSUMED (§2). Driven with
// `SourceText.codeOnly` the parent tree yields ONE offender; driven per line it yields TWO,
// because the store guard's `repoRoot()` sits past the point where the stripper goes dark.
// One of two verdicts flips — so the plain-line read is the reason this guard sees the older
// and more serious of the two defects at all.

import XCTest

final class TheRootSentinelIsUniqueToTheRootTests: XCTestCase {

    /// Fewest root-walk sentinels the bundle must still contain for this scan to mean
    /// anything. An ANCHOR (#454), not a census: deleting a root-walking guard is ordinary
    /// work and must not turn this red (#364).
    private static let sentinelFloor = 3

    /// The directories a walk starting in `Tests/CISmoke/` passes through before the root.
    /// A sentinel present in either one is caught by the first hop and never reaches the root.
    private static let onTheWalk = ["Tests/CISmoke", "Tests"]

    func testNoGuardWalksToARootBySentinelThatSitsOnTheWalk() throws {
        let bundle = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let root = bundle.deletingLastPathComponent().deletingLastPathComponent()
        let fm = FileManager.default

        // Claim 1 — the structural assumption, checked rather than trusted.
        XCTAssertTrue(
            fm.fileExists(atPath: root.appendingPathComponent("Package.swift").path)
                && fm.fileExists(atPath: root.appendingPathComponent("Tests/CISmoke").path), """
            This file derives the repo root as two directories above \(bundle.path), and that \
            no longer lands on a tree holding both `Package.swift` and `Tests/CISmoke`.

            The derivation is structural on purpose — the whole point of this guard is that a \
            sentinel SEARCH can land in the wrong place. If the bundle moved, re-point the \
            derivation in the same commit; do not replace it with a search.
            """)

        var found: [(file: String, sentinel: String)] = []
        let me = URL(fileURLWithPath: #filePath).lastPathComponent
        let names = (try? fm.contentsOfDirectory(atPath: bundle.path)) ?? []
        for name in names.sorted() where name.hasSuffix(".swift") && name != me {
            guard let raw = try? String(contentsOf: bundle.appendingPathComponent(name),
                                        encoding: .utf8) else { continue }
            let head = "dir.appendingPathComponent(\""
            for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
                guard !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                var rest = line
                while let open = rest.range(of: head) {
                    let after = rest[open.upperBound...]
                    if let close = after.range(of: "\")"),
                       after[close.upperBound...].hasPrefix(".path") {
                        found.append((name, String(after[..<close.lowerBound])))
                    }
                    rest = after
                }
            }
        }

        XCTAssertGreaterThanOrEqual(found.count, Self.sentinelFloor, """
            Only \(found.count) root-walk sentinel(s) were found in \(names.count) file(s) — \
            the scan expected at least \(Self.sentinelFloor).

            A collapse means the idiom moved, not that the bundle got tidy (#454). The needle \
            is the walk's loop variable: `dir.appendingPathComponent("X").path`. If root \
            walking is now written another way, re-point this scan in the same commit — \
            otherwise it passes on nothing, which is the shape it exists to prevent.
            """)

        var offenders: [String] = []
        var absent: [String] = []
        for hit in found {
            if !fm.fileExists(atPath: root.appendingPathComponent(hit.sentinel).path) {
                absent.append("\(hit.file) walks to `\(hit.sentinel)`, which is not at the root")
            }
            for dir in Self.onTheWalk
            where fm.fileExists(atPath:
                root.appendingPathComponent("\(dir)/\(hit.sentinel)").path) {
                offenders.append("\(hit.file) walks to `\(hit.sentinel)`, "
                                 + "which also exists in \(dir)/")
            }
        }

        // Claim 2 — a sentinel that is not at the root makes the walk throw, not mis-land.
        XCTAssertTrue(absent.isEmpty, """
            Root-walk sentinel(s) that do not exist at the repo root: \
            \(absent.joined(separator: "; ")).

            Such a walk throws after its hop limit and the guard reads nothing at all. Point \
            it at a file that is actually at the root — `Package.swift` is the house choice.
            """)

        // Claim 3 — the #804 defect itself.
        XCTAssertTrue(offenders.isEmpty, """
            Root-walk sentinel(s) that also sit ON the walk: \
            \(offenders.joined(separator: "; ")).

            A walk up from `Tests/CISmoke/` matches the FIRST directory that holds the \
            sentinel, so a copy in \(Self.onTheWalk.joined(separator: " or ")) is matched \
            before the root is ever reached. The guard then reads a tree that does not hold \
            the files it was written for, and fails for a reason its message cannot explain \
            — which is what #804 found in two guards, one of them red since #757.

            This is not a ban on any sentinel: it is the requirement that the marker be \
            unique to the place it marks. `Package.swift`, `project.yml` and `decisions.csv` \
            all qualify today; `CLAUDE.md` does not, because this directory owns one.
            """)
    }
}
