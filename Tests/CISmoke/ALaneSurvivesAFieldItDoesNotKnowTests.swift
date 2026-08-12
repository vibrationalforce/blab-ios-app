// ALaneSurvivesAFieldItDoesNotKnowTests.swift
// Echoel — #543. A decoder that spent a paragraph explaining why `decodeIfPresent` is not
// enough, and then used it, three lines up.
//
// WHAT THIS GUARDS. `TimelineLane.init(from:)` carries a long comment stating the law
// verbatim: "`decodeIfPresent` absorbs a MISSING key, never an unknown case … the day
// `case drums` is deleted, an old song's drum lane would throw here → `Lossy<Lane>` yields nil
// → `lossyArray` drops the WHOLE LANE → its regions survive as orphans pointing at a laneID
// that no longer exists." Four fields in that same initializer were decoded with the exact form
// the paragraph rules out — `kind` (a String-raw enum), `genreOverride` (ditto), `mood` (a
// synthesized `Codable` over eight NON-optional `Float`s, so `keyNotFound` on a ninth
// dimension) and `patch`. A claim and its own refutation inside one function is the #425
// defect in the literal sense this bundle's rulebook defines.
//
// ⚠️ HONEST SEVERITY, stated before the rule so it cannot be inflated later: NOT ship-blocking
// and not a live defect. No edit in the tree today can trigger the throw. `kind` is the only
// one whose key is on disk at all — `TimelineStore` seeds `kind: .midi` and `kind: .audio` into
// every default document — and nothing constructs a `.video` or `.visual` LANE, so those two
// are precisely the dead cases a future cleanup would delete. `genreOverride` and `mood` cannot
// be on disk today: their setters have zero production callers and the synthesized encoder
// omits a nil Optional. This is a latent hazard plus a self-contradicting comment. Overstating
// it is how the next session mis-ranks the real ones.
//
// ⭐ THE RULE, NOT AN EXEMPTION LIST. The scan below does not enumerate "these four fields must
// be wrapped" — that list would need maintaining and would silently miss field five. It reads
// EVERY `decode…(X.self` in the initializer, and requires `try?` on any `X` that is not a
// Foundation primitive. A new `Int` field stays legal with no edit here; a new enum or struct
// field is red until it is defended. That is the difference between a guard that ages and one
// that teaches.
//
// ⚠️ THE LIMIT. This is a SOURCE-TEXT SCAN. `TimelineLane` is `public` and this bundle could in
// principle decode a hand-built JSON — but the failure being guarded is a FUTURE type change
// (a retired enum case, a ninth mood dimension), which no test can stage without making the
// change. What a green here proves is that the decoder is written defensively; that a real
// legacy document from a user's device survives a real future migration is a DEVICE probe and
// it is OPEN.
//
// ⚠️ HONEST GRADING against the parent — TRANSCRIBED (a Python rebuild of every scan below,
// driven against `git show HEAD:` and the worktree), not assumed. Of the six scans:
//   · ONE REGRESSION, red on the parent for exactly the reason its name gives:
//     `testEveryNonPrimitiveFieldIsDefended` — four fields there use the bare form.
//   · FIVE are COUNTERWEIGHTS, green on both trees, and they are what makes the first one mean
//     something (#343): the lane array must still be decoded LOSSILY (a defended field inside a
//     strictly-decoded array buys nothing), the sibling `Clip.init(from:)` must still use the
//     same form for the same type, `MoodProfile` must still be a struct of non-optional
//     properties (the premise for `mood`), and the two setters must still have no production
//     caller (the premise for the severity claim above — if one gains a caller, the honest
//     severity RISES and this file says so).
//
// ⚠️ `SourceText.codeOnly` is LOAD-BEARING here — MEASURED (#453 asks for the count; three
// slices in a row asserted it without measuring and had to retract, and the first draft of THIS
// line said "4 of 12" before anything was driven). Transcribed run over {6 scans × 2 trees},
// each evaluated raw and stripped: **1 of 12** verdicts flips, and it is the one that matters —
// `testEveryNonPrimitiveFieldIsDefended` on the WORKTREE, PASS stripped and FAIL raw. The ⛔
// blocks this slice writes into `Timeline.swift` quote the removed
// `try c.decodeIfPresent(ClipKind.self` form verbatim to explain why it was wrong, so without
// the stripper the main scan is RED on CORRECT code — the #486/#491 collision again: this repo
// writes down what it removed, so a negative scan necessarily meets its own obituary.
// ⭐ ONE flip is the whole load-bearing case; a bigger number would not have made it stronger.
// The other eleven agreeing is the expected result (#453's own file says all twelve strippers
// agree on every assertion made today) — quoting a larger count reads as more evidence and is
// really just an unmeasured number, which is the flattering-direction defect #433 names.

