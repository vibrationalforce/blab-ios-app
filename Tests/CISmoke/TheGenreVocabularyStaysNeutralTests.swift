// TheGenreVocabularyStaysNeutralTests.swift
// Echoel — #570, cycle C5 of the 2026-08-13 handover ("language + scope hygiene, pre-upload").
//
// TWO THINGS, and they pull in opposite directions, which is why they are in one file:
//   1. The genre roster must not carry esoteric / altered-state / therapeutic vocabulary in
//      anything a user reads. That is a brand red line, not a taste ("NEVER use … esoteric
//      terminology (healing frequencies, chakras, Solfeggio)"), and #184 removed twelve false
//      or off-brand claims from the App Store text where such a word is a 2.3 rejection.
//   2. The stored TOKEN must never change, whatever the vocabulary does. `MusicStyle.rawValue`
//      is persisted in three places — `@AppStorage(StudioDefaultKeys.genre.key)`,
//      `Project.styleRaw`, and `TimelineLane.genreOverride` through synthesized `Codable` — and
//      `@AppStorage` answers a failed `init?(rawValue:)` with its DEFAULT, silently. A rename
//      that moves the token resets a user's chosen genre with no error anywhere.
//
// #570 renamed the case `esotericMeditation` → `stillMeditation` and PINNED its raw value to the
// legacy string. Claim 2 is what makes that pin a fact instead of an intention; claim 1 is the
// rule the rename served, asserted for every case so the next genre batch inherits it.
//
// ⚠️ THE LIMIT, PER ASSERTION:
//   · claims 1–3 are END-TO-END BEHAVIOUR over `MusicStyle`, a public Foundation-only enum.
//     They drive every shipped case, not a sample.
//   · claim 4 is a SOURCE SCAN — the only place the retired word may still appear in code is
//     the pinned literal itself.
//   · DEVICE PROBE, open and NOT covered: whether "Deep Ambient" is the right name for this
//     sound is a founder judgement. This file guards vocabulary and storage, never taste.
//
// ⚠️ HONEST GRADING (§3), transcribed in Python against the parent (`720ca37`) and this tree:
//   · claim 2's `.stillMeditation` reference does not COMPILE on the parent (the case is named
//     `esotericMeditation` there), so the file has no verdict on the parent — hand-transcribed,
//     one absence reported once (#486).
//   · claim 1 is a COUNTERWEIGHT whose LOGIC is green on both trees: measured over all shipped
//     cases, no `displayName` and no `lineage` contained a banned word before this commit
//     either. That is the point (#343) — the rename must not be read as having fixed a leak in
//     the copy, because there never was one. What leaked was the identifier.
//   · claim 3 (round-trip of every token) is likewise green on both trees by logic: it protects
//     the whole persisted set, not just the renamed case, so a future rename of ANY case that
//     forgets to pin its token lands here rather than in a user's reset settings.
//   · claim 4 is a REGRESSION on the parent for its named reason: there, `esotericMeditation`
//     occurs 30 times in code across five files, not once.
//   · STRIPPER: TRAGEND, 1 of 1 needle verdict flips — measured. On this tree the retired word
//     occurs FOUR times in `Sources/`: once in code (the pinned literal) and three times in
//     prose (twice in the case's own ⛔ block, once in the `lineage` note that used to cite it
//     as an example). A raw scan therefore counts four and claim 4 demands one — red on a
//     correct tree, the #367 failure exactly.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheGenreVocabularyStaysNeutralTests: XCTestCase {

    private static let styleFile = "Sources/Echoelmusic/Sequencer/MusicStyle.swift"

    /// The repo's own red line, in words. Deliberately NOT a general "spiritual-sounding" filter:
    /// each entry is a term `CLAUDE.md` or the brand section names, so this cannot red on an
    /// ordinary music word. "Drone", "ambient", "meditation" and "calm" are all legitimate and
    /// are all in use — the ban is on claims about states, energies and cures, not on stillness.
    private static let banned = [
        "chakra", "solfeggio", "healing", "heal ", "aura", "esoteric", "third eye",
        "vibrational force", "manifest", "cleanse", "detox", "cure", "therapy", "therapeutic"
    ]

    // MARK: - claim 1 (COUNTERWEIGHT, END-TO-END) — nothing a user reads carries the vocabulary

    /// ⛔ DO NOT ADD `rawValue` (or `id`, which returns it) TO THE SCANNED PROPERTIES. It looks
    /// like the obvious completion and it would be red on correct code: `.stillMeditation`'s
    /// token is pinned to the legacy string "esotericMeditation" on purpose (claim 2), and
    /// "esoteric" is on the list below. The distinction this file rests on is exactly that one —
    /// a STORAGE TOKEN is not copy. `displayName` and `lineage` are what the picker renders.
    func testNoShippedGenreStringUsesEsotericVocabulary() {
        for style in MusicStyle.allCases {
            for (label, text) in [("displayName", style.displayName), ("lineage", style.lineage)] {
                let lowered = text.lowercased()
                for word in Self.banned {
                    XCTAssertFalse(lowered.contains(word), """
                        `MusicStyle.\(style).\(label)` contains "\(word.trimmingCharacters(in: .whitespaces))": \
                        "\(text)"
                        These are the terms the brand section puts on a hard reject list, and the \
                        genre picker is shipped copy — #184 had to strip twelve off-brand or \
                        false claims out of the App Store text, where one of these is a 2.3 \
                        rejection rather than a style note. If a new genre genuinely needs a \
                        word on this list, that is a founder decision and this list moves WITH \
                        it, in the same commit.
                        """)
                }
            }
        }
    }

    // MARK: - claim 2 (END-TO-END) — the rename cost no user their genre

    /// The single most important assertion in this file. `@AppStorage` does not report a failed
    /// `init?(rawValue:)` — it returns the default — so this is the difference between a rename
    /// and a silent reset of every affected user's chosen sound, plus a `.dubTechno` fallback on
    /// every saved project that used it (`Project.swift`).
    func testTheLegacyGenreTokenStillResolves() {
        XCTAssertEqual(MusicStyle(rawValue: "esotericMeditation"), .stillMeditation, """
            The stored token "esotericMeditation" no longer resolves. #570 renamed the CASE and \
            deliberately pinned its raw value, precisely because that token is persisted in \
            `@AppStorage(studio.genre)`, `Project.styleRaw` and `TimelineLane.genreOverride`. \
            Dropping the pin resets the genre of every user who chose it — silently, since \
            `@AppStorage` answers a failed init with its default and nothing logs it.
            """)
        XCTAssertEqual(MusicStyle.stillMeditation.rawValue, "esotericMeditation", """
            `.stillMeditation`'s raw value moved. If the token is being migrated on purpose, the \
            migration has to cover all THREE persistence surfaces in the same commit and this \
            assertion moves with it — carrying the shim, not deleted.
            """)
    }

    // MARK: - claim 3 (COUNTERWEIGHT, END-TO-END) — and no other token drifted either

    /// Generalises claim 2 to the whole roster. A future rename that forgets its pin fails HERE,
    /// on a named case, instead of in a user's reset settings six weeks later.
    func testEveryGenreTokenRoundTrips() {
        for style in MusicStyle.allCases {
            XCTAssertEqual(MusicStyle(rawValue: style.rawValue), style, """
                `\(style)` does not round-trip through its raw value "\(style.rawValue)".
                """)
        }
        XCTAssertEqual(Set(MusicStyle.allCases.map { $0.rawValue }).count,
                       MusicStyle.allCases.count, """
            Two genres now share a raw value. With an explicit raw value in the enum (the #570 \
            pin) that is possible to write and impossible to notice: one of the two becomes \
            unreachable through every persisted path, so a saved project silently opens as the \
            other genre.
            """)
    }

    // MARK: - claim 4 — the retired word survives in code ONLY as the pinned token

    func testTheRetiredIdentifierIsGoneFromCode() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: sources.path),
                          "Sources/ not present in this checkout")
        guard let walker = FileManager.default.enumerator(at: sources,
                                                          includingPropertiesForKeys: nil) else {
            XCTFail("could not walk Sources/ — re-anchor this scan rather than letting it pass")
            return
        }
        var hits: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let code = SourceText.codeOnly(text)
            for (n, line) in code.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where line.contains("esotericMeditation") {
                hits.append("\(url.lastPathComponent):\(n + 1) \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(hits.count, 1, """
            The retired identifier appears \(hits.count) times in CODE, not once:
            \(hits.joined(separator: "\n"))
            After #570 the only legitimate occurrence is the pinned raw value on the case \
            declaration — everything else is either the old identifier coming back or a second \
            copy of the storage token. (Comments are exempt by construction: this scan runs on \
            `SourceText.codeOnly`, and the case's own ⛔ block names the old word repeatedly \
            because that is where the decision is recorded.)
            """)
        XCTAssertTrue(hits.first?.contains("case stillMeditation") ?? false, """
            The one code occurrence of the retired identifier is not the pinned raw value: \
            \(hits.first ?? "none"). If the token moved to a lookup table or a migration map, \
            re-anchor this scan there in the same commit (#454) — the assertion is "one owner", \
            not "this exact line forever".
            """)
    }
}
