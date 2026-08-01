// NoDoorlessStudioViewsTests.swift
// Echoel — #322. `EchoelStudioView.swift` held FOUR `some View` properties that nothing
// mounted. Three were leftovers. One was not.
//
// ⭐ WHY THE CLASS AND NOT THE FOUR NAMES. From a grep the four were indistinguishable:
// a `private var X: some View` whose only occurrence in the whole repo was its own
// declaration line. What they actually were:
//
//   · `soundControls`   — the pre-chip page layout, replaced by `dropdownContent`. Leftover.
//   · `learnRow`        — a door card; its door moved to the `.echoelChromeDoor` receiver. Leftover.
//   · `liveColaboRow`   — same. Leftover.
//   · `moodPadsSection` — the two XY atmosphere pads AND the sound↔visual link the founder
//                         asked for on 2026-07-07. NOT a leftover: an unreachable feature.
//
// Nothing in the source said which was which. And the last one was the hardest kind to
// notice, because every parameter it moves (darkness, liveliness, hue, motion, intensity)
// is reachable as a number somewhere else — so no control was missing, only the gesture.
// That is why this guard fires on the CLASS: the next unmounted view has to be LOOKED AT,
// and whoever looks decides "delete" or "re-door" with the evidence in front of them.
//
// ⛔ HONEST LIMITS — three, and the third is the one that matters.
//
//  1. This is a SOURCE SCAN. It proves a property is referenced somewhere in its own file,
//     not that a user can reach it. There is no simulator here (house pattern —
//     `SoundPanelPresetBarTests`, `SoundPromptHasADoorTests`).
//  2. It scans ONE file. `EchoelStudioView.swift` is where the defect keeps happening
//     (it is the only view file large enough to lose a property in), not a claim about
//     the rest of `Studio/`.
//  3. **It cannot catch a view referenced from a DEAD caller.** `visualVJOverlay` is the
//     live proof: it has two occurrences — its declaration and one use inside
//     `.fullScreenCover(isPresented: $showVisual)`, whose flag has no setter anywhere in
//     `Sources/`. So the whole VJ control panel is unreachable and this file says nothing
//     about it (that is #270). Catching THAT needs reachability, not reference-counting,
//     and reference-counting is what can be done exactly and without a compiler. A guard
//     that overstates its reach is the failure mode this repo keeps paying for, so the
//     reach is stated instead of implied.

import Foundation
import XCTest

final class NoDoorlessStudioViewsTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// `body` is a `View` protocol requirement: SwiftUI calls it, no source line names it.
    /// Every other `some View` property in this file is a private building block that
    /// something must mount by name.
    private static let protocolRequirements: Set<String> = ["body"]

    /// ⚠️ PRE-EXISTING ORPHANS (2026-08-01), each with its own decision to make. This list is
    /// declared, not silent, because a guard that quietly excuses what it finds is the same
    /// defect as a workflow step that swallows its exit status.
    ///
    /// Three of the four were ALREADY documented as unmounted inside `EchoelStudioView.swift`
    /// itself — which is the point: the file knew, and nothing enforced it, so they sat there.
    ///
    ///   · `beatModeRow`             — the beat surface went 2026-07-07 ("Schmeiß den Beat weg")
    ///                                 and the drums themselves with #166/#167. Nothing left to
    ///                                 control; a deletion, not a decision. → #323
    ///   · `visualBlendControls`     — the file says it plainly: "That view has ZERO mount sites",
    ///                                 and that a wrong note once protected it "blocking a
    ///                                 legitimate deletion". → #324
    ///   · `nonStandardTuningBanner` — the file says "keeps the full explainer, unpresented". A
    ///                                 judgement call about a tuning warning, not cleanup. → #325
    ///   · `liveNarrationBanner`     — the EchoelAI live caption. ZERO occurrences anywhere, not
    ///                                 even in prose, so nothing recorded why. → #326
    ///
    /// They are excused from the headline and pinned by `testTheKnownOrphanListDoesNotRot`, which
    /// fails if one is deleted, renamed, OR quietly mounted — so the list cannot outlive its
    /// entries in either direction.
    private static let knownOrphans: Set<String> = [
        "beatModeRow", "visualBlendControls", "nonStandardTuningBanner", "liveNarrationBanner"
    ]

    // MARK: - The headline

    func testEveryStudioSomeViewPropertyIsMountedSomewhere() throws {
        let code = try codeLines(Self.studio)
        let declared = Self.someViewNames(in: code)

        XCTAssertGreaterThan(declared.count, 20, """
        found only \(declared.count) `some View` properties in \(Self.studio) — this file has \
        dozens. A near-empty result means the declaration pattern stopped matching (a rename, a \
        formatting change), not that the file got smaller. A guard that silently scans nothing \
        is worse than no guard: fix the pattern rather than trusting this green.
        """)

        let orphans = declared.filter { name in
            !Self.knownOrphans.contains(name) && Self.occurrences(of: name, in: code) <= 1
        }.sorted()

        XCTAssertTrue(orphans.isEmpty, """
        these `some View` properties in \(Self.studio) are declared and never mounted: \
        \(orphans.joined(separator: ", ")).

        DO NOT reach for the delete key first. #322 found four of these at once and ONE of them \
        (`moodPadsSection`) was an unreachable founder feature, not dead code — the other three \
        were genuine leftovers, and the source did not distinguish them. Read what the block \
        does, then either mount it or delete it WITH a tombstone saying which it was and why.

        Two things to check before deleting: does this block write any persisted state \
        (`@AppStorage`, a store) that nothing else writes — deleting it then freezes that value \
        rather than leaving a gap; and does anything it constructs become unreachable with it \
        (`moodPadsSection` was the only mount point of BOTH `MoodXYPad` leaves).
        """)
    }

    /// The excuse list must describe reality, or it becomes the thing it excuses. An entry that
    /// got deleted, renamed, or (best case) MOUNTED has to leave the list in the same commit.
    func testTheKnownOrphanListDoesNotRot() throws {
        let code = try codeLines(Self.studio)
        let declared = Self.someViewNames(in: code)

        let vanished = Self.knownOrphans.subtracting(declared).sorted()
        XCTAssertTrue(vanished.isEmpty, """
        excused as known orphans but no longer declared in \(Self.studio): \
        \(vanished.joined(separator: ", ")). Deleted or renamed — either way remove the entry \
        (and its task) from `knownOrphans`, so the list keeps meaning something.
        """)

        let nowMounted = Self.knownOrphans
            .filter { declared.contains($0) && Self.occurrences(of: $0, in: code) > 1 }
            .sorted()
        XCTAssertTrue(nowMounted.isEmpty, """
        excused as known orphans but now referenced: \(nowMounted.joined(separator: ", ")). \
        Good news — take them off `knownOrphans` so the headline test starts protecting them.
        """)
    }

    // MARK: - The scanner's own honesty

    /// The comment stripper is load-bearing here: this file is unusually comment-dense, and
    /// several tombstones name properties that no longer exist. If prose counted as a
    /// reference, a genuinely orphaned view could be kept green by a sentence about it —
    /// the exact substitution #320 was built on.
    func testProseAboutAViewDoesNotCountAsMountingIt() throws {
        let invented = "aViewNameThatAppearsOnlyInThisTest"
        let line = "    // \(invented) is mentioned here and nowhere else"
        XCTAssertEqual(Self.occurrences(of: invented, in: [Self.stripComment(line)]), 0, """
        a name that appears only inside a `//` comment was counted as a reference — the \
        stripper is not doing its job, and every result of this file becomes untrustworthy.
        """)

        // And the inverse: a real code line must still count.
        XCTAssertEqual(Self.occurrences(of: invented, in: [Self.stripComment("        \(invented)")]), 1)
    }

    /// The word-boundary match must not let a LONGER name stand in for a shorter one —
    /// otherwise `moodPanel` would be "mounted" by any mention of `moodPanelHost`.
    func testASubstringOfALongerNameIsNotAReference() {
        XCTAssertEqual(Self.occurrences(of: "moodPanel", in: ["            moodPanelHost"]), 0)
        XCTAssertEqual(Self.occurrences(of: "moodPanel", in: ["            moodPanel"]), 1)
    }

    // MARK: - Scanning

    /// Names of `some View` properties declared in `code`, minus protocol requirements.
    /// The declaration itself is one occurrence, which is why the headline compares to 1.
    private static func someViewNames(in code: [String]) -> Set<String> {
        var found = Set<String>()
        for line in code {
            guard let range = line.range(of: "var "),
                  let colon = line.range(of: ": some View", range: range.upperBound..<line.endIndex)
            else { continue }
            let name = String(line[range.upperBound..<colon.lowerBound])
                .trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty,
                  name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
                  !protocolRequirements.contains(name)
            else { continue }
            found.insert(name)
        }
        return found
    }

    /// Whole-word occurrences of `name` across `code`. Swift identifiers are
    /// letters/digits/underscore, so a neighbouring one of those means a different symbol.
    private static func occurrences(of name: String, in code: [String]) -> Int {
        var total = 0
        for line in code {
            var search = line.startIndex
            while let hit = line.range(of: name, range: search..<line.endIndex) {
                let beforeOK = hit.lowerBound == line.startIndex
                    || !isIdentifierCharacter(line[line.index(before: hit.lowerBound)])
                let afterOK = hit.upperBound == line.endIndex
                    || !isIdentifierCharacter(line[hit.upperBound])
                if beforeOK && afterOK { total += 1 }
                search = hit.upperBound
            }
        }
        return total
    }

    private static func isIdentifierCharacter(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber || ch == "_"
    }

    // MARK: - Files

    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { Self.stripComment(String($0)) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Whole-line and trailing `//` comments removed. Quote parity approximates "is this
    /// `//` inside a string literal"; it is imperfect in both directions (an escaped quote
    /// or a `"""` delimiter leaves odd parity and the comment survives), which for THIS
    /// file can only ever keep an extra prose line in — i.e. it can hide an orphan, never
    /// invent one. Stated because the same helper's doc in `SoundPromptHasADoorTests` had
    /// to be corrected for claiming one-directional failure without measuring it.
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

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
            source tree not present at \(sources.path) — this file reads source text, so it \
            SKIPS rather than reporting a green it did not earn
            """)
        }
        return root
    }
}
