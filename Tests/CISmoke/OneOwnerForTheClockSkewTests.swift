// OneOwnerForTheClockSkewTests.swift
// Echoel — #545. Six copies of one number, in four files, with nothing that notices a
// partial retune.
//
// WHAT THIS GUARDS. Every freshness check in this repo is two-sided: `age <= window` rejects a
// frozen reading, `age >= -skew` rejects a stamp from ahead of `now`. The window half has an
// owner (`BioSource.freshnessWindow`). The skew half was the literal `-1`, written at
// `EngineBus.freshBio` / `.usableBio` / `.freshMusical`, `AlwaysOnBioChannel.reading(in:now:)`,
// `ColabPayload.live(at:)` and `BioFeedbackManager.isFresh`. One decision, six edit sites — the
// #416 defect at the exact shape `Tests/CISmoke/CLAUDE.md` §2 describes, and the failure it
// names is not disagreement but a retune that converts one site and leaves five behind.
//
// ⛔ AND TWO OF THE SIX CARRIED PROSE CLAIMING THE OPPOSITE. `ColabPayload.live(at:)` said the
// tolerance is "asked the same way rather than minted a second time (#416/#426)" seven lines
// above the line that minted it; `BioFeedbackManager.isFresh` said it "mirrors
// `EngineBus.freshBio`" and then restated its number. That is the #425 defect in its most
// expensive form: the claim a reviewer would have checked FOR was the false one.
//
// ⭐ WHY THE CONSTANT SITS ON `BioSource` even though two of its six callers have no bio source
// (`freshMusical` takes a `MusicalFrame`, `ColabPayload` a peer payload): the quantity is a
// property of the shared WALL clock, not of a source, and `ColabPayload`'s own comment already
// pointed readers at `EngineBus` as the owner. A second constant on the musical or peer side
// would be a tidier spelling of the defect, not its removal.
//
// ⚠️ THE LIMIT, per assertion rather than per file.
//   · Claim 1 is END-TO-END and the strongest thing here: `BioSource.futureSkewTolerance` is
//     `public static`, so this bundle reads the shipped value directly. No source text involved.
//   · Claims 2–4 are SOURCE-TEXT SCANS. The comparison sites are inside `public` functions this
//     bundle could in principle drive, but driving them proves the VALUE, which claim 1 already
//     owns; what these need to see is that the sites ASK rather than restate, and that is a
//     property of the text.
//   · Claim 5 reads `project.yml` — the module graph, which no Swift symbol exposes.
//   · Claim 6 is a source-text scan of a different file's premise.
//
// ⚠️ WHY THE NEGATIVE SCAN IS NARROW, and it is narrow on purpose (#364). It reds a code line
// only when it holds `>= -1` AND names one of `age`/`timestamp`/`arrivedAt` — i.e. a freshness
// comparison. A repo-wide hunt for the bare literal would fire on any legitimate clamp (a DSP
// range check against −1 is ordinary arithmetic), and a guard that reds correct work gets
// deleted with the law inside it. The cost of the narrowing is stated rather than hidden: a
// seventh site that compares a differently-named variable slips through, which is why claim 3
// counts the ASKING sites positively instead of trusting the absence.
//
// ⚠️ ONE PROSE COPY IS DELIBERATELY LEFT STANDING. `Sequencer/BreathHold.swift:344` writes
// "`EngineBus.usableBio()` requires `age >= -1`" inside a ⛔ retraction block that argues a
// reorder is behaviour-preserving. It is a comment, so `SourceText.codeOnly` cannot see it and
// this guard does not red on it; rewriting a carefully-argued retraction to launder a number
// out of it costs more than it buys. It IS the one prose site that goes stale if the tolerance
// is ever retuned — named here and in claim 2's failure message so the next reader finds it
// without grepping.
//
// ⛔ AND IT IS FIVE SITES CONVERTED, NOT SIX — the sixth cannot be, and the COMPILER said so,
// not a rule (#547). `Core/BioFeedbackManager.swift` is compiled STANDALONE into two other
// targets: `project.yml` lists that path under `EchoelmusicWidgets` and under
// `EchoelmusicWatch`, each of which takes this one file and none of `Core/EngineBus.swift`.
// `BioSource` does not exist there, and converting the line produced exactly that —
// `error: cannot find 'BioSource' in scope`, twice, on `Xcode Compile Check` for `9c4f344`.
// ⭐ THE LESSON IS SPECIFIC TO A REPO WITH NO LOCAL TOOLCHAIN: "one owner for one decision"
// (#416) is a rule about the MODULE GRAPH as much as about style, and a file's target
// membership is invisible from the file. `git grep` finds every site; only `project.yml` says
// which of them can see the owner. Read it before a de-duplication that spans `Core/`.
// ⚠️ The exemption is therefore SELF-EXPIRING rather than a list entry: claim 5 asserts the
// premise — the path is still listed standalone AND the literal is still there — so the day
// this file joins the app module, claim 5 reds and names the line to convert. #545's own
// argument against a second copy is what makes this legitimate: it rejected a rationale that
// SOUNDED right and was false ("two phones are not clock-synchronised"). This one is decided
// by a compiler, and it is written down where the next reader will hit it.
//
// ⚠️ HONEST GRADING against the parent `6bab91e` (part 1 of the same slice) — TRANSCRIBED, a
// Python rebuild of every claim driven against `git show 6bab91e:` and this tree:
//   · TWO REGRESSIONS, red there for the reason their names give: claim 2 (one offender,
//     `ColabPayload.swift`, still holding the literal) and claim 3 (2 asking sites of the
//     required 3). They are two halves of the same conversion and are reported as two because
//     they fail on different evidence — one on a literal that is present, one on an ask that
//     is missing. A tree that DELETED the checks rather than converting them passes claim 2
//     and fails claim 3; that asymmetry is the point of carrying both (#343).
//   · FOUR COUNTERWEIGHTS green on both trees: the constant exists and is 1 (claim 1 — part 1
//     declared it), it is declared exactly once (claim 4), the cross-target premise holds
//     (claim 5 — `project.yml` unchanged, the literal still in place), and `MultipeerSession`
//     still stamps `arrivedAt` with the RECEIVER's clock (claim 6 — the premise that makes
//     "both operands are local, so this is skew and not network delay" true, and therefore the
//     premise that forbids re-minting a second literal for `ColabPayload`).
//
// ⚠️ `SourceText.codeOnly` is LOAD-BEARING, MEASURED (#453) over {6 claims × 2 trees}, each
// evaluated raw and stripped against the parent `6bab91e` and this tree: **1 of 12** verdicts
// flips — claim 2 on THIS tree, PASS stripped and FAIL raw, because `BreathHold.swift:344`
// quotes `age >= -1` inside a comment. Without the stripper this guard is red on correct code
// (#486/#491: a repo that writes down what it removed makes every negative scan meet its own
// obituary).
// ⛔ The first draft of this line said "2 of 10, both on claim 2" — and its own next sentence
// refuted it: raw, claim 2 is red on BOTH trees, so the parent produces the same verdict either
// way and cannot flip. One tree, one claim, one flip. Written out rather than silently fixed
// because it is the same slip #543's header made a day earlier: a flip count states a verdict
// DIFFERENCE, and "red for an extra reason" is not a different verdict.

