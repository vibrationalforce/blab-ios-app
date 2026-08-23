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
// ⛔ #767 ADDED A FIFTH INVARIANT, AND THE FOUR ABOVE ARE THE REASON IT WAS NEEDED: every one
// of them asks whether a sentence EXISTS and is translated. None asks WHERE. The comment on
// `testEveryKeyStillExistsAsALiteralInSources` already named the danger without closing it —
// two of the five mandated warnings are ALSO embedded in `BioSourceView` and `SessionView`, and
// both of those views are DOORLESS. MEASURED rather than reasoned: with the notice moved out of
// the onboarding screen into `BioSourceView`, `testEveryKeyStillExistsAsALiteralInSources`
// stayed **GREEN on all five** while the app showed none of them. For a label that would be a
// stale string; CLAUDE.md lists these five under "SAFETY WARNINGS (must be in app)".
// `testEveryMandatedWarningIsOnAReachableScreen` is the one that goes red on that tree.
//
// ⭐ GRADING FOR #767 (parent `d87d76c`). The new claim is a COUNTERWEIGHT on the parent —
// green there too, because the notice has not moved. Booking it as a caught regression would be
// the flattering direction (#464). What it buys is the FUTURE red, and that red was driven
// deliberately on a mutated tree rather than imagined: all five went red for their named
// reason, and both mutated files were restored byte-identically. The other eight assertions are
// untouched; the mandated list moved to a `static let` so the two claims that read it cannot
// fork a second copy and drift apart while both stay green (#416).
//
// ⭐ #769 ADDED A SIXTH INVARIANT — the app must speak every language the STORE LISTING is
// written in. `fastlane/metadata/<locale>/` and this catalog are maintained by different hands
// at different times and nothing had ever compared them. A French listing over an `en`/`de`
// catalog delivers an English app to a French buyer, five mandated safety warnings included.
// Graded honestly: green on both trees (the two sides agree today), so it is PREVENTIVE, not a
// catch — driven red on a mutated tree with an `fr-FR` listing, which fired for its named
// reason; the directory was removed afterwards.
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

    /// The five sentences CLAUDE.md lists under "SAFETY WARNINGS (must be in app)".
    ///
    /// ⚠️ ONE LIST, TWO CLAIMS (#416). `testEveryMandatedSafetyWarningIsTranslated` asks whether
    /// they are in the catalog; `testEveryMandatedWarningIsOnAReachableScreen` asks whether a
    /// user can ever read them. A second copy of these strings would let the two drift, and the
    /// drift would be invisible — both tests would keep passing about different sentences.
    private static let mandated = [
        "For self-observation, not medical diagnosis.",
        "Not while driving or operating machinery.",
        "Not under the influence of alcohol or drugs.",
        "Coordinate any therapeutic use with your provider.",
        "Visuals are capped at a safe 3 Hz flash rate."
    ]

    /// `struct X: View` declarations in comment-stripped source.
    private static func viewNames(in code: String) -> [String] {
        let pattern = #"\bstruct\s+([A-Za-z_]\w*)\s*:\s*View\b"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = code as NSString
        return re.matches(in: code, range: NSRange(location: 0, length: ns.length))
            .compactMap { $0.numberOfRanges > 1 ? ns.substring(with: $0.range(at: 1)) : nil }
    }

    /// A construction site for `view`, accepting both `Name(` and SwiftUI's trailing-closure
    /// `Name {`, and excluding the declaration and `extension Name {`.
    ///
    /// ⚠️ THE `{` HALF IS NOT OPTIONAL. A scan for `Name(` alone misses `SafeModeView { … }`
    /// and reports live surfaces as dead — measured in this repo, at least three false
    /// positives including the app's own black-screen recovery screen.
    private static func constructs(_ view: String, in code: String) -> Bool {
        let pattern = "(?<!struct )(?<!extension )\\b\(view)\\s*[\\(\\{]"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return false }
        let ns = code as NSString
        return re.firstMatch(in: code, range: NSRange(location: 0, length: ns.length)) != nil
    }

    /// Every tracked Swift file under `Sources/`, comment-stripped once.
    private func swiftSources() throws -> [(path: String, code: String)] {
        let sources = try repoRoot().appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(at: sources,
                                                          includingPropertiesForKeys: nil) else {
            throw NSError(domain: "StringCatalogIsHonest", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "cannot enumerate Sources/ — refusing to report a green it did not earn"
            ])
        }
        var out: [(String, String)] = []
        while let url = walker.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            out.append((url.lastPathComponent, SourceText.codeOnly(text)))
        }
        return out
    }

    /// The app must speak every language the App Store listing is written in.
    ///
    /// ⛔ WHY THIS PAIRING (#769). `fastlane/metadata/<locale>/` and
    /// `Localizable.xcstrings` are maintained by different hands at different times, and
    /// nothing has ever compared them. Ship a French listing while the catalog carries only
    /// `en` and `de` and a French user arrives at an English app — including, per the claim
    /// above, all five MANDATED SAFETY WARNINGS. That is the same failure as an untranslated
    /// key, one level out: not a stale label, a warning in a language the reader may not have.
    ///
    /// ⚠️ IT COMPARES LANGUAGE, NOT REGION. `en-US` and `de-DE` reduce to `en` and `de`; the
    /// catalog is language-keyed. A future `de-AT` listing would therefore be satisfied by the
    /// existing `de`, which is correct — Apple falls back the same way.
    ///
    /// ⚠️ ONE DIRECTION ONLY (#364). A catalog language with no store locale is FINE and stays
    /// unchecked: translating ahead of a listing is ordinary work, and forbidding it would make
    /// this guard the thing that blocks going international.
    func testTheCatalogSpeaksEveryLanguageTheStoreListingUses() throws {
        // ⛔ I FIRST WROTE TWO `deletingLastPathComponent()` CALLS HERE, "climbing out of
        // Sources/". `repoRoot()` in this file already RETURNS the repo root — it only
        // *checks* for `Sources/Echoelmusic` before doing so. Two more climbs land two levels
        // above the checkout, `contentsOfDirectory` returns nothing, and the anchor below
        // would have failed on a correct tree. Read the helper; do not infer it from its name.
        let base = try repoRoot().appendingPathComponent("fastlane/metadata")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        let locales = names.filter { name in
            var isDir: ObjCBool = false
            let path = base.appendingPathComponent(name).path
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                && isDir.boolValue
        }.sorted()
        XCTAssertFalse(locales.isEmpty, """
            `fastlane/metadata/` holds no locale directory, so this claim compared nothing \
            (#454). If the metadata tree moved, point this at its new home in the same commit.
            """)
        for locale in locales {
            let language = String(locale.prefix(while: { $0 != "-" }))
            XCTAssertTrue(Self.languages.contains(language), """
                The App Store listing ships a \(locale) page, but `Localizable.xcstrings` \
                carries no "\(language)" — every string in the app, INCLUDING the five \
                mandated safety warnings, would reach that user in English.

                Add "\(language)" to the catalog and to `Self.languages` in the same commit as \
                the listing. If the listing was added deliberately without a translation, that \
                is a decision to record in `decisions.csv`, not a needle to delete.
                """)
        }
    }

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
    /// A mandated warning must sit on a screen a user can actually reach.
    ///
    /// ⛔ WHY THIS WAS MISSING AND WHY IT MATTERS MOST HERE (#767). The two claims above pin
    /// that each sentence EXISTS as a quoted literal somewhere in `Sources/` and is translated.
    /// Neither asks WHERE. The comment on `testEveryKeyStillExistsAsALiteralInSources` already
    /// names the danger without closing it: two of these five sentences are ALSO embedded in
    /// `BioSourceView` and `SessionView`, and **both of those views are doorless** — nothing in
    /// `Sources/` constructs them. Move the notice from the onboarding screen into either one
    /// and every existing assertion stays GREEN while the app stops showing a safety warning.
    /// For ordinary copy that would be a stale label; CLAUDE.md lists these five under
    /// "SAFETY WARNINGS (must be in app)".
    ///
    /// ⚠️ IT DOES NOT PIN A LOCATION (#364). Moving the notice to a better home is welcome —
    /// what it pins is the PROPERTY: some file carrying the sentence must declare a `View` that
    /// something ELSE in `Sources/` constructs. Measured on this tree, all five have exactly one
    /// carrier, `Views/OnboardingView.swift`, mounted from `EchoelmusicApp.swift`. That single
    /// point of failure is the finding, not a reassurance.
    ///
    /// ⚠️ HONEST LIMIT — this is FIRST-ORDER reachability, the same limit `scripts/doctor.py`
    /// states for its own section C. "Constructed somewhere" is not proof of reachability: the
    /// constructor may itself be dead, which is exactly how the Tools-grid views stayed "wired"
    /// for weeks. What it PROVES is the negative — a sentence whose only carrier is constructed
    /// nowhere cannot be on screen. That negative is the failure mode this repo has actually had.
    ///
    /// ⚠️ COMMENT-STRIPPED ON BOTH SIDES, and it is load-bearing rather than hygiene: the repo
    /// writes `git grep -n 'SomeView(' -- Sources` INSIDE comments to document doorlessness, so
    /// a raw scan reads the note that records a view as unreachable as proof that it is mounted.
    /// That defect was live in `scripts/doctor.py` until #762 and it bit a hand-run `git grep`
    /// again while this file was being written.
    func testEveryMandatedWarningIsOnAReachableScreen() throws {
        let files = try swiftSources()
        XCTAssertGreaterThan(files.count, 250, """
            Only \(files.count) Swift files were read — every check below would pass vacuously \
            on a tree it never walked (#454).
            """)
        for sentence in Self.mandated {
            let literal = "\"\(sentence)\""
            let carriers = files.filter { $0.code.contains(literal) }
            XCTAssertFalse(carriers.isEmpty, """
                MANDATED SAFETY WARNING \"\(sentence)\" appears in no Swift file at all. \
                `testEveryKeyStillExistsAsALiteralInSources` covers the same ground from the \
                catalog side; if both are red, the sentence was deleted rather than moved.
                """)
            var mounted: [String] = []
            for carrier in carriers {
                for view in Self.viewNames(in: carrier.code) {
                    let others = files.filter { $0.path != carrier.path }
                    if others.contains(where: { Self.constructs(view, in: $0.code) }) {
                        mounted.append("\(carrier.path): \(view)")
                    }
                }
            }
            XCTAssertFalse(mounted.isEmpty, """
                MANDATED SAFETY WARNING \"\(sentence)\" is only in \
                \(carriers.map(\.path).joined(separator: ", ")), and no `View` declared there is \
                constructed anywhere else in Sources/ — so no user can read it.

                This is NOT a ban on moving the notice. Put it wherever it belongs and make sure \
                that screen is mounted; the check follows it. Two of these five sentences also \
                sit in `BioSourceView` and `SessionView`, both doorless, so "the string still \
                exists" is exactly the reassurance that must not be trusted here. CLAUDE.md lists \
                these five under "SAFETY WARNINGS (must be in app)".
                """)
        }
    }

    func testEveryMandatedSafetyWarningIsTranslated() throws {
        let strings = try strings()
        for sentence in Self.mandated {
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
