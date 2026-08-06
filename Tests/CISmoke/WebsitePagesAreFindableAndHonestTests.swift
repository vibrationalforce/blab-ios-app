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

    /// English number words this scan understands. A phrase whose quantifier is NOT in here
    /// (`the genres`, `electronic genres`, `many scales`) is deliberately IGNORED — this guard
    /// exists to catch a WRONG number, not to demand that every mention carry one.
    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
        "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
        "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60,
        "seventy": 70, "eighty": 80, "ninety": 90
    ]

    private static func number(_ token: String) -> Int? {
        let t = token.lowercased()
        if let n = Int(t) { return n }
        if let n = numberWords[t] { return n }
        // "fifty-seven"
        let parts = t.split(separator: "-").map(String.init)
        if parts.count == 2, let tens = numberWords[parts[0]], let ones = numberWords[parts[1]],
           tens >= 20, ones < 10 {
            return tens + ones
        }
        return nil
    }

    /// Every quantified mention of `noun` in `text`, as (spelled token, value, isSubsetClaim).
    ///
    /// ⭐ THE `of` PREFIX IS THE WHOLE DESIGN, and it was found by running this scan before
    /// writing the assertion: `docs/architecture.html` says "22 of 33 genres carry their own
    /// [reverb] values". That 33 is the TAXONOMY (`MusicStyle.allCases`), not the roster, and a
    /// guard that compared it to `MusicStyle.offered.count` would have gone red on a correct
    /// sentence — the #364 mistake this file's header already apologises for once. So a match
    /// preceded by `of` is checked against the taxonomy instead of being skipped: still
    /// guarded, just against the number it is actually claiming.
    private static func counts(of noun: String, in text: String) -> [(String, Int, Bool)] {
        let pattern = "(of\\s+)?([A-Za-z0-9-]+)\\s+(?:curated\\s+|offered\\s+)?" + noun + "\\b"
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return [] }
        let ns = text as NSString
        return rx.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { m in
                let token = ns.substring(with: m.range(at: 2))
                guard let value = number(token) else { return nil }
                return (token, value, m.range(at: 1).location != NSNotFound)
            }
    }

    /// Marketing copy that states HOW MANY genres or scales Echoel offers must agree with the
    /// app. #254 added eight genres and #232's shelves took the scale list to 57; every public
    /// "eight curated genres … 50 scales" went stale on the day of those commits and stayed
    /// stale — across four site pages and the LIVE App Store release notes (#428).
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
        let notes = try repoRoot()
            .appendingPathComponent("fastlane/metadata/en-US/release_notes.txt")
        if let text = try? String(contentsOf: notes, encoding: .utf8) {
            sources.append((name: "fastlane/metadata/en-US/release_notes.txt", text: text))
        }

        let taxonomyGenres = MusicStyle.allCases.count
        let taxonomyScales = Scale.allCases.count

        var checked = 0
        for source in sources {
            for (token, value, isSubset) in Self.counts(of: "genres", in: source.text) {
                checked += 1
                let expected = isSubset ? taxonomyGenres : expectedGenres
                XCTAssertEqual(value, expected, """
                    \(source.name) says "\(isSubset ? "of " : "")\(token) genres"; \
                    \(isSubset ? "the taxonomy holds \(taxonomyGenres) (`MusicStyle.allCases`)"
                               : "the app offers \(expectedGenres) (`MusicStyle.offered`)"). \
                    Published copy must be recounted in the same commit that changes the roster.
                    """)
            }
            for (token, value, isSubset) in Self.counts(of: "scales", in: source.text) {
                checked += 1
                let expected = isSubset ? taxonomyScales : expectedScales
                XCTAssertEqual(value, expected, """
                    \(source.name) says "\(isSubset ? "of " : "")\(token) scales"; the picker \
                    offers \(expectedScales) (`Scale.Family.allCases.flatMap(\\.scales)`).
                    """)
            }
        }

        // Without this the whole test is vacuous the day someone rewords the copy to drop every
        // number — a green that was never earned, the failure mode this file's header names.
        XCTAssertGreaterThanOrEqual(checked, 6, """
            Only \(checked) quantified genre/scale claim(s) were found across \
            \(sources.count) source(s). The site and the release notes carried nine before \
            #428; if the copy legitimately stopped counting, lower this floor deliberately \
            rather than letting the scan pass over nothing.
            """)
    }
}