import Foundation
import XCTest
@testable import Echoelmusic

final class OneOwnerForTheClockSkewTests: XCTestCase {

    /// The comparison sites that CAN ask, by file and by how many asks each must carry.
    /// Five of the original six; the sixth is `crossTarget` below, and claim 5 keeps its
    /// exemption honest.
    private static let askingSites: [(path: String, count: Int)] = [
        ("Sources/Echoelmusic/Core/EngineBus.swift", 3),
        ("Sources/Echoelmusic/Studio/AlwaysOnBioChannel.swift", 1),
        ("Sources/Echoelmusic/Sync/ColabPayload.swift", 1),
    ]

    private static let owner = "Sources/Echoelmusic/Core/EngineBus.swift"
    private static let multipeer = "Sources/Echoelmusic/Sync/MultipeerSession.swift"

    /// The ONE site that keeps the literal, and it is not a style exemption — it is a
    /// compile-time fact. `project.yml` lists this path STANDALONE under `EchoelmusicWidgets`
    /// and `EchoelmusicWatch`; both targets take this single file and none of
    /// `Core/EngineBus.swift`, so `BioSource` does not exist in them. Converting the line
    /// produced `error: cannot find 'BioSource' in scope` on the compile gate.
    private static let crossTarget = "Sources/Echoelmusic/Core/BioFeedbackManager.swift"

