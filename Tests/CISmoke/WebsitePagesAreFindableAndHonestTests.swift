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
}
