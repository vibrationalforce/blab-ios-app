// WebsitePagesAreFindableAndHonestTests.swift
// Echoel — the published site, in the BLOCKING bundle.
//
// WHY A WEBSITE GUARD LIVES WITH THE APP TESTS (#371). `docs/` is not documentation, it is
// the GitHub-Pages site the world reads. Getting one claim wrong there has cost this repo
// two whole cycles (#158/#192 removed a single false AUv3 claim from eight files and ~25
// places) and, in the App Store metadata that mirrors it, twelve more (#184) — where a false
// claim is a 2.3 rejection, not a typo. `ContentPipelineClaimsTests` already sets the
// precedent that a marketing-truth fact belongs in the blocking bundle.
//
// ⛔ WHAT THIS FILE DELIBERATELY IS NOT, AND THE MEASUREMENT THAT DECIDED IT. The obvious
// guard is a keyword scan for struck terms — "AUv3", "wellness", "healing frequencies",
// "meditation", "cure". I ran exactly that over `docs/` before writing a line of Swift:
// 27 hits, and EVERY ONE of them was a NEGATION. The site says "it is not an Audio Unit
// (AUv3) plugin", "no esoteric claims, no 'healing frequencies'", "please don't describe
// Echoelmusic as a wellness, therapy or meditation product", "not intended to diagnose,
// treat, cure". Those sentences are the site being CORRECT — several of them are the fix
// #158/#192 shipped. A keyword guard would have gone red on the repair and pushed the next
// reader to delete it.
//
// That is the #364 mistake in a new costume: grepping a token instead of reading what it
// means. So this file guards what is actually DECIDABLE from text — findability and the
// per-page metadata contract — plus ONE narrow claim check whose limits are stated below.
//
// ⚠️ Source-text scan, no browser, no crawler. A green means the pages are reachable and
// carry their metadata; it can say nothing about whether they read well or rank.

import Foundation
import XCTest
// #428: the counted-claims test reads `MusicStyle.offered` and `Scale.Family` so the published
// numbers are chained to the app instead of copied from it. Every other test here is pure text.
@testable import Echoelmusic