// `import Foundation` explicitly, not via XCTest's re-export: this file constructs a
// `CharacterSet(charactersIn:)`, and every other file in this bundle that does so imports
// Foundation by name (measured — there is no compiler here to catch the omission, #488).
import Foundation
import XCTest
@testable import Echoelmusic

final class ALaneSurvivesAFieldItDoesNotKnowTests: XCTestCase {

    private static let timeline = "Sources/Echoelmusic/Sequencer/Timeline.swift"
    private static let clip = "Sources/Echoelmusic/Sequencer/Clip.swift"
    private static let composer = "Sources/Echoelmusic/Sequencer/BioComposer.swift"
    private static let store = "Sources/Echoelmusic/Core/TimelineStore.swift"

    /// Types whose decode cannot throw on a value the app does not recognise: there is no
    /// "unknown case" for a number or a string. Everything else — enums, structs, arrays of
    /// them — can, and must be wrapped.
    private static let primitives: Set<String> = [
        "UUID", "String", "Bool", "Float", "Int", "Double", "UInt64", "Int64", "UInt32", "Date",
    ]

    // MARK: - the rule (the one regression)

    func testEveryNonPrimitiveFieldIsDefended() throws {
        let body = try laneInitBody()
        var offenders: [String] = []
        for line in body.split(separator: "\n").map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let type = decodedType(in: trimmed) else { continue }
            guard !Self.primitives.contains(type) else { continue }
            if !trimmed.contains("try?") {
                offenders.append("\(type): \(trimmed.prefix(96))")
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) field(s) in `TimelineLane.init(from:)` decode a NON-primitive \
            type without `try?`: \(offenders.joined(separator: " | ")). A String-raw enum throws \
            `dataCorrupted` on a retired case and a synthesized struct throws `keyNotFound` on a \
            new stored property — `decodeIfPresent` absorbs a missing OUTER key and neither of \
            those. The throw happens INSIDE this decoder, so `Lossy<TimelineLane>` yields nil, \
            `lossyArray` drops the whole lane, and its regions survive as orphans pointing at a \
            laneID that no longer exists. The initializer's own comment says exactly this. Use \
            the form `Clip.init(from:)` uses for the same types: \
            `(try? c.decode(X.self, forKey: .k)) ?? default`.
            """)
    }

    /// The scan has to actually look at something. An extraction that returned nothing would
    /// report a perfect green over an empty string — the silent-pass failure this bundle exists
    /// to prevent.
    func testTheScanReachesTheDecoderItClaimsToCover() throws {
        let body = try laneInitBody()
        let decodes = body.split(separator: "\n").compactMap { decodedType(in: String($0)) }
        XCTAssertGreaterThan(decodes.count, 10, """
            Only \(decodes.count) decode calls were found in `TimelineLane.init(from:)`. It has \
            well over a dozen fields; a short read makes the assertion above vacuous.
            """)
        XCTAssertTrue(decodes.contains("ClipKind"), """
            `ClipKind` is no longer decoded in `TimelineLane.init(from:)`. It is the one field \
            of the four whose key is on disk for every user (`TimelineStore` seeds both a \
            `.midi` and an `.audio` lane); if the field went away, this file's severity note \
            and CLAUDE.md's lane prose both need moving.
            """)
    }

    // MARK: - counterweights (green on both trees — the premises the rule stands on)

    /// A defended field inside a STRICTLY decoded array buys nothing: the array would throw
    /// before any per-field tolerance mattered.
    func testTheLaneArrayIsStillDecodedLossily() throws {
        let src = try source(Self.timeline)
        XCTAssertTrue(src.contains("Self.lossyArray(TimelineLane.self"), """
            `lanes` is no longer decoded through `lossyArray`. Per-field `try?` inside \
            `TimelineLane` only limits the blast radius to ONE lane because the array wraps each \
            element in `Lossy` and drops nil elements. Without that, one bad lane still takes \
            the document.
            """)
    }

    /// The house pattern this fix copied. If the sibling drifts, the fix stops being mechanical
    /// and becomes a lone opinion.
    func testTheSiblingClipDecoderStillUsesTheSameForm() throws {
        let body = try declarationBody(of: "public init(from decoder: Decoder) throws",
                                       in: Self.clip)
        XCTAssertTrue(body.contains("(try? c.decode(ClipKind.self, forKey: .kind)) ?? .midi"), """
            `Clip.init(from:)` no longer decodes `ClipKind` defensively. It is the precedent \
            `TimelineLane` was aligned to for the identical type; if it changed, decide once \
            which form is the house pattern and move both.
            """)
    }

    /// The premise for `mood` being a hazard at all: a synthesized `Codable` over non-optional
    /// stored properties throws the moment a property is added.
    func testMoodProfileIsStillASynthesizedStructOverNonOptionals() throws {
        let src = try source(Self.composer)
        XCTAssertTrue(src.contains("public struct MoodProfile: Sendable, Equatable, Codable"), """
            `MoodProfile` no longer declares synthesized `Codable`. If it gained a hand-written \
            tolerant decoder, `mood` stopped being a hazard and this file's reasoning needs \
            updating — that is good news, not a failure to paper over.
            """)
        XCTAssertFalse(src.contains("public var liveliness: Float?"), """
            `MoodProfile`'s properties became Optional. That also removes the hazard, by a \
            different route. Either way the note in `Timeline.swift` is now wrong.
            """)
    }

    /// THE SEVERITY PREMISE, and it is the counterweight that keeps this file honest rather
    /// than alarmist. `genreOverride` and `mood` cannot be on any user's disk today because
    /// nothing can set them. The day one gains a production caller, the hazard becomes real —
    /// and this assertion goes red to say so.
    func testThePerLaneSettersStillHaveNoProductionCaller() throws {
        let src = try source(Self.store)
        for setter in ["setLaneMood", "setLaneGenreOverride"] {
            XCTAssertTrue(src.contains("func \(setter)"), """
                `\(setter)` is gone from `TimelineStore`. This file's honest-severity note \
                reasons from its existence AND its uselessness; re-check both.
                """)
        }
        let callers = try productionCallers(of: ["setLaneMood(", "setLaneGenreOverride("])
        XCTAssertTrue(callers.isEmpty, """
            \(callers.joined(separator: ", ")) now calls a per-lane mood/genre setter. That is \
            not a failure — it means the feature got a door. But it also means those keys can \
            now reach a user's disk, so the "cannot be on disk today" half of this file's \
            severity note is retired: say so there, and in the commit that adds the caller.
            """)
    }

    // MARK: - source access

    private struct LaneAnchorMissing: Error { let reason: String }

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

    /// Comment-stripped source (#453 — one stripper for the whole bundle); a SKIP without a
    /// checkout, a FAILURE when the file moved (#454: a skip passes CI, so "no tree" may skip
    /// and "my anchor was renamed" may not).
    private func source(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw LaneAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip.
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// `X` from a `decode(X.self` / `decodeIfPresent(X.self` on this line, or nil.
    private func decodedType(in line: String) -> String? {
        for form in ["decodeIfPresent(", "decode("] {
            guard let r = line.range(of: form) else { continue }
            let tail = line[r.upperBound...]
            guard let dot = tail.range(of: ".self") else { continue }
            let name = String(tail[..<dot.lowerBound])
            // `[AutomationLane].self` and friends: take the element name, still non-primitive.
            let cleaned = name.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            return cleaned.isEmpty ? nil : cleaned
        }
        return nil
    }

    private func laneInitBody() throws -> String {
        let text = try source(Self.timeline)
        guard let lane = text.range(of: "public struct TimelineLane") else {
            throw LaneAnchorMissing(reason: "`TimelineLane` is no longer declared in \(Self.timeline)")
        }
        let scoped = String(text[lane.lowerBound...])
        guard scoped.range(of: "public init(from decoder: Decoder) throws") != nil else {
            throw LaneAnchorMissing(reason: """
                `TimelineLane` no longer declares `init(from:)`. If the decoder became \
                synthesized, EVERY field is strict again and this guard's subject is gone — \
                that is the regression, not a re-anchor.
                """)
        }
        return try declarationBody(of: "public init(from decoder: Decoder) throws", in: scoped,
                                   isSource: false)
    }

    /// The brace-matched body following `key`. Brace-matched rather than a line window: this
    /// repo writes 30-line comment blocks between statements, so any fixed window is unsound by
    /// construction (#408/#489).
    private func declarationBody(of key: String, in pathOrText: String,
                                 isSource: Bool = true) throws -> String {
        let text = isSource ? try source(pathOrText) : pathOrText
        guard let start = text.range(of: key) else {
            throw LaneAnchorMissing(reason: "no `\(key)` found. Re-anchor this scan.")
        }
        guard let open = text[start.upperBound...].firstIndex(of: "{") else {
            throw LaneAnchorMissing(reason: "no opening brace after `\(key)`")
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
        throw LaneAnchorMissing(reason: "unbalanced braces after `\(key)`")
    }

    /// Files under `Sources/` that call any of `needles`, excluding the declaration site.
    private func productionCallers(of needles: [String]) throws -> [String] {
        let base = try repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: base.path) else {
            throw LaneAnchorMissing(reason: "cannot walk Sources/")
        }
        var hits: [String] = []
        var seen = 0
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            seen += 1
            if rel.hasSuffix("TimelineStore.swift") { continue }
            let text = SourceText.codeOnly(
                try String(contentsOf: base.appendingPathComponent(rel), encoding: .utf8))
            if needles.contains(where: { text.contains($0) }) { hits.append(rel) }
        }
        guard seen > 200 else {
            throw LaneAnchorMissing(reason: """
                only \(seen) Swift files walked under Sources/; the tree holds well over three \
                hundred, so a "no callers" result here would be vacuous.
                """)
        }
        return hits.sorted()
    }
}
