// StringCatalogIsHonestTests.swift
// Echoel — the String Catalog must actually ship the translations it appears to contain.
//
// FOUNDER, 2026-07-29: *"international für alle Kulturen und Hintergründe accessible."*
// `Sources/Echoelmusic/Resources/Localizable.xcstrings` is the first localisation
// infrastructure this app has ever had. It is hand-authored, because there is no local Xcode
// here to edit it with — which means every invariant Xcode's editor would enforce has to be
// enforced by this file instead.
//
// ⛔ THE ONE THAT MOTIVATED THE WHOLE TEST — `"state": "new"` SILENTLY SHIPS NOTHING.
// `xcstringstool` does not build a string whose unit state is `new`; `new` is the default
// state Xcode assigns to freshly extracted strings, so it is also the state a hand-written
// entry most plausibly gets by copying an example. The result is the worst possible failure
// shape: the catalog looks complete, the build is GREEN, and the device shows English. There
// is no diagnostic anywhere. Every unit we write by hand must say `translated`, and this test
// is the only thing that can say so before a device does.
//
// The other three invariants, each guarding a specific way a hand-written catalog rots:
//   · Every key carries EXACTLY the languages the catalog claims to support. A key that
//     quietly lacks `de` is a sentence that reverts to English for a German user while the
//     screen around it stays German — worse than a screen that is honestly all-English.
//   · The `en` unit's value must EQUAL the key. In this catalog the key IS the English source
//     text (SwiftUI looks literals up by their own content), so a drift between the two means
//     the translator is working from a source string the app never displays.
//   · Every key must still exist as a literal under `Sources/`. Edit a sentence in the view
//     and its catalog entry becomes an orphan: the German is still in the file, still looks
//     translated, and is never found again. For the MANDATED SAFETY WARNINGS this is not
//     cosmetic — it silently reverts a warning to a language the user may not read.
//
// ⚠️ HONEST LIMITS — read before trusting a green result:
//   · This inspects SOURCE TEXT, not a built bundle. If the checkout is not at the path this
//     file was compiled from, it SKIPS. A skip is not a pass — the same rule the sibling
//     `BaseLanguageIsEnglishTests` states, and the reason `doctor` exists.
//   · It cannot verify that `xcstringstool` actually ran, that `de.lproj` landed in the built
//     product, or that a German phone sees German. Only a device can. It verifies that the
//     INPUT is correct, which is the half that is checkable here.
//   · It does not judge translation QUALITY. It cannot. A confidently wrong German safety
//     warning passes every assertion in this file.

import Foundation
import XCTest

final class StringCatalogIsHonestTests: XCTestCase {

    /// The languages this catalog commits to. Adding one here without filling it in fails
    /// `testEveryKeyCarriesEveryLanguage`, which is the intended direction: the list is a
    /// promise, and the test is what makes it one.
    private static let languages: Set<String> = ["en", "de"]

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

    private func catalog() throws -> [String: Any] {
        let root = try repoRoot()
        let url = root.appendingPathComponent(
            "Sources/Echoelmusic/Resources/Localizable.xcstrings")
        guard FileManager.default.fileExists(atPath: url.path) else {
            XCTFail("Localizable.xcstrings is missing at \(url.path). It is the app's only "
                    + "localisation input; deleting it reverts every language to English with "
                    + "no other symptom.")
            return [:]
        }
        let data = try Data(contentsOf: url)
        let parsed = try JSONSerialization.jsonObject(with: data)
        guard let object = parsed as? [String: Any] else {
            XCTFail("Localizable.xcstrings is not a JSON object at its top level.")
            return [:]
        }
        return object
    }

    private func strings() throws -> [String: [String: Any]] {
        let object = try catalog()
        guard let strings = object["strings"] as? [String: [String: Any]] else {
            XCTFail("Localizable.xcstrings has no `strings` object.")
            return [:]
        }
        return strings
    }

    // MARK: - Shape

    func testCatalogDeclaresTheExpectedFormatAndSourceLanguage() throws {
        let object = try catalog()
        XCTAssertEqual(object["version"] as? String, "1.0",
                       "String Catalog format version. Xcode writes \"1.0\"; a different value "
                       + "means this file was hand-edited into a format the tool may not read.")
        XCTAssertEqual(object["sourceLanguage"] as? String, "en",
                       "The source language must be English — it is what CFBundleDevelopmentRegion "
                       + "in Resources/iOS/Info.plist and `defaultLocalization` in Package.swift "
                       + "both say. All three have to agree or translators work from the wrong base.")
    }

    /// Non-vacuity. Every other test in this file iterates the catalog, so an empty or
    /// unparsed catalog would make all of them pass while checking nothing.
    func testCatalogIsNotEmpty() throws {
        let strings = try strings()
        XCTAssertGreaterThan(strings.count, 15,
                             "Only \(strings.count) entries. Either the catalog was gutted or "
                             + "this test is reading the wrong file — and every assertion below "
                             + "iterates this same dictionary, so they would all pass vacuously.")
    }

    // MARK: - The invariants