final class WebsitePagesAreFindableAndHonestTests: XCTestCase {

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("docs/sitemap.xml").path) else {
            throw XCTSkip("""
                site tree not present under \(root.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }

    /// `404.html` is served on error and must not be indexed; `og-image.html` is a template
    /// used to render the social preview, not a page anyone visits. Both are excluded from
    /// every assertion below, and this is the ONE place that decision is written down.
    private static let notPages: Set<String> = ["404.html", "og-image.html"]

    private func pages() throws -> [(name: String, html: String)] {
        let docs = try repoRoot().appendingPathComponent("docs")
        let names = try FileManager.default.contentsOfDirectory(atPath: docs.path)
            .filter { $0.hasSuffix(".html") && !Self.notPages.contains($0) }
            .sorted()
        return try names.map { ($0, try String(contentsOf: docs.appendingPathComponent($0), encoding: .utf8)) }
    }

    // MARK: - Findability

    /// A page that exists but is in no sitemap is a page nobody finds. This is mechanical,
    /// which is exactly why it is worth a test: it is the check a human skips when adding
    /// the sixteenth page in a hurry.
    func testEveryPageIsInTheSitemap() throws {
        let sitemap = try String(
            contentsOf: try repoRoot().appendingPathComponent("docs/sitemap.xml"), encoding: .utf8)
        var missing: [String] = []
        for page in try pages() {
            // The home page is listed as the bare domain, not as `index.html` — a real
            // convention, and the reason this test resolves it rather than string-matching
            // the filename. My own first pass at this check reported `index.html` as missing
            // for exactly that reason and had to be corrected.
            let listed = page.name == "index.html"
                ? sitemap.contains("<loc>https://echoelmusic.com/</loc>")
                : sitemap.contains(page.name)
            if !listed { missing.append(page.name) }
        }
        let shown = missing.joined(separator: ", ")
        XCTAssertTrue(missing.isEmpty, """
            \(missing.count) page(s) are published but absent from `docs/sitemap.xml`: \
            \(shown). A page outside the sitemap is not indexed and cannot be found by \
            anyone who does not already have the link.
            """)
    }

    /// The mirror check: a sitemap entry with no file behind it is a 404 handed to a crawler.
    func testTheSitemapPromisesNoPageThatIsMissing() throws {
        let root = try repoRoot()
        let sitemap = try String(
            contentsOf: root.appendingPathComponent("docs/sitemap.xml"), encoding: .utf8)
        var ghosts: [String] = []
        for line in sitemap.split(separator: "\n") where line.contains("<loc>") {
            guard let a = line.range(of: "<loc>"), let b = line.range(of: "</loc>") else { continue }
            let url = String(line[a.upperBound..<b.lowerBound]).trimmingCharacters(in: .whitespaces)
            guard url.hasSuffix(".html") else { continue }   // the bare domain is index.html
            let file = String(url.split(separator: "/").last ?? "")
            if !FileManager.default.fileExists(
                atPath: root.appendingPathComponent("docs/\(file)").path) { ghosts.append(file) }
        }
        let shown = ghosts.joined(separator: ", ")
        XCTAssertTrue(ghosts.isEmpty, """
            The sitemap lists \(ghosts.count) page(s) that do not exist: \(shown). A crawler \
            following it gets a 404, which costs trust in the whole file.
            """)
    }

    /// An orphan page — in the sitemap but linked from nowhere — is findable only by a
    /// crawler, never by a reader who is already on the site.
    func testNoPageIsAnOrphan() throws {
        let all = try pages()
        var orphans: [String] = []
        for page in all where page.name != "index.html" {
            let linked = all.contains { $0.name != page.name && $0.html.contains("\"\(page.name)\"") }
            if !linked { orphans.append(page.name) }
        }
        let shown = orphans.joined(separator: ", ")
        XCTAssertTrue(orphans.isEmpty, """
            \(orphans.count) page(s) are linked from no other page: \(shown). Add a link from \
            the page whose topic it continues — the footer alone is not a reading path, it is \
            a legal shelf.
            """)
    }

    // MARK: - The metadata contract every page already keeps

    /// Fifteen pages kept this contract before the sixteenth existed. Pinning it means the
    /// seventeenth cannot quietly ship without it — the failure mode is invisible, because a
    /// page with no description still looks perfect in a browser.
    func testEveryPageCarriesItsMetadata() throws {
        for page in try pages() {
            for required in ["<title>", "name=\"description\"", "rel=\"canonical\"",
                             "property=\"og:title\"", "application/ld+json"] {
                XCTAssertTrue(page.html.contains(required), """
                    `docs/\(page.name)` is missing `\(required)`. Every other page carries \
                    it; a page without it renders identically and is simply worth less \
                    everywhere it is quoted — search results, link previews, shares.
                    """)
            }
        }
    }

    /// A canonical URL that points at a different page tells search engines to index the
    /// wrong one. It is the classic copy-paste defect of building a page from another page's
    /// shell — which is exactly how the newest page here was made.
    func testEachCanonicalPointsAtItsOwnPage() throws {
        for page in try pages() {
            guard let r = page.html.range(of: "rel=\"canonical\" href=\"") else { continue }
            let rest = page.html[r.upperBound...]
            let url = String(rest.prefix { $0 != "\"" })
            // ⛔ THE TRAILING SLASH IS NOT A DEFECT AND MY FIRST DRAFT SAID IT WAS. The home
            // page declares `https://echoelmusic.com` without one while the sitemap lists it
            // WITH one; both forms are valid and resolve identically. The test was wrong, not
            // the site — so it normalises instead of demanding one spelling. Tightening this
            // into "the site must pick a form" would be inventing a rule to make a test pass.
            let normalised = url.hasSuffix("/") ? String(url.dropLast()) : url
            let expected = page.name == "index.html" ? "https://echoelmusic.com" : page.name
            XCTAssertTrue(normalised.hasSuffix(expected), """
                `docs/\(page.name)` declares its canonical URL as \(url). A canonical that \
                names another page hands that page this one's ranking and can drop this one \
                from the index entirely.
                """)
        }
    }

    // MARK: - The one claim check that IS decidable

    /// ⚠️ NARROW ON PURPOSE, AND HERE IS EXACTLY HOW FAR IT REACHES. "AUv3" is the claim that
    /// cost #158 and #192 two cycles, so it is worth a guard — but the site legitimately
    /// mentions it, always to DENY it ("it is not an Audio Unit (AUv3) plugin"). So the rule
    /// is not "the word must not appear"; it is "every occurrence must sit near a negation".
    ///
    /// What that CANNOT catch, stated so nobody trusts it further than it goes: a sentence
    /// that negates something else within the same window, or an affirmative claim phrased
    /// without any of these words. It is a tripwire against the careless re-introduction the
    /// history actually shows, not a proof of honesty. Honesty is `ContentPipeline/CLAIMS.md`
    /// plus a human.
    func testEveryAUv3MentionIsADenial() throws {
        let negations = ["not ", "no ", "never", "n't", "removed", "cannot", "can not",
                         "without", "neither", "nor "]
        var affirmatives: [String] = []
        for page in try pages() {
            let html = page.html
            var search = html.startIndex..<html.endIndex
            while let hit = html.range(of: "AUv3", range: search) {
                let lo = html.index(hit.lowerBound, offsetBy: -220, limitedBy: html.startIndex) ?? html.startIndex
                let hi = html.index(hit.upperBound, offsetBy: 120, limitedBy: html.endIndex) ?? html.endIndex
                let window = html[lo..<hi].lowercased()
                if !negations.contains(where: { window.contains($0) }) {
                    affirmatives.append("\(page.name): …\(html[lo..<hi].prefix(90))…")
                }
                search = hit.upperBound..<html.endIndex
            }
        }
        let shown = affirmatives.prefix(3).joined(separator: " | ")
        XCTAssertTrue(affirmatives.isEmpty, """
            \(affirmatives.count) mention(s) of AUv3 on the site are not near a negation: \
            \(shown). The AUv3 target was REMOVED on 2026-07-24 (#121 Slice 1+2) and the \
            hosting with it — Echoel is a standalone app, is not a plugin, and cannot load \
            one. See `ContentPipeline/CLAIMS.md` §1 before rewording anything here.
            """)
    }

    /// The scan has to actually reach the site. A directory listing that yields nothing would
    /// report a perfect green over an empty list — the silent-pass failure this repo has
    /// already paid for once in `full-tests.yml`.
    func testTheScanReachesTheSiteItClaimsToCover() throws {
        let all = try pages()
        XCTAssertGreaterThan(all.count, 10, """
            Only \(all.count) page(s) were read from `docs/`. The site has well over a dozen; \
            a truncated listing makes every assertion above vacuous.
            """)
        XCTAssertTrue(all.contains { $0.name == "index.html" }, """
            `docs/index.html` was not among the scanned pages. If the home page moved, this \
            file's index/canonical special cases are describing a site that no longer exists.
            """)
    }

    // MARK: - Counted claims (#428)

    /// Number words this scan understands, English AND German.
    ///
    /// ⛔ THE FIRST VERSION WAS ENGLISH-ONLY, AND THAT WAS NOT A GAP — IT WAS A BLIND SPOT WITH
    /// A LIVE CONSEQUENCE. `fastlane/metadata/de-DE/release_notes.txt` is App Store copy that
    /// `deliver` overwrites the live listing with, exactly like the en-US file — and it said
    /// "Acht kuratierte Genres" for a week after the roster went to sixteen. The guard could not
    /// see it twice over: the de-DE path was never a source, and `"Acht"` resolved to `nil`, so
    /// even adding the file would have produced a SILENT green over stale store copy. A guard
    /// that ignores what it cannot parse must be told every language it is expected to police.
    ///
    /// A phrase whose quantifier is genuinely absent (`the genres`, `many scales`) is still
    /// deliberately IGNORED — this guard exists to catch a WRONG number, not to demand that
    /// every mention carry one. The `checked` floor at the end of the test is what stops that
    /// tolerance from decaying into a vacuous pass.
    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60,
        "seventy": 70, "eighty": 80, "ninety": 90,
        // German. "ein"/"eine" are deliberately absent — as an article they would turn
        // "eine Auswahl der Genres" into a claim of one.
        "zwei": 2, "drei": 3, "vier": 4, "fünf": 5, "fuenf": 5, "sechs": 6, "sieben": 7,
        "acht": 8, "neun": 9, "zehn": 10, "elf": 11, "zwölf": 12, "zwoelf": 12,
        "dreizehn": 13, "vierzehn": 14, "fünfzehn": 15, "fuenfzehn": 15, "sechzehn": 16,
        "siebzehn": 17, "achtzehn": 18, "neunzehn": 19, "zwanzig": 20, "dreißig": 30,
        "dreissig": 30, "vierzig": 40, "fünfzig": 50, "fuenfzig": 50, "sechzig": 60,
        "siebzig": 70, "achtzig": 80, "neunzig": 90
    ]

    /// Words that may sit between the number and the noun without breaking the claim.
    /// `offered`/`curated` (and their German forms) additionally mark the number as the ROSTER
    /// count rather than the taxonomy — see `counts(of:in:)`.
    private static let rosterMarkers: Set<String> = [
        "curated", "offered", "kuratierte", "kuratierten", "kuratierter", "angebotene",
        "angebotenen"
    ]

    /// Determiners skipped when looking for an `of` in front of the number.
    private static let determiners: Set<String> = ["the", "die", "der", "den", "dem"]

    /// Words that CANNOT sit between a number and the noun it quantifies. Finding one means the
    /// nearest number belongs to something else — "released in 2026 the genres" is not a claim
    /// that there are 2026 genres. Adjectives (`curated`, `electronic`, `kuratierte`) are fine
    /// and are exactly what the window exists to tolerate; a determiner or a preposition is not.
    private static let claimBreakers: Set<String> =
        determiners.union(["of", "von", "in", "for", "across", "with", "und", "and"])

    private static func number(_ token: String) -> Int? {
        let t = token.lowercased()
        if let n = Int(t) { return n }
        if let n = numberWords[t] { return n }
        // "fifty-seven" (English) and "siebenundfünfzig" (German, ones first).
        let hyphen = t.split(separator: "-").map(String.init)
        if hyphen.count == 2, let tens = numberWords[hyphen[0]], let ones = numberWords[hyphen[1]],
           tens >= 20, ones < 10 {
            return tens + ones
        }
        let und = t.components(separatedBy: "und")
        if und.count == 2, let ones = numberWords[und[0]], let tens = numberWords[und[1]],
           tens >= 20, ones < 10 {
            return tens + ones
        }
        return nil
    }

    /// Every quantified mention of `noun` in `text`, as (spelled token, value, isSubsetClaim).
    ///
    /// ⭐ THE TAXONOMY-vs-ROSTER SPLIT IS THE WHOLE DESIGN, and it was found by running this
    /// scan before writing the assertion: `docs/architecture.html` says "22 of 33 genres carry
    /// their own [reverb] values". That 33 is the TAXONOMY (`MusicStyle.allCases`), not the
    /// roster, and a guard that compared it to `MusicStyle.offered.count` would have gone red on
    /// a correct sentence — the #364 mistake this file's header already apologises for once.
    ///
    /// ⛔ THE FIRST VERSION DECIDED THAT SPLIT WITH A REGEX PREFIX `(of\s+)?` DIRECTLY IN FRONT
    /// OF THE NUMBER, AND IT WAS UNSOUND IN BOTH DIRECTIONS — the reviewer found all three cases
    /// and each is a phrasing already in use somewhere in this tree:
    ///   · `"22 of the 33 genres"` — `the` is not a number, so the `of` could not bind and the
    ///     33 was compared to the ROSTER. One inserted word turns the guard red on correct copy.
    ///   · `"8 of 16 offered genres"` (the shape at `EchoelStudioView.swift:5201`) — `of` bound,
    ///     so the 16 was compared to the TAXONOMY. Red on correct copy again, opposite cause.
    ///   · `"16 electronic genres"` — `electronic` was not in the whitelist, the match consumed
    ///     the phrase, and because `NSRegularExpression` matches are non-overlapping the number
    ///     was never checked at all. An ordinary copy edit could silently disarm the guard.
    ///
    /// So the split is no longer positional. The scan takes a window of up to three words in
    /// front of the noun, finds the NEAREST token that parses as a number (which tolerates any
    /// adjectives), and then decides:
    ///   1. a roster marker between the number and the noun (`offered`, `kuratierte`) ⇒ ROSTER;
    ///   2. otherwise an `of`/`von` in front of the number, determiners skipped ⇒ TAXONOMY;
    ///   3. otherwise ⇒ ROSTER.
    /// Rule 1 is checked FIRST on purpose: "N offered genres" states the roster whatever
    /// precedes it. The window cannot cross punctuation — only word characters and spaces match
    /// — which is what keeps a list ("… — eight on the ambient shelf") out of the window.
    ///
    /// ⚠️ A THREE-WORD WINDOW INTRODUCES ITS OWN FALSE POSITIVE, AND IT WAS MEASURED, NOT
    /// ASSUMED: `"released in 2026 the genres"` read 2026 as the quantifier. So a determiner or
    /// a preposition between the number and the noun (`claimBreakers`) rejects the match
    /// outright — an adjective may sit there, a `the` may not. Nothing in the scanned sources
    /// hits this today; it is guarded because widening the window is what made it reachable.
    private static func counts(of noun: String, in text: String) -> [(String, Int, Bool)] {
        let word = "[A-Za-z0-9\u{00C0}-\u{024F}-]+"
        // NOTE: `\\b` and `\\t` must reach ICU as escapes, so they are DOUBLE-escaped here.
        // A single `\\b` in a Swift literal is not a valid Swift escape and does not compile.
        let pattern = "((?:" + word + "[ \\t]+){1,3})" + noun + "\\b"
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return [] }
        let ns = text as NSString
        return rx.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { m -> (String, Int, Bool)? in
                let prefix = ns.substring(with: m.range(at: 1))
                let tokens = prefix.split(whereSeparator: { $0 == " " || $0 == "\t" })
                    .map(String.init)
                guard let numberIndex = tokens.indices.reversed().first(where: {
                    number(tokens[$0]) != nil
                }), let value = number(tokens[numberIndex]) else { return nil }

                let between = tokens[(numberIndex + 1)...].map { $0.lowercased() }
                guard !between.contains(where: { claimBreakers.contains($0) }) else { return nil }
                if between.contains(where: { rosterMarkers.contains($0) }) {
                    return (tokens[numberIndex], value, false)
                }
                var before = tokens[..<numberIndex].map { $0.lowercased() }
                while let last = before.last, determiners.contains(last) { before.removeLast() }
                let isSubset = before.last == "of" || before.last == "von"
                return (tokens[numberIndex], value, isSubset)
            }
    }

    /// Marketing copy that states HOW MANY genres or scales Echoel offers must agree with the
    /// app. #254 took the roster to sixteen and #232 J took the scale list to 57; every public
    /// "eight curated genres … 50 scales" went stale on the day of those commits (both
    /// 2026-07-30) and stayed stale until 2026-08-06 — across THREE site pages
    /// (`brainstorming`, `press`, `tools`; `architecture` carried a correct taxonomy claim and
    /// was right to be left alone) and the LIVE App Store release notes in BOTH locales (#428).
    /// Measured: 10 of the 11 claims this scan finds were wrong on `5bcc000^`.
    ///
    /// The counts come from the SAME expressions the app uses — `MusicStyle.offered` and
    /// `Scale.Family.allCases.flatMap(\.scales)`, which is what the grouped picker iterates
    /// (`ScaleFamilyTests` guards that it covers `Scale.allCases`). Hardcoding 16/57 here would
    /// simply move the staleness into this file.
    ///
    /// ⚠️ Understating is not an App Store 2.3 rejection the way overstating is — but it is
    /// still a false claim, and this repo has twice paid a full cycle to remove one (#158/#192,
    /// #184). The guard treats both directions the same.
    func testPublishedGenreAndScaleCountsMatchTheApp() throws {
        let expectedGenres = MusicStyle.offered.count
        let expectedScales = Scale.Family.allCases.flatMap(\.scales).count

        var sources = try pages().map { (name: "docs/\($0.name)", text: $0.html) }
        // BOTH store locales. `fastlane/Deliverfile` ships en-US and de-DE with
        // `skip_metadata false`, so both files ARE the live listing; only en-US was scanned
        // until the de-DE notes were caught stale a week after the roster changed.
        for locale in ["en-US", "de-DE"] {
            let notes = try repoRoot()
                .appendingPathComponent("fastlane/metadata/\(locale)/release_notes.txt")
            if let text = try? String(contentsOf: notes, encoding: .utf8) {
                sources.append((name: "fastlane/metadata/\(locale)/release_notes.txt",
                                text: text))
            }
        }

        let taxonomyGenres = MusicStyle.allCases.count
        let taxonomyScales = Scale.allCases.count

        var checked = 0
        for source in sources {
            for (token, value, isSubset) in Self.counts(of: "genres", in: source.text) {
                checked += 1
                let expected = isSubset ? taxonomyGenres : expectedGenres
                // Hoisted, not folded into the literal: a newline INSIDE a `\( … )` segment is
                // legal only in a multiline literal and has no precedent in this repo, and a
                // ternary-of-literals inside an already-heavy message is the #287 type-check
                // cost that turned the blocking gate red once.
                let claim = isSubset ? "the taxonomy" : "the app's roster"
                XCTAssertEqual(value, expected, """
                    \(source.name) says "\(isSubset ? "of " : "")\(token) genres"; \
                    \(claim) holds \(expected). Published copy must be recounted in the same \
                    commit that changes the roster.
                    """)
            }
            let scaleClaims = Self.counts(of: "scales", in: source.text)
                + Self.counts(of: "skalen", in: source.text)
            for (token, value, isSubset) in scaleClaims {
                checked += 1
                let expected = isSubset ? taxonomyScales : expectedScales
                XCTAssertEqual(value, expected, """
                    \(source.name) says "\(isSubset ? "of " : "")\(token) scales"; the picker \
                    offers \(expectedScales) and the enum holds \(taxonomyScales).
                    """)
            }
        }

        // Without this the whole test is vacuous the day someone rewords the copy to drop every
        // number — a green that was never earned, the failure mode this file's header names.
        XCTAssertGreaterThanOrEqual(checked, 6, """
            Only \(checked) quantified genre/scale claim(s) were found across \
            \(sources.count) source(s). The site and the two release-note locales carried \
            eleven at #428, ten of them wrong; if the copy legitimately stopped counting, \
            lower this floor deliberately rather than letting the scan pass over nothing.
            """)
    }
}
