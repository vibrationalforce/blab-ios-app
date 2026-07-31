// BaseLanguageIsEnglishTests.swift
// Echoel — the app's BASE language must actually be the one the bundle claims.
//
// FOUNDER, 2026-07-29: *"international für alle Kulturen und Hintergründe accessible."*
// The first thing an inventory turned up was not a missing translation — it was that the app
// was ALREADY bilingual by accident. Eight user-facing German strings shipped inside a bundle
// whose `CFBundleDevelopmentRegion` is `en`, including the four top-level genre-category
// headers and both onboarding hints on the immersive visual — the most-seen surface in the
// app and the first thing a new user reads.
//
// ⚠️ WHY THIS IS A GUARD AND NOT A TIDY-UP, and why it had to land BEFORE any String Catalog:
// a catalog extracts the BASE language as the source text — the key every other language is
// translated FROM. A German literal left in place would have been frozen as the English
// source string, so the French build would ship German, the Japanese build would ship German,
// and a translator would be asked to render "Berühre das Bild zum Spielen" into Japanese from
// a file labelled English. Order matters here in a way it usually does not: this is cheap now
// and expensive-and-embarrassing after the catalog exists.
//
// ⚠️ HONEST LIMITS — read before trusting a green result:
//   · It scans SOURCE TEXT, not the built binary. If the checkout is not at the path this file
//     was compiled from, the test SKIPS rather than passing — a skip is not a pass, and a
//     silent pass on an unscanned tree is exactly the `continue-on-error` lie the `doctor`
//     skill exists to catch.
//   · It ignores whole-line comments, because the fix commit deliberately QUOTES the removed
//     German strings in its own comments so the history stays legible. A German literal parked
//     on the same line as trailing code would slip through. Accepted: the realistic mistake is
//     someone typing a German label, not smuggling one past a scanner.
//   · The marker list is small and word-bounded on purpose. "Ort" is a substring of Sort,
//     Import, Export and Short; matching it loosely would produce noise until someone disables
//     the test, which is worse than not having it.
//   · It cannot tell German from any OTHER wrong base language. It catches the mistake this
//     repo actually made, by the founder's own hand, in his own language — which is the only
//     kind of check worth adding.

import Foundation
import XCTest

final class BaseLanguageIsEnglishTests: XCTestCase {

    /// Words that are unambiguously German and would never appear in English UI copy.
    /// Matched case-insensitively with word boundaries.
    private static let germanWords = [
        "Datei", "Ort", "Berühre", "Berühren", "bringt", "Meditativ", "Elektronisch",
        "Energie", "Akustisch", "Klang", "Stimme", "Taste", "Atem", "Sprache",
        "nicht", "kein", "keine", "zum", "zur", "und", "oder", "auf die", "mit dem"
    ]

    /// Characters that only occur in German (and a few other non-English) orthography.
    private static let germanCharacters = CharacterSet(charactersIn: "äöüÄÖÜß")

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…` → up two).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()   // CISmoke
            .deletingLastPathComponent()              // Tests
            .deletingLastPathComponent()              // repo
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("source tree not present at \(sources.path) — this test inspects "
                          + "source text, so it SKIPS rather than reporting a green it did "
                          + "not earn")
        }
        return root
    }

    /// Non-user-facing literals that are German ON PURPOSE. An explicit list with a reason
    /// each, rather than a clever heuristic: a heuristic that happens to exclude these would
    /// silently widen later and start excluding a real label too.
    private static let allowed: Set<String> = [
        // The German vowel set in the singing syllabifier (`Sequencer/LyricsModel.swift`).
        // It is German because German lyrics are a supported input — the opposite of the
        // defect this file guards, and never rendered anywhere.
        "aeiouyäöü"
    ]

    /// Every `"…"` literal on a line, ignoring comments.
    ///
    /// Comment handling is the part worth reading. A first version skipped only WHOLE-line
    /// comments and documented trailing comments as a known gap — then the very first dry run
    /// against the tree hit that gap: `WeatherMood.swift`'s `case sound   // "Klang"` is a
    /// German word in a trailing comment on a line of code, and the scanner flagged it. A
    /// guard whose first real encounter is with its own documented limitation is a guard people
    /// switch off. So the walk now also stops at a `//` that is OUTSIDE a string literal —
    /// which closes the gap exactly, because `"https://…"` keeps its slashes inside the string
    /// and is unaffected.
    private func literals(in line: String) -> [String] {
        var out: [String] = []
        var current: String?
        var escaped = false
        var previousWasSlash = false
        for ch in line {
            if escaped { current?.append(ch); escaped = false; previousWasSlash = false; continue }
            if ch == "\\" { escaped = true; previousWasSlash = false; continue }
            if ch == "\"" {
                if let done = current { out.append(done); current = nil } else { current = "" }
                previousWasSlash = false
                continue
            }
            if current == nil {
                if ch == "/" {
                    if previousWasSlash { return out }   // `//` outside a string → comment
                    previousWasSlash = true
                    continue
                }
                previousWasSlash = false
                continue
            }
            current?.append(ch)
        }
        return out
    }