    // MARK: - claim 1 (END-TO-END — the shipped value, no text involved)

    func testTheToleranceIsOneSecond() {
        XCTAssertEqual(BioSource.futureSkewTolerance, 1, accuracy: 1e-9, """
            `BioSource.futureSkewTolerance` is no longer 1 s. That is a legitimate retune — this \
            assertion exists to make it deliberate, not to forbid it. If you changed it, the \
            prose that spells the old number moves in the SAME commit: this file's header, \
            `Sequencer/BreathHold.swift`'s ⛔ block ("requires `age >= -1`"), and \
            `AHeldReadingSaysSoTests`, which drives a 10 s future stamp against it.
            """)
    }

    // MARK: - claim 2 (the regression — nobody restates it)

    func testNoFreshnessComparisonRestatesTheLiteral() throws {
        var offenders: [String] = []
        for rel in try swiftFiles() {
            let code = try source(rel)
            for (i, line) in code.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() {
                let text = String(line)
                guard text.contains(">= -1") else { continue }
                guard !text.contains("futureSkewTolerance") else { continue }
                let names = ["age", "timestamp", "arrivedAt"]
                guard names.contains(where: { text.contains($0) }) else { continue }
                // The cross-target exemption, and it EXPIRES ON ITS OWN: skipped here only
                // because `testTheExemptionsPremiseStillHolds` proves the file is still
                // compiled standalone into a target that has no `BioSource`. If that stops
                // being true, that assertion reds and this skip has to go with it. An
                // exemption whose premise nothing checks is the exemption list this file's
                // header argues against.
                guard rel != Self.crossTarget else { continue }
                offenders.append("\(rel):\(i + 1): \(text.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) freshness comparison(s) restate the skew tolerance as a literal \
            instead of asking `BioSource.futureSkewTolerance`: \
            \(offenders.joined(separator: " | ")). One decision, N places to edit — the failure \
            is not that they disagree today but that a retune converts one and leaves the rest \
            (#416). The one copy that is allowed to stand is prose, in \
            `Sequencer/BreathHold.swift`'s ⛔ retraction block, and it is invisible to this scan \
            because `SourceText.codeOnly` blanks comments.
            """)
    }

    // MARK: - claim 3 (the #343 counterweight to claim 2 — the checks still EXIST)

    func testEverySiteStillAsksTheOwner() throws {
        for site in Self.askingSites {
            let code = try source(site.path)
            let asks = code.components(separatedBy: "-BioSource.futureSkewTolerance").count - 1
            XCTAssertEqual(asks, site.count, """
                \(site.path) asks `-BioSource.futureSkewTolerance` \(asks)× — expected \
                \(site.count). A tree that DELETED the skew half of these comparisons passes the \
                "nobody restates the literal" scan while quietly accepting a stamp from any \
                distance in the future; that is why this file counts the asks positively as well \
                as scanning for the literal negatively (#343). If a site legitimately went away, \
                move the number here in the same commit.
                """)
        }
    }

    // MARK: - claim 4 (one owner, not two)

    func testTheConstantIsDeclaredExactlyOnce() throws {
        var declarations: [String] = []
        for rel in try swiftFiles() {
            let hits = try source(rel)
                .components(separatedBy: "static let futureSkewTolerance").count - 1
            if hits > 0 { declarations.append("\(rel)×\(hits)") }
        }
        XCTAssertEqual(declarations, ["\(Self.owner)×1"], """
            `futureSkewTolerance` is declared at \(declarations.joined(separator: ", ")) — it \
            must be declared exactly once, on `BioSource` in \(Self.owner), next to \
            `freshnessWindow`. Two declarations of one decision is the defect this slice \
            removed, arriving by a different door.
            """)
    }

    // MARK: - claim 5 (the exemption's premise — it must expire by itself)

    func testTheExemptionsPremiseStillHolds() throws {
        let yml = try text("project.yml")
        XCTAssertTrue(yml.contains("- path: \(Self.crossTarget)"), """
            `project.yml` no longer lists \(Self.crossTarget) as a standalone source. That path \
            was the ONLY reason claim 2 skips that file: the widget and watch targets take this \
            single file WITHOUT `Core/EngineBus.swift`, so `BioSource` does not exist there and \
            `age >= -1` cannot be converted (proved by `error: cannot find 'BioSource' in \
            scope` on the compile gate). If the file joined the app module, the exemption is \
            over — convert the literal and delete the skip in claim 2, in the same commit. \
            `project.yml` is founder-gated: report the change, do not edit it here.
            """)
        let code = try source(Self.crossTarget)
        XCTAssertTrue(code.contains("age >= -1"), """
            \(Self.crossTarget) no longer holds the exempted literal. If it was converted \
            because the target layout changed, remove the skip in claim 2 and this whole \
            assertion; if it was converted anyway, the compile gate will say so. Either way the \
            exemption must not outlive the thing it excuses.
            """)
    }

    // MARK: - claim 6 (the premise that forbids re-minting a peer-side copy)

    func testThePeerStampIsTheReceiversClock() throws {
        let code = try source(Self.multipeer)
        XCTAssertTrue(code.contains("arrivedAt: CFAbsoluteTimeGetCurrent()"), """
            `MultipeerSession` no longer stamps `arrivedAt` with the RECEIVER's clock at \
            delivery. That premise is what makes `ColabPayload.live(at:)` a SKEW check rather \
            than a network-delay check: both operands are local, so it may share the one \
            tolerance. If a sender timestamp ever crosses the wire, `ColabPayload` needs its own \
            reasoning — a second constant with its own name and its own justification, NOT a \
            second copy of this one under a comment saying two phones are not synchronised.
            """)
    }

    // MARK: - source access

    private struct SkewAnchorMissing: Error { let reason: String }

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

    /// Raw file text — `project.yml` is YAML, and `SourceText.codeOnly` would blank the `#`
    /// comments it is full of while leaving `//` alone. Wrong tool; read it as it is.
    private func text(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw SkewAnchorMissing(reason: "\(relativePath) is missing while the tree is present")
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    /// Comment-stripped source (#453 — one stripper for the whole bundle). A SKIP without a
    /// checkout, a FAILURE when a named file moved (#454).
    private func source(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw SkewAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// Every `.swift` path under `Sources/`, relative to the repo root.
    private func swiftFiles() throws -> [String] {
        let base = try repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: base.path) else {
            throw SkewAnchorMissing(reason: "cannot walk Sources/")
        }
        var out: [String] = []
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            out.append("Sources/" + rel)
        }
        guard out.count > 200 else {
            throw SkewAnchorMissing(reason: """
                only \(out.count) Swift files walked under Sources/; the tree holds well over \
                three hundred, so a "nobody restates it" result here would be vacuous.
                """)
        }
        return out.sorted()
    }
}
