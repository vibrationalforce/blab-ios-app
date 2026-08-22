// TheBreathPlaySwitchHasNoDoorTests.swift
// Echoel — a knob whose doc comment described a control nobody built. #724, repaired #725.
//
// WHAT WAS WRONG. `BioReactiveSynthVoice.breathPlayEnabled` is `public var … = true` and its
// doc comment ended "Toggle off for pure manual play". Measured across all 369 files under
// `Sources/`: exactly ONE assignment, the declaration itself. Nothing can turn it off, so the
// THREE-condition gate in `consumeBioEventsIfFresh` —
// `guard isArmed, breathPlayEnabled, !heldByController` — is doing two conditions' work, and
// the sentence described a capability with no producer.
//
// ⚠️ THE SIGN IS THE OPPOSITE OF THE USUAL no-producer FINDING, and #724 got this wrong by
// citing `.motion` and `.eegBurst` as "the same shape". Where a SOURCE has no producer the
// capability does not HAPPEN; here the missing writer means it ALWAYS happens. Breath-play is
// fully functional — only the ability to switch it off is absent. The comparison that does
// hold is the tempo modulation route: engine running, destination registered, no route ever
// constructed.
//
// ⭐ THE ENGINE HALF IS REAL, AND THAT IS THE POINT OF CLAIM 3. The consumer reads the flag on
// every bio event, so a door is one control away. This is a knob waiting for a surface, not
// dead code — and the counterweight exists so that "clean up the unused flag" cannot pass
// green. Deleting the read is the one change this guard is designed to make red.
//
// ⛔ #724's NEEDLE SET COULD NOT SEE THE DOOR IT WAS BUILT TO DETECT — the whole promise of
// claim 2, false for the single most likely writer. The class is `@MainActor @Observable`, not
// `ObservableObject`, so `$breathPlayEnabled` (the property-wrapper projection) can never
// appear for it. The realistic door is `@Bindable var voice = bioVoice` +
// `Toggle(…, isOn: $voice.breathPlayEnabled)` — and `.environment(bioVoice)` at
// `EchoelmusicApp.swift` makes exactly that shape the natural one. Four hand-picked needles
// matched none of it. Claim 2 therefore scans for the NAME, anywhere outside the declaring
// file: zero occurrences today, so the scan stays green and becomes total instead of clever.
// A scan that enumerates write shapes is a guess about the future; a scan for the name is not.
//
// ⚠️ IT FORBIDS NOTHING (#364). Giving the flag a door is exactly the work the finding argues
// for; whether it SHOULD have one ("breathe with me" vs "manual only", next to the Body-voice
// arm switch #277) is a founder question, not this file's — and the repo records no decision
// either way. On the day a writer appears, claim 2 goes red BY DESIGN, and the repair is to
// move the ⛔ block in `BioReactiveSynthVoice.swift` in the SAME commit (#456), not to relax
// the assertion.
//
// ⚠️ CLAIM 1 IS SCOPED, NOT A BARE ABSENCE SCAN (#525). The corrected comment QUOTES the
// withdrawn sentence in order to withdraw it, so a plain `contains` would be red on correct
// code, and `codeOnly` cannot rescue it — the text lives in a comment on both trees and the
// stripper blanks it either way. Per line: any line carrying the phrase must also carry
// `SAID`. Claim 1b then asserts the retraction still EXISTS, because otherwise deleting the
// whole block passes every claim here while the record is gone (#343).
//
// ⚠️ A MISSING ANCHOR FAILS, A MISSING TREE SKIPS (#454) — a skip passes CI, so "no checkout"
// may skip and "my anchor was renamed" may not. #724 threw `XCTSkip` for both, which meant
// renaming the file would have left claim 2 reporting green with zero writers for a flag that
// still existed. `BreathAnchorMissing` is the repair, in the shape 98 files in this bundle use.
//
// ⭐ THE SWEEP THAT FOUND THIS FOUND MORE, and #724 claimed "exactly one". Recorded here so
// the next slice does not re-derive it — neither is fixed by this file:
//   · `ResourceGovernor.isAutomatic` + `manualTier` — zero production writers, gate at
//     `guard isAutomatic else`, and a doc that says a performer "can pin a tier (e.g. force
//     High for a show)". A user-facing capability claim in the present tense, in live code.
//     STRONGER than this finding, and nothing anywhere records it.
//   · `ArtNetSender.resolution` / `SACNSender.resolution` — non-Bool, `CaseIterable` (the tell
//     that a Picker was intended), zero writers anywhere, six gating reads, and a doc calling
//     8-bit "the legacy mode for simple fixtures": a selectable mode with no selector.
//
// ⚠️ HONEST GRADING (#433/#464/#486). This file names no symbol the slice adds, so it COMPILES
// against both trees and every assertion has a verdict. Transcribed by hand (a Python rebuild
// of `SourceText.codeOnly`, driven against `git show <tree>:` and the worktree) — a CI round
// trip is a lottery ticket, not a check (#686).
//   · Against the PRE-FINDING tree `fa062a8`: **2 REGRESSIONS** — claim 1 red (the promise
//     "Toggle off for pure manual play" is present, unretracted) and claim 1b red (no
//     retraction on record). Claims 2, 2b, 3, 4 are green there: the flag already had no
//     writer, one assignment, a live consumer and a public declaration. That is the point —
//     they are COUNTERWEIGHTS, and 4 of 6 green on both trees is correct, not padding (#343).
//   · Against the immediate parent `eea4bbe` (#724, which corrected the comment): **0
//     regressions, 6 counterweights.** #725 repairs the GUARD, not the source — so no
//     assertion here can be red on its parent, and saying otherwise would be the flattering
//     direction (#433).
//   · SOURCE-TEXT SCAN throughout (§1). Not one assertion drives behaviour: the members are on
//     a `@MainActor` class the bundle does not instantiate here.
//
// ⚠️ AND THE LIMIT FIRST. Nothing here plays audio or proves anything about breath on a
// device. It proves that no line in `Sources/` can turn this flag off, and that a sentence and
// that measurement agree. `Tests/CISmoke` is the blocking bundle.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheBreathPlaySwitchHasNoDoorTests: XCTestCase {

    private struct BreathAnchorMissing: Error, CustomStringConvertible {
        let reason: String
        var description: String { "breath-play anchor missing: \(reason)" }
    }

    private static let voiceRelative = "Echoelmusic/Tools/BioReactiveSynthVoice.swift"
    private static let voice = "Sources/" + voiceRelative

    // MARK: - 1: the comment no longer promises a control

    func testTheDocNoLongerPromisesAToggle() throws {
        let phrase = "Toggle off for pure manual play"
        let raw: String = try rawText(Self.voice)
        let offenders: [String] = raw.components(separatedBy: "\n")
            .filter({ $0.contains(phrase) && !$0.contains("SAID") })
        XCTAssertTrue(offenders.isEmpty, """
            `BioReactiveSynthVoice` promises again that you can "\(phrase)", outside a \
            retraction:
            \(offenders.joined(separator: "\n"))
            Nothing in `Sources/` writes `breathPlayEnabled`. If a control HAS been built, \
            claim 2 is red in this same run and the ⛔ block above the declaration is the work.
            """)
    }

    /// 1b — without this, deleting the whole ⛔ block passes claims 1-4 while the record is
    /// gone: the "kept the LINE, lost the FACT" shape (#343).
    func testTheRetractionItselfIsStillOnRecord() throws {
        let raw = try rawText(Self.voice)
        // ⛔ The needle must live on ONE line. The first version quoted
        // "THERE IS NOTHING TO TOGGLE IT WITH (#724)", which the comment wraps across two
        // `///` lines — so it matched nothing and claim 1b was red on correct code. Caught by
        // simulating the claim before pushing, which is the only reason it is not a CI red.
        XCTAssertTrue(raw.contains("AND THERE IS NOTHING TO TOGGLE"), """
            The retraction above the declaration is gone from \(Self.voice).

            If a door was built, that block SHOULD change — but then claim 2 is red too and \
            the replacement text is the work. If it was merely deleted, the measurement that \
            justifies keeping this permanently-true flag is no longer written anywhere.
            """)
    }

    // MARK: - 2: THE FINDING — no line in Sources/ can turn it off

    func testNothingOutsideTheDeclaringFileNamesTheFlag() throws {
        let writers = try filesNamingTheFlag()
        XCTAssertTrue(writers.isEmpty, """
            `breathPlayEnabled` is now named outside its own declaration, in: \
            \(writers.joined(separator: ", ")).

            That is GOOD NEWS if it is a real door — this guard forbids building one (#364). \
            It also fires on a mere READ, deliberately: enumerating write shapes is a guess \
            about the future, and #724's four-shape guess missed `$voice.breathPlayEnabled`, \
            the `@Observable` binding that is the likeliest door of all. The repair is not to \
            relax this assertion: move the ⛔ block above the declaration in \
            `BioReactiveSynthVoice.swift` in the SAME commit (#456), because it states in the \
            present tense that the flag is permanently true.
            """)
    }

    /// 2b — the declaring file itself must still hold exactly ONE assignment. Claim 2 skips
    /// that file, so without this a door added INSIDE it (a `setBreathPlay(_:)`, a
    /// `#if canImport(SwiftUI)` extension — this repo does put views beside models) would be
    /// invisible forever.
    /// ⛔ WRITTEN AS A PLAIN LOOP ON PURPOSE. The first version chained
    /// `split().map(String.init).filter { … range(of:) … drop(while:) … }`, and CI reported
    /// "took 550ms to type-check (limit: 200ms)" — the ONLY such warning under `Tests/` in a
    /// log carrying 89 of them. A guard is read far more often than it runs; an expression
    /// that costs the type checker half a second is one a reader also has to unpick (#726).
    func testTheDeclaringFileAssignsItExactlyOnce() throws {
        let code: String = try codeOf(Self.voice)
        var assignments: [String] = []
        for line in code.components(separatedBy: "\n") {
            guard let hit = line.range(of: "breathPlayEnabled") else { continue }
            let tail: String = String(line[hit.upperBound...])
            let trimmed: String = tail.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("="), !trimmed.hasPrefix("==") else { continue }
            assignments.append(line)
        }
        XCTAssertEqual(assignments.count, 1, """
            \(Self.voiceRelative) now assigns `breathPlayEnabled` \(assignments.count) times, \
            not once:
            \(assignments.joined(separator: "\n"))
            One assignment is the declaration. A second is a door built inside the declaring \
            file, which claim 2 cannot see — same repair: move the ⛔ block.
            """)
    }

    // MARK: - 3: COUNTERWEIGHT — the consumer still reads it

    /// Without this, "delete the unused flag" would pass claim 2 trivially. The engine half is
    /// what makes the finding a missing DOOR rather than dead code.
    func testTheConsumerStillReadsTheFlag() throws {
        let code = try codeOf(Self.voice)
        XCTAssertTrue(code.contains("guard isArmed, breathPlayEnabled, !heldByController"), """
            The breath-event gate no longer reads `breathPlayEnabled`.

            If the flag was DELETED, this finding changed shape: it was "a knob with no door", \
            and removing the knob answers a founder question (breathe-with-me vs manual-only) \
            that was never asked. If the gate was merely reformatted, re-anchor this needle on \
            the new spelling — an unanchored scan is the #367 defect this file exists to avoid.
            """)
    }

    // MARK: - 4: ANCHOR — the declaration is present and is a settable, public knob

    /// Two needles rather than the full line: `public var breathPlayEnabled = true` alone goes
    /// red on `: Bool = true`, which is a non-semantic normalisation AND the majority style in
    /// this codebase — that would be a #364 violation on a correct refactor.
    func testTheDeclarationIsPresentAndPublic() throws {
        let code: String = try codeOf(Self.voice)
        let declaration: String? = code.components(separatedBy: "\n")
            .first(where: { $0.contains("var breathPlayEnabled") })
        let line = try XCTUnwrap(declaration, """
            No `var breathPlayEnabled` declaration in \(Self.voice).

            Claims 1-3 all reason about it; without it they would pass by scanning for \
            something that is not there (#367/#408). Re-derive the needle from the real \
            declaration rather than deleting this claim.
            """)
        XCTAssertTrue(line.contains("public"), """
            `breathPlayEnabled` is no longer `public`: \(line)

            The finding is that a PUBLIC knob has no door. If it became private, the knob is \
            gone and so is the finding — move the ⛔ block rather than this assertion.
            """)
    }

    // MARK: - helpers

    /// Files under `Sources/` that name the flag at all, excluding the declaring file by its
    /// exact relative path (a `hasSuffix` match would also excuse a future
    /// `LegacyBioReactiveSynthVoice.swift` anywhere in the tree).
    private func filesNamingTheFlag() throws -> [String] {
        let base = try repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: base.path) else {
            throw BreathAnchorMissing(reason: "cannot walk Sources/")
        }
        var hits: [String] = []
        var seen = 0
        var sawDeclaringFile = false
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            seen += 1
            if rel == Self.voiceRelative {
                sawDeclaringFile = true
                continue
            }
            let text = SourceText.codeOnly(
                try String(contentsOf: base.appendingPathComponent(rel), encoding: .utf8))
            if text.contains("breathPlayEnabled") { hits.append(rel) }
        }
        guard seen > 200 else {
            throw BreathAnchorMissing(reason: """
                only \(seen) Swift files walked under Sources/; the tree holds well over three \
                hundred, so this walk saw a partial checkout and would report a green it did \
                not earn (#454)
                """)
        }
        guard sawDeclaringFile else {
            throw BreathAnchorMissing(reason: """
                \(Self.voiceRelative) was not among the \(seen) files walked — it moved or was \
                renamed. This FAILS rather than skips: a rename would otherwise leave this \
                claim reporting "zero writers" for a flag that still exists (#454)
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
            throw BreathAnchorMissing(reason: """
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