    private func looksGerman(_ s: String) -> Bool {
        if s.rangeOfCharacter(from: Self.germanCharacters) != nil { return true }
        let lower = " " + s.lowercased() + " "
        for w in Self.germanWords {
            // Word-bounded: surround by non-letters. Cheap and enough — see the limits note.
            let needle = w.lowercased()
            var searchStart = lower.startIndex
            while let r = lower.range(of: needle, range: searchStart..<lower.endIndex) {
                let before = r.lowerBound == lower.startIndex ? " "
                    : String(lower[lower.index(before: r.lowerBound)])
                let after = r.upperBound == lower.endIndex ? " " : String(lower[r.upperBound])
                let isLetter: (String) -> Bool = { $0.rangeOfCharacter(from: .letters) != nil }
                if !isLetter(before) && !isLetter(after) { return true }
                searchStart = r.upperBound
            }
        }
        return false
    }

    /// THE ONE THAT MATTERS. No German in any user-facing string literal under `Sources/`.
    func testNoGermanStringShipsInTheEnglishBaseBundle() throws {
        let root = try repoRoot()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard let walker = FileManager.default.enumerator(at: sources,
                                                          includingPropertiesForKeys: nil) else {
            return XCTFail("could not walk \(sources.path)")
        }
        var offenders: [String] = []
        var scannedFiles = 0

        for case let url as URL in walker where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            scannedFiles += 1
            for (i, line) in text.components(separatedBy: .newlines).enumerated() {
                for lit in literals(in: line)
                where lit.count >= 3 && !Self.allowed.contains(lit) {
                    if looksGerman(lit) {
                        let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
                        offenders.append("\(rel):\(i + 1)  \"\(lit)\"")
                    }
                }
            }
        }

        // Non-vacuity: if the walk found nothing, the empty `offenders` proves nothing. This
        // repo has written that failure mode into three other test files after hitting it.
        XCTAssertGreaterThan(scannedFiles, 250, """
        only \(scannedFiles) Swift files scanned — the walk failed, so a green result here \
        would be meaningless
        """)

        // ⛔ WHY THESE ARE `"""` LITERALS AND NOT `+`-CHAINS. Both messages here were exactly
        // that, and the four-part one below mixed an interpolation, a `joined(separator:)` and
        // three literals in ONE expression. That construct is what took the blocking bundle
        // red on `f8f1fef`: the Swift type-checker hard-errored with "unable to type-check
        // this expression in reasonable time" on a sibling file (#287, repaired in `3379bb3`,
        // logged in HARNESS_LEDGER). It compiled HERE — but the difference between the two
        // sites was chain length, not kind, and the warning form ("expression took NNNNms")
        // is silent in this bundle. Converted before it costs a second cycle. The `joined`
        // is hoisted to a local for the same reason.
        let listing = offenders.joined(separator: "\n")
        XCTAssertTrue(offenders.isEmpty, """
        German text in the English base bundle (\(offenders.count)):
        \(listing)

        Write the base string in English. German belongs in a String Catalog translation, \
        where a translator and a reviewer can see it.
        """)
    }

    /// The scanner must be able to FAIL — a guard that cannot fire is decoration. Proves the
    /// two detection paths (umlaut, word-bounded keyword) and the two exclusions (whole-line
    /// comment, English word that merely contains a marker as a substring).
    func testTheScannerActuallyDetectsGerman() {
        XCTAssertTrue(looksGerman("Berühre das Bild"), "umlaut path")
        XCTAssertTrue(looksGerman("Datei: take.mid"), "keyword path")
        XCTAssertTrue(looksGerman("Ort manuell"), "word-bounded keyword")
        XCTAssertFalse(looksGerman("Sort presets"), "\"Sort\" contains \"ort\" — must not fire")
        XCTAssertFalse(looksGerman("Import a loop"), "\"Import\" contains \"ort\"")
        XCTAssertFalse(looksGerman("Export MIDI"), "\"Export\" contains \"ort\"")
        XCTAssertFalse(looksGerman("Sound"), "\"Sound\" contains \"und\"")
        XCTAssertFalse(looksGerman("A finger on the camera brings it to life"),
                       "the replacement copy must itself pass")
        XCTAssertTrue(literals(in: "        // case .rock: return \"Rock & Energie\"").isEmpty,
                      "a whole-line comment must be ignored, or the fix commit's own "
                      + "historical quotes would fail this test")
        XCTAssertEqual(literals(in: "case sound   // \"Klang\""), [],
                       "a TRAILING comment must be ignored too — this exact line exists in "
                       + "WeatherMood.swift and was the scanner's first false positive")
        XCTAssertEqual(literals(in: "Text(\"Sound\") // and \"Klang\""), ["Sound"],
                       "code before a trailing comment is still scanned; the comment is not")
        XCTAssertEqual(literals(in: "let u = \"https://echoelmusic.com\""),
                       ["https://echoelmusic.com"],
                       "a // INSIDE a string is not a comment — the case that makes the "
                       + "comment-stripping rule non-trivial")
        XCTAssertTrue(Self.allowed.contains("aeiouyäöü"),
                      "the singing syllabifier's German vowel set is German on purpose")
    }

    /// The allowlist must stay honest: every entry has to be a string that WOULD otherwise be
    /// flagged. A stale entry that no longer matches anything is a quiet licence for the next
    /// one to be added without justification.
    func testEveryAllowlistEntryIsActuallyNeeded() {
        for entry in Self.allowed {
            XCTAssertTrue(looksGerman(entry),
                          "\"\(entry)\" is on the allowlist but would not be flagged anyway — "
                          + "remove it rather than leaving an unexplained exemption")
        }
    }
}