    /// ⛔ The one that motivated the file. See the header.
    func testEveryTranslationIsMarkedTranslatedAndNotNew() throws {
        let strings = try strings()
        for (key, entry) in strings {
            guard let localizations = entry["localizations"] as? [String: Any] else {
                XCTFail("`\(key)` has no `localizations` — it will display as its own key in "
                        + "every language.")
                continue
            }
            for (language, payload) in localizations {
                guard let unit = (payload as? [String: Any])?["stringUnit"] as? [String: Any]
                else {
                    XCTFail("`\(key)` [\(language)] has no `stringUnit`.")
                    continue
                }
                XCTAssertEqual(unit["state"] as? String, "translated",
                               "`\(key)` [\(language)] is state "
                               + "\(String(describing: unit["state"])). `xcstringstool` builds "
                               + "NOTHING for a unit that is not `translated` — the build stays "
                               + "green and the device shows English. This is the failure this "
                               + "whole test file exists for.")
                let value = unit["value"] as? String ?? ""
                XCTAssertFalse(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                               "`\(key)` [\(language)] has an empty value.")
            }
        }
    }

    func testEveryKeyCarriesEveryLanguage() throws {
        let strings = try strings()
        for (key, entry) in strings {
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            XCTAssertEqual(Set(localizations.keys), Self.languages,
                           "`\(key)` covers \(Set(localizations.keys).sorted()) but the catalog "
                           + "promises \(Self.languages.sorted()). A key missing one language "
                           + "reverts to English mid-screen, which reads as a bug rather than as "
                           + "an untranslated app.")
        }
    }

    /// The key IS the English source text — SwiftUI looks a `Text("…")` literal up by its own
    /// content — so the two drifting apart means the translator's source is not what ships.
    func testTheEnglishUnitEqualsTheKey() throws {
        let strings = try strings()
        for (key, entry) in strings {
            let unit = ((entry["localizations"] as? [String: Any])?["en"]
                        as? [String: Any])?["stringUnit"] as? [String: Any]
            XCTAssertEqual(unit?["value"] as? String, key,
                           "`\(key)` has an English value that differs from its own key. The key "
                           + "is what the app displays; the value is what a translator reads.")
        }
    }

    /// Catches the orphan: a sentence edited in a view whose catalog entry is left behind,
    /// still full of German, never looked up again.
    func testEveryKeyStillExistsAsALiteralInSources() throws {
        let root = try repoRoot()
        let sources = root.appendingPathComponent("Sources")
        let enumerator = FileManager.default.enumerator(at: sources,
                                                        includingPropertiesForKeys: nil)
        var haystack = ""
        var scanned = 0
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            haystack += text
            scanned += 1
        }
        XCTAssertGreaterThan(scanned, 250,
                             "Only \(scanned) Swift files scanned — the search below would pass "
                             + "vacuously on a tree it never read.")
        let keys = try strings().keys
        for key in keys {
            // ⛔ MATCH THE QUOTED LITERAL, NOT THE BARE SUBSTRING. A bare `contains(key)`
            // is shielded by any LONGER sentence elsewhere in `Sources/` that happens to
            // embed the same words — and five of the twenty-one keys are, including two
            // MANDATED SAFETY WARNINGS: `BioSourceView.swift` runs "…coordinate any
            // therapeutic use with your provider. For self-observation, not medical
            // diagnosis…" as one paragraph, and `SessionView.swift` has "Not while driving
            // or operating machinery. Not a medical device." Reword either sentence in the
            // onboarding view and the bare form stays GREEN while the German silently dies
            // — the exact orphan this test is the only guard against. `"Ready"` was the
            // worst: 23 bare hits across the tree, 1 as a literal.
            XCTAssertTrue(haystack.contains("\"\(key)\""),
                          "`\(key)` is in the catalog but appears nowhere in Sources/. Either the "
                          + "sentence was edited in the view and this entry is now an orphan — its "
                          + "translation silently dead — or the entry was added for a string that "
                          + "does not exist yet.")
        }
    }

    /// The five sentences CLAUDE.md mandates. They are the highest-stakes strings in the app:
    /// if one of these silently reverts to English, a user who cannot read English loses a
    /// safety warning, not a label.
    ///
    /// ⚠️ WHAT THIS DOES **NOT** CATCH — the first version of this comment claimed it was
    /// "pinned by content so an edit to the view fails HERE". False, and worth stating
    /// precisely because the wrong reading makes a warning look better guarded than it is:
    /// rewording the sentence in the VIEW leaves the catalog untouched, so THIS test stays
    /// green. The one that goes red is `testEveryKeyStillExistsAsALiteralInSources` above —
    /// the quoted literal no longer appears in `Sources/`. (It only goes red because that
    /// test matches `"key"` WITH the quotes. In its first form it matched the bare
    /// substring, and two of the five sentences below were shielded by longer paragraphs in
    /// `BioSourceView` and `SessionView` that embed them — so for exactly the highest-stakes
    /// strings, NEITHER test would have fired. Both halves of this note were wrong once;
    /// they are two edits apart in the file, which is why the pointer is spelled out.)
    /// What THIS test catches is the other direction: a mandated warning deleted from the
    /// catalog, or never added to it.
    func testEveryMandatedSafetyWarningIsTranslated() throws {
        let mandated = [
            "For self-observation, not medical diagnosis.",
            "Not while driving or operating machinery.",
            "Not under the influence of alcohol or drugs.",
            "Coordinate any therapeutic use with your provider.",
            "Visuals are capped at a safe 3 Hz flash rate."
        ]
        let strings = try strings()
        for sentence in mandated {
            guard let entry = strings[sentence] else {
                XCTFail("MANDATED SAFETY WARNING not in the catalog: \"\(sentence)\". It will "
                        + "display in English to every user in every language.")
                continue
            }
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            XCTAssertEqual(Set(localizations.keys), Self.languages,
                           "MANDATED SAFETY WARNING \"\(sentence)\" is missing a language.")
        }
    }
}
