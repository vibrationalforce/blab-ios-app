// TheEntryPointTellsTheTruthTests.swift
// Echoel — the first line of the app must not describe a different product. #587.
//
// WHAT THIS GUARDS. The doc comment on the `@main` struct carried the v10 DAW-era tagline
// "Make Beats. Record Video. Stream Live." — three claims, all three struck (beats #166/#167,
// video edit #121 Slice 3, streaming never linked). `decisions.csv` row 29 declared that exact
// sentence superseded on 2026-05-30, and it sat on the entry point for 2.5 months more.
//
// ⭐ WHY AN ENTRY-POINT COMMENT DESERVES A GUARD when ordinary comments do not: it is an IDENTITY
// line. It is the first prose a session or a new contributor reads, and identity lines are what
// plans get derived FROM — this repo's CLAUDE.md carries the same lesson about its own H1 ("the
// headline is part of the claim"), and #184 removed twelve identical over-claims from App Store
// text where each is a 2.3 rejection. The founder's ask that produced this slice was precisely a
// purge of retired DMMW/streaming identity from the repo's context surfaces.
//
// ⚠️ HONEST LIMITS. SOURCE-TEXT SCAN over RAW source — deliberately NOT `SourceText.codeOnly`,
// which blanks comments, and a doc comment is the entire subject here. 4 tests, 5 assertions
// (`grep -c`, measured). This proves the entry point STATES the canonical identity; it cannot
// prove anyone reads it.
//
// ⚠️ THE NEGATIVE NEEDLE IS THE FULL ORIGINAL LINE, prefix included, on purpose: the retraction
// block #587 left at the site QUOTES the tagline (as CLAUDE.md's ⛔ blocks do), which is the
// #491 collision a bare-phrase needle would walk into. Measured on the worktree: the quote wraps
// across a line break, so even the bare phrase happens not to appear contiguously today — the
// full-line needle is chosen anyway, so a future re-wrap of that comment cannot red this guard.
//
// ⭐ GRADING (§3): driven against both trees raw (no stripper — see above). ONE finding: the
// parent carries the retired tagline as the live entry-point doc (1 needle red by presence,
// 2 red by absence of the canonical sentence this commit adds — one absence, reported once,
// #486). 2 needles are COUNTERWEIGHTS, green on both trees: the canonical source document and
// its one-sentence exist, so the entry point quotes a definition that is still canonical rather
// than inventing a third spelling (#416).

import Foundation
import XCTest

final class TheEntryPointTellsTheTruthTests: XCTestCase {

    private static let app = "Sources/Echoelmusic/EchoelmusicApp.swift"
    private static let definition = "docs/dev/PRODUCT_DEFINITION.md"

    /// The entry point states the canonical identity — body plays it, output multidimensional.
    func testTheEntryPointStatesTheCanonicalIdentity() throws {
        let src = try rawSource(Self.app)
        XCTAssertTrue(src.contains("Echoel is a bio-reactive instrument."),
                      "The @main doc must open with the PRODUCT_DEFINITION one-sentence.")
        XCTAssertTrue(src.contains("multidimensional — sound, image, light, space"),
                      "The output half of the sentence is the half DMMW retired INTO — "
                      + "dropping it re-narrows the identity to 'a synth'.")
    }

    /// The retired tagline must not be the LIVE doc line again. Full original line, prefix
    /// included — the retraction block quotes the bare phrase and must stay legal (#491/#364).
    func testTheRetiredTaglineIsNotTheLiveDocLine() throws {
        XCTAssertFalse(try rawSource(Self.app)
            .contains("/// Echoelmusic — Make Beats. Record Video. Stream Live."),
            "The v10 DAW tagline is back on the entry point. All three of its claims are "
            + "struck; decisions.csv row 29 superseded it on 2026-05-30.")
    }

    /// COUNTERWEIGHT. The document the entry point cites must still exist and still be canonical
    /// — otherwise the comment points at nothing and becomes the next stale identity line.
    func testTheCanonicalDefinitionStillExists() throws {
        let def = try rawSource(Self.definition)
        XCTAssertTrue(def.contains("CANONICAL"),
                      "PRODUCT_DEFINITION.md is no longer marked canonical — the entry-point "
                      + "doc quotes it and must move WITH it, not outlive it.")
    }

    /// COUNTERWEIGHT (#416). One spelling of the sentence, owned by the definition file — the
    /// entry point QUOTES it, so the two must agree word for word on the load-bearing clause.
    func testTheSentenceIsTheDefinitionsOwnSpelling() throws {
        let def = try rawSource(Self.definition)
        XCTAssertTrue(def.contains("Echoel is a bio-reactive instrument."),
                      "The definition no longer contains the sentence the entry point quotes — "
                      + "update BOTH in one commit or the app header becomes a second spelling.")
    }

    // MARK: - source access (raw on purpose — the subject IS a comment; §2 skip/fail rules)

    private struct IdentityAnchorMissing: Error { let reason: String }

    private func rawSource(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw IdentityAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }
}
