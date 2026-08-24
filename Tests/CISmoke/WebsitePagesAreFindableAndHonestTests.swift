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
//
// ⚠️ SCOPE, because a guard that looks broader than it is will be trusted further than it
// should be. `pages()` uses a NON-RECURSIVE listing of `docs/*.html`. It can therefore never
// see `README.md` — the file a GitHub visitor reads first — nor `docs/dev/**`, nor
// `fastlane/metadata` (which only the counted-claims test reaches, and only because that test
// names those paths explicitly). This is not theoretical: the #436 sweep found the SAME false
// "RTMP was built and removed" sentence sitting in `README.md`, where no assertion in this file
// could ever have reached it. When a claim is corrected on the site, grep the whole repo for it.

import Foundation
import XCTest
// #428: the counted-claims test reads `MusicStyle.offered` and `Scale.Family` so the published
// numbers are chained to the app instead of copied from it. Every other test here is pure text.
@testable import Echoelmusic

final class WebsitePagesAreFindableAndHonestTests: XCTestCase {

    /// Every locale directory under `fastlane/metadata/`, read rather than assumed.
    ///
    /// ⚠️ It returns an EMPTY list rather than failing, because this file's store-notes scan is
    /// an ADDITION to its `docs/` sources: the surrounding test still checks every website page
    /// if the metadata tree is absent. The sibling `TheStoreTextClaimsOnlyWhatShipsTests` reads
    /// nothing else, so there the same walk must FAIL — same helper name, deliberately
    /// different contract, and the difference is written down because it is not guessable.
    private func localeDirectories() throws -> [String] {
        let base = try repoRoot().appendingPathComponent("fastlane/metadata")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: base.path)) ?? []
        return names.filter { name in
            var isDir: ObjCBool = false
            let path = base.appendingPathComponent(name).path
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
                && isDir.boolValue
        }.sorted()
    }

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
    ///
    /// ⚠️ CONVERTED to `mentionsWithoutMarker` (#436). It carried its own copy of that windowed
    /// walk until the RTMP and Ableton-Link checks needed the same shape — at which point
    /// leaving it alone would have shipped THREE copies of one decision while the helper's own
    /// doc cited #416 as the reason it exists. The only behavioural change is that the search
    /// is now case-insensitive: for the literal "AUv3" that can only ADD matches, so the check
    /// is strictly stricter, never looser.
    func testEveryAUv3MentionIsADenial() throws {
        let negations = ["not ", "no ", "never", "n't", "removed", "cannot", "can not",
                         "without", "neither", "nor "]
        let affirmatives = try mentionsWithoutMarker("AUv3", markers: negations,
                                                     back: 220, forward: 120)
        let shown = affirmatives.prefix(3).joined(separator: " | ")
        XCTAssertTrue(affirmatives.isEmpty, """
            \(affirmatives.count) mention(s) of AUv3 on the site are not near a negation: \
            \(shown). The AUv3 target was REMOVED on 2026-07-24 (#121 Slice 1+2) and the \
            hosting with it — Echoel is a standalone app, is not a plugin, and cannot load \
            one. See `ContentPipeline/CLAIMS.md` §1 before rewording anything here.
            """)
    }

    /// ⭐ #439 — THE PRESS KIT UNDERSTATED WHAT SHIPS, and understating is the direction this
    /// repo keeps failing to notice.
    ///
    /// `press.html`'s "What ships today" list said "stamped WAV export … plus MIDI **input**
    /// from an external controller" — no MIDI FILE export at all — while BOTH App Store
    /// descriptions have claimed `.mid` export since #188 put the door back in the existing
    /// export drawer. Two published surfaces, opposite claims, and the press kit is the one a
    /// journalist copies. #428 already wrote the rule this test enforces: *"understating is not
    /// an App Store 2.3 rejection the way overstating is — but it is still a false claim."*
    ///
    /// The chain is the point, in BOTH directions:
    ///   · Premise — MIDI export is REACHABLE (`exportMIDI()` has a caller, not just a
    ///     declaration). If a future slice removes the door, this fails FIRST and names the
    ///     published places that then have to stop claiming it.
    ///   · Claim — given that premise, every page that already claims WAV export must claim
    ///     MIDI export too, and so must both store descriptions.
    ///
    /// ⚠️ Comments are stripped before counting, and that is load-bearing here rather than
    /// prophylactic. `exportMIDI` occurs SIX times across `Sources/**` — all six in
    /// `EchoelStudioView.swift`, which is the only file that mentions it today: two in code
    /// (the declaration plus the one caller) and FOUR in comments, including one whose whole
    /// subject is the period when it had NO caller. On raw text the premise would read "six"
    /// and could never fail. (⛔ It said EIGHT — "two in code and SIX in comments" — until
    /// #482's Nachlese re-counted. #482 deleted the old full-width MIDI button and the comment
    /// block that explained it, and changed this neighbouring guard's prose without touching
    /// it: the assertion is `>= 2` so nothing went red, and the number is the load-bearing
    /// half of the argument for why stripping comments matters here. #456's rule — a commit
    /// that reshapes a surface pulls its guards along — applies to PROSE as well.)
    /// (⛔ An earlier version of this sentence said "six DOC comments". Three of the six are
    /// plain `//`. The claim was about a count I had, and a kind I had not looked at — the
    /// cheapest possible version of the mistake this whole file exists to catch.)
    ///
    /// ⚠️ Two limits stated rather than hidden:
    ///   · The premise scans ALL of `Sources/**`, not one file. Pinning the path would make an
    ///     ordinary extraction (`exportMIDI` moving into a helper) red, and the obvious repair
    ///     would then be to delete a TRUE claim from the website.
    ///   · The claim side is substring-matching and therefore NEGATION-BLIND: a page that said
    ///     "MIDI file export is not in this build" would satisfy it. That is acceptable here
    ///     because the failure mode being guarded is silence, not denial — and denial is what
    ///     `testTheSiteDoesNotClaimAUv3` already handles, with the surrounding-window machinery
    ///     this assertion deliberately does not duplicate.
    ///   · `pages()` enumerates `docs/*.html` only, so the Markdown under `docs/dev/**` — which
    ///     IS published and indexed — is NOT covered. `docs/dev/APP_STORE_LISTING_v1.md` was in
    ///     fact stale on both halves when this was written, and was fixed by hand rather than
    ///     by widening the scan: those files are drafts and internal notes whose claims are
    ///     deliberately provisional, so a green/red verdict over them would mean something
    ///     different than it does over a live page.
    func testTheSiteAndTheStoreAgreeThatMIDIExportShips() throws {
        let sources = try repoRoot().appendingPathComponent("Sources")
        guard let walk = FileManager.default.enumerator(atPath: sources.path) else {
            throw XCTSkip("`Sources/` is not present — a docs-only checkout cannot judge the premise")
        }
        var mentions = 0
        for case let rel as String in walk where rel.hasSuffix(".swift") {
            let text = try String(contentsOf: sources.appendingPathComponent(rel), encoding: .utf8)
            mentions += SourceText.codeOnly(text).components(separatedBy: "exportMIDI").count - 1
        }
        XCTAssertGreaterThanOrEqual(mentions, 2, """
            `exportMIDI` appears \(mentions) time(s) in the CODE of `Sources/**` (comments \
            stripped). Two is the floor: the declaration plus at least one caller.

            Zero means the symbol was renamed — re-anchor this scan, do not weaken it. One \
            means the door was removed and MIDI export is unreachable again, which is exactly \
            the state #188 was opened to end. If that removal is deliberate, the SAME commit \
            must strike the claim from every surface listed below, because a shipped store \
            description promising an export the app cannot perform is an App Store 2.3 \
            rejection, not a stale sentence.
            """)

        // Given the premise, every published surface has to carry it. Spellings rather than one
        // needle: the press kit writes prose, the store files write a bullet, and pinning one
        // phrasing would make an ordinary copy edit red — the #364 trap.
        let spellings = ["MIDI file export", "MIDI export", "als MIDI", "as MIDI", "(.mid",
                         ".mid)", "MIDI-Datei", "MIDI file"]

        // ⭐ THE RULE, not a list of three files. The first version of this test hard-coded
        // `press.html` plus the two store descriptions — and this file's own header prescribes
        // the opposite ("When a claim is corrected on the site, grep the WHOLE repo for it").
        // Measured at the time: EIGHT pages claim WAV export; only `press.html` was covered, so
        // seven could have gone stale green — and THREE of them actually were. `privacy.html`'s
        // Portability bullet offered "export your takes as WAV" and nothing else.
        //
        // The needle is a bare, CASE-SENSITIVE "WAV", which is both broader and safer than the
        // phrase list I first wrote. Broader: an intermediate version listed "WAV export",
        // "as WAV", "(WAV)" and ".wav" — and `tools.html` fell OUT of the set the moment its
        // copy was reworded to "WAV and MIDI file export", i.e. the needle list tracked MY
        // phrasing rather than the site's claim. Safer than lowercase: "wav" is a substring of
        // "Vaporwave", a genre name that appears on two pages; "WAV" is not.
        var checked: [String] = []
        for page in try pages() where page.html.contains("WAV") {
            checked.append(page.name)
            XCTAssertTrue(spellings.contains { page.html.contains($0) }, """
                `docs/\(page.name)` claims WAV export and says nothing about MIDI file export, \
                but the app ships both (`exportMIDI()` has a caller — see the assertion above).

                This is the #439 defect in the direction that is easy to miss: the page \
                UNDERSTATES. `press.html` carried "WAV export … plus MIDI input" for weeks \
                while both store descriptions promised `.mid` export — two published surfaces \
                disagreeing, with the press kit being the one a journalist copies.

                Spellings accepted: \(spellings.joined(separator: ", ")).
                """)
        }
        XCTAssertGreaterThanOrEqual(checked.count, 6, """
            Only \(checked.count) page(s) mention WAV: \(checked.joined(separator: ", ")). \
            EIGHT did when this rule was written. A needle that suddenly matches almost nothing \
            is how this assertion goes quiet without anyone editing it — the silent-pass \
            failure `full-tests.yml` already cost this repo. The floor is 6 rather than 8 on \
            purpose: two pages may legitimately stop discussing export, but a drop below that \
            means the needle broke, not the copy.
            """)

        // The store descriptions are not pages and are checked by name: they are the two files
        // `deliver` overwrites the LIVE listing with, so a stale one is a 2.3 rejection rather
        // than a stale sentence.
        for surface in ["fastlane/metadata/en-US/description.txt",
                        "fastlane/metadata/de-DE/description.txt"] {
            let url = try repoRoot().appendingPathComponent(surface)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                XCTFail("""
                    \(surface) is missing while the tree is present — it was renamed or moved. \
                    Re-anchor this scan; do not let it pass silently.
                    """)
                continue
            }
            XCTAssertTrue(spellings.contains { text.contains($0) }, """
                \(surface) does not mention MIDI file export, but the app ships it. This file \
                is uploaded verbatim to the App Store listing.

                Spellings accepted: \(spellings.joined(separator: ", ")).
                """)
        }
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
        // EVERY store locale, READ rather than typed. `fastlane/Deliverfile` ships this
        // directory with `skip_metadata false`, so these files ARE the live listing.
        //
        // ⛔ THIS LINE IS THE SECOND REPAIR OF ONE DEFECT (#769). The note that stood here
        // recorded the first: "only en-US was scanned until the de-DE notes were caught stale
        // a week after the roster changed" — and the repair then was to TYPE the second locale
        // in, which leaves a third to be skipped in the same silence. #768 hit the identical
        // shape one level in (three of five metadata leaves hand-typed) on the sibling guard.
        // A hand-typed subset of a directory reads as an enumeration and is not one.
        for locale in try localeDirectories() {
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

    // MARK: - Never-built claims (#436 / #437)

    /// Every mention of `needle` must sit within a window of at least one `markers` phrase.
    /// `testEveryAUv3MentionIsADenial` carried the only copy of this walk until the RTMP and
    /// Ableton-Link checks needed the same shape; all three now call this, because three
    /// hand-rolled copies of one decision is the #416 double-definition defect.
    ///
    /// ⚠️ THIS HELPER COUNTS CHARACTERS (graphemes); `testMotionIsNotListedAsABodySignalTheAppSenses`
    /// counts UTF-16 units, because it drives `NSRegularExpression` and must speak `NSRange`.
    /// They agree on this tree and are NOT interchangeable in general — do not "unify" them by
    /// swapping one unit for the other.
    ///
    /// #796 — the two synth modules that cannot sound are not sold as live.
    ///
    /// `EchoelSynth` is a TAXONOMY, not a type: two published places name the modules grouped
    /// under it, and both read them as shipping. `EchoelModalBank`'s only caller was the drum
    /// voice removed by #167; `EchoelCellular` never had one. Both stay in the tree deliberately
    /// (the founder said "erstmal") — what must not stay is a public line reading them as live.
    ///
    /// ⭐ THE PREMISE IS MEASURED, SO THIS CANNOT BECOME A TRAP (#364). It counts `Module(` in
    /// the CODE of `Sources/**` first and skips any module with even one instantiation. The day
    /// somebody wires one, the guard stops demanding a qualifier instead of forbidding the work;
    /// there is no "lift this in the same commit" instruction because there is nothing to lift.
    /// Comments are stripped for a concrete reason: CLAUDE.md's note about `EchoelModalBank`
    /// QUOTES the recipe `git grep -n "EchoelModalBank(" -- Sources`, so a source file quoting
    /// that note back would make a naive scan read documentation as an instantiation.
    ///
    /// ⛔ THE FIRST DRAFT OF THIS GUARD WAS GREEN ON THE BROKEN PARENT, and driving it is the
    /// only reason that was found. It asked, per FILE, whether a not-wired marker appears
    /// anywhere — chosen to avoid flagging a legitimate third mention (#486). But the defect WAS
    /// a roster line contradicting a detail row IN THE SAME FILE (#425), which per-file can
    /// never see: `architecture.html` carried "Not wired" on lines 224/225 and sold both modules
    /// as LIVE on line 346. A window-based version then false-alarmed on `FEATURE_MATRIX.md`,
    /// where every entry has a `**Code:**` line followed by a `**Live:**` line and one paragraph
    /// legitimately names the module while discussing a documentation lesson. So both halves are
    /// ANCHORED at the exact claim instead: no windows, no proximity, no false alarms (#665).
    func testTheUnwiredSynthModulesAreNotSoldAsLive() throws {
        let modules = ["EchoelModalBank", "EchoelCellular"]
        let notWired = ["not wired", "no voice instantiates", "makes no sound",
                        "neither makes a sound", "nicht verdrahtet"]

        let sources = try repoRoot().appendingPathComponent("Sources")
        guard let walk = FileManager.default.enumerator(atPath: sources.path) else {
            throw XCTSkip("`Sources/` is not present — a docs-only checkout cannot judge the premise")
        }
        var code = ""
        for case let rel as String in walk where rel.hasSuffix(".swift") {
            let text = try String(contentsOf: sources.appendingPathComponent(rel), encoding: .utf8)
            code += SourceText.codeOnly(text)
        }
        XCTAssertFalse(code.isEmpty, """
            The walk over `Sources/**` read no Swift at all, so the premise was never measured \
            and both assertions below would have passed vacuously (#454). Re-point the walk in \
            the same commit as whatever moved the sources.
            """)

        let unsounding = modules.filter { code.components(separatedBy: $0 + "(").count - 1 == 0 }
        guard !unsounding.isEmpty else { return }   // all wired — nothing left to qualify

        // ANCHOR 1 — the published roster row on the website.
        let html = try String(contentsOf: try repoRoot()
            .appendingPathComponent("docs/architecture.html"), encoding: .utf8)
        // A plain literal with escaped quotes, NOT a `"""` block: Swift forbids content
        // on the delimiter line, and the first draft wrote exactly that — the #792 class
        // of break, caught here by reading the emitted line instead of trusting the patch.
        let rosterKey = "<div class=\"k\">EchoelSynth "
        guard let keyAt = html.range(of: rosterKey) else {
            return XCTFail("""
                `docs/architecture.html` no longer carries a `<div class="k">EchoelSynth ` \
                roster row, so this guard checked nothing (#454). If the roster moved, \
                re-anchor it here in the same commit — do not delete the check.
                """)
        }
        let rowEnd = html.range(of: "</div></div>", range: keyAt.upperBound..<html.endIndex)
        let row = String(html[keyAt.upperBound..<(rowEnd?.upperBound ?? html.endIndex)]).lowercased()
        for module in unsounding where row.contains(module.lowercased()) {
            XCTAssertTrue(notWired.contains(where: { row.contains($0) }), """
                The EchoelSynth roster row in `docs/architecture.html` lists \(module) beside \
                `EchoelDDSP` under a LIVE tag, with no word saying it cannot sound.

                It has ZERO instantiations in the code of `Sources/**`. The detail rows higher \
                up the same page already say "Not wired" and "no voice instantiates it today" — \
                so the page contradicted itself, and the roster row is the one a skimmer reads. \
                Say it in the row, or wire the module.
                """)
        }

        // ANCHOR 2 — the reference document's Live inventory for the same tool.
        let matrix = try String(contentsOf: try repoRoot()
            .appendingPathComponent("docs/dev/FEATURE_MATRIX.md"), encoding: .utf8)
        guard let section = matrix.range(of: "### 1. EchoelSynth") else {
            return XCTFail("""
                `docs/dev/FEATURE_MATRIX.md` no longer has a "### 1. EchoelSynth" section, so \
                the second half of this guard checked nothing (#454). Re-anchor it here.
                """)
        }
        let after = matrix[section.upperBound...]
        let liveLine = after.split(separator: "\n").first { $0.hasPrefix("- **Live:**") }
        guard let live = liveLine.map({ $0.lowercased() }) else {
            return XCTFail("""
                The "### 1. EchoelSynth" section carries no `- **Live:**` line any more, so the \
                inventory this guard reads is gone (#454). Re-anchor it here.
                """)
        }
        for word in ["modal", "cellular"] where live.contains(word) {
            XCTFail("""
                `FEATURE_MATRIX.md`'s EchoelSynth Live line still sells "\(word)" synthesis.

                Neither `EchoelModalBank` nor `EchoelCellular` is instantiated anywhere in the \
                code of `Sources/**` — this line read "DDSP / modal / cellular synthesis" until \
                #796. This is the document a session reads to decide what is live, so a false \
                entry here plans the next cycle's work around a module that makes no sound. \
                Wire it, or leave it out of the Live line.
                """)
        }
    }

    /// ⚠️ THE WINDOW IS ASYMMETRIC ON PURPOSE and the numbers are not decorative: English
    /// qualifies AFTER the noun far more often than before it ("RTMP was never built"), so the
    /// forward reach carries most of the weight, while the backward reach only has to cross a
    /// heading or a `<div>`. Widening either is safe for correctness — a bigger window can only
    /// make the guard MISS a lie, never invent one — but it is what turns a guard into
    /// decoration, so widen it deliberately and say why.
    private func mentionsWithoutMarker(_ needle: String, markers: [String],
                                       back: Int, forward: Int) throws -> [String] {
        // ⛔ Every index below is an index into `html`, and the window is lowercased only AFTER
        // it is cut. The first draft searched a pre-lowercased copy and then sliced `html` with
        // those indices — indices are not portable between two Strings, and `lowercased()` is
        // not even length-preserving in general (ß, İ). It would have worked on this tree and
        // trapped on the first non-ASCII page. `.caseInsensitive` on the search removes the
        // need for the second string entirely.
        var offenders: [String] = []
        for page in try pages() {
            let html = page.html
            var search = html.startIndex..<html.endIndex
            while let hit = html.range(of: needle, options: [.caseInsensitive], range: search) {
                let lo = html.index(hit.lowerBound, offsetBy: -back, limitedBy: html.startIndex)
                    ?? html.startIndex
                let hi = html.index(hit.upperBound, offsetBy: forward, limitedBy: html.endIndex)
                    ?? html.endIndex
                let window = html[lo..<hi].lowercased()
                if !markers.contains(where: { window.contains($0) }) {
                    offenders.append("\(page.name): …\(html[lo..<hi].prefix(110))…")
                }
                search = hit.upperBound..<html.endIndex
            }
        }
        return offenders
    }

    /// RTMP was NEVER BUILT. Measured on the tree this commit repaired: SEVEN mentions across
    /// FIVE pages had no never-built marker anywhere near them.
    ///
    /// ⛔ WHY "NOT PLANNED" IS NOT AN ACCEPTED MARKER HERE, AND THIS IS THE WHOLE POINT OF THE
    /// TEST. The false sentences were not enthusiastic — they were *disclaimers*. They read
    /// "RTMP … is not planned (built and removed, July 2026)" and "video editing and RTMP were
    /// built and removed". Six of the seven correctly told a reader RTMP is absent and attached
    /// the wrong REASON: they invented a shipped-then-withdrawn broadcast stack. That is a claim
    /// about engineering history a journalist can quote and an integrator can plan against ("so
    /// the code exists — how hard can re-enabling it be?"). The seventh, a bare
    /// `<li>RTMP / live broadcast</li>` under a "Built, shipped, and then removed" heading,
    /// attached no reason at all and inherited the wrong one from the heading.
    ///
    /// ⛔ AND THE NUMBER IN THIS PARAGRAPH HAS NOW BEEN WRONG TWICE, IN OPPOSITE DIRECTIONS —
    /// which is the reason it is now a measurement and not an intuition. It first read "would
    /// have passed all five" (a leftover count), was "corrected" to "all seven" on the
    /// assumption that a looser marker set can only be looser, and the real figure is **two**:
    /// adding "not planned" to `markers` takes the offender count from 7 to 5, silencing exactly
    /// the `architecture.html` "Further roadmap" row and the `tools.html` roadmap paragraph —
    /// the only two false sentences that contain the phrase. The argument is unchanged and the
    /// two it silences include the loudest of them; but a prohibition defended by a refutable
    /// number is worth less than one defended by none. Measure, then write the sentence.
    ///
    /// So the accepted markers are exactly the ones that contradict *having been built* — a
    /// disclaimer is not a contradiction.
    ///
    /// The truth, chained below rather than restated: `Package.swift` declares
    /// `dependencies: []`, HaishinKit is not a dependency, and `BroadcastPublisher` is a
    /// `#if canImport(HaishinKit)` scaffold that cannot compile into a working publisher. The
    /// deletion that DID happen in July 2026 was the video EDITOR (#121 Slice 3) — the two got
    /// merged into one sentence, and the sentence outlived the check.
    ///
    /// ⚠️ WHAT THIS CANNOT DO: it cannot catch the same lie phrased without the token, e.g.
    /// "live streaming was built and removed". That is the #364 limit and it is real — but
    /// "RTMP" is the term every one of the seven offenders used, and a scan for the generic word
    /// `streaming` collides with legitimate copy on three pages: `architecture.html` (the
    /// "streaming −14 LUFS" target and a "Lighting / streaming" row), `artnet-sacn-from-a-phone`
    /// ("Streaming ACN", "keeps streaming underneath") and `brainstorming.html` ("HR/HRV
    /// streaming"). Narrow and honest beats broad and disarmed.
    func testNothingClaimsRTMPWasEverBuilt() throws {
        let manifest = try String(
            contentsOf: try repoRoot().appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertTrue(manifest.contains("dependencies: []"), """
            `Package.swift` no longer declares an empty dependency list. If HaishinKit (or any \
            RTMP stack) was actually linked, this whole test is describing a build that no \
            longer exists — reword the site FIRST, then delete or invert this guard.
            """)

        let markers = ["never built", "scoped and cut", "scaffold", "not linked", "never linked"]
        let offenders = try mentionsWithoutMarker("RTMP", markers: markers,
                                                  back: 260, forward: 200)
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) mention(s) of RTMP on the site are not near any of \(markers): \
            \(offenders.prefix(3).joined(separator: " | ")). RTMP was never built — say "scoped \
            and cut, never built", not "built and removed" (that was the VIDEO EDITOR, #121 \
            Slice 3). See `ContentPipeline/CLAIMS.md` before rewording.
            """)
    }

    /// Ableton Link is a roadmap item with ZERO code: `git grep -E "AbletonLink|LinkKit|ABLLink"`
    /// over `Sources/` returns nothing, and `Package.swift` links nothing. Eight of the ten
    /// phrased site mentions already said "roadmap"/"planned"; the two that did not were a bare
    /// `<li>Ableton Link</li>` and an ideas-page list — both technically under a heading that
    /// qualified them, but too far away for any window a guard can justify, so both were given
    /// their own qualifier.
    ///
    /// The worst offender was not phrased at all: a spec-table badge reading `MIDI · Link` —
    /// no verb, no qualifier, in a row of things that ship today. That is how an unqualified
    /// claim survives a truth pass: it is not a sentence, so nobody reads it as one.
    ///
    /// ⚠️ THIS GUARD CANNOT SEE THAT BADGE, AND THAT IS WORTH STATING RATHER THAN GLOSSING. It
    /// scans for the two-word phrase "Ableton Link"; the badge said only "Link", and scanning
    /// for the bare token over HTML is unusable (`<link>`, "linked", "linking", every anchor's
    /// prose). So the badge was fixed by hand and this test protects only the phrased mentions.
    /// A green here means no PROSE overclaims Link — not that no abbreviation does.
    ///
    /// ⚠️ AND IT IS MATERIALLY WEAKER THAN THE RTMP CHECK ABOVE — same shape, worse markers.
    /// "roadmap" and "planned" are the site's own badge vocabulary: `architecture.html` carries
    /// 24 "roadmap" and 9 "planned" tokens, `faq.html` and `overview.html` a comparable density.
    /// On those pages a 440-character window will often contain an unrelated
    /// `<span class="tag">ROADMAP</span>`, so a fresh unqualified mention placed one table row
    /// over would pass. It is not unfalsifiable — it DID fire on the bare `<li>Ableton Link</li>`
    /// even on the page with 24 roadmap tokens — but it is a tripwire, not a proof. The RTMP
    /// markers are specific phrases the site does not otherwise use; these are not.
    func testEveryAbletonLinkMentionIsUnshipped() throws {
        let markers = ["roadmap", "planned", "not in the app"]
        let offenders = try mentionsWithoutMarker("Ableton Link", markers: markers,
                                                  back: 240, forward: 200)
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) mention(s) of Ableton Link are not marked as unshipped: \
            \(offenders.prefix(3).joined(separator: " | ")). Nothing in `Sources/` imports \
            LinkKit and `Package.swift` links nothing; Link is a roadmap item (#111).
            """)
    }

    /// Motion is a STRUCK word (CLAUDE.md, 2026-07-31): `ModSource.motion.hasProducer` is hard
    /// `false`, all six `BioSampleFrame` construction sites write `motionEnergy: 0`, the last
    /// CoreMotion provider went in the 2026-06-19 cleanup, and `/echoelmusic/bio/motion` is
    /// deliberately not sent (#215 — "a constant 0 is indistinguishable from a still
    /// performer"). The press page nevertheless said "your heartbeat, breath and motion compose
    /// live".
    ///
    /// ⛔ A BARE `motion` SCAN IS THE #364 TRAP AND I MEASURED IT BEFORE WRITING THIS. The token
    /// appears across the scanned pages exactly 28 times and almost every one is legitimate:
    /// "reduced-motion support" and `prefers-reduced-motion` (accessibility — required copy),
    /// "Legibility & motion safety", "filter motion", "chord motion", "your pulse drives
    /// motion" (all MUSICAL motion), and "head motion" on the explicitly-labelled ideas page.
    /// A keyword guard would go red on the accessibility statement — the site being at its most
    /// correct.
    ///
    /// So the rule is the LIST FORM, not the token: motion adjacent to `and` / `&` / `,` with
    /// another body signal within 60 characters on the joining side. That is precisely the shape
    /// of the false claim and none of the legitimate uses can reach it — "drives motion" and
    /// "filter motion" have no conjunction, and "Legibility & motion safety" has the conjunction
    /// but no bio word in front of it. Measured, not assumed: zero hits on the current tree,
    /// THREE on the tree this commit repaired — the press headline, the `bioFrames` payload row,
    /// and the `bioEvents` onset row.
    ///
    /// ⚠️ BOTH DIRECTIONS, AND `bio` INCLUDES HRV AND COHERENCE — because the first version had
    /// each gap and a reviewer walked straight through them. It only matched a conjunction
    /// BEFORE motion, so "your motion, heartbeat and breath" — the mirror image of the press
    /// sentence just repaired — was invisible; and `bio` listed only heart/breath/pulse, so
    /// "HRV, coherence and motion" would have passed. That second one is not hypothetical: it is
    /// the vocabulary of the `architecture.html` `bioFrames` row this commit fixed, and the ONLY
    /// reason that row was caught is that "breath rate, breath phase" happened to fall inside the
    /// 60-character window. Reword it without the word "breath" and the old guard went blind.
    /// Widening cost nothing measurable — still zero hits on the current tree.
    ///
    /// ⚠️ WHAT THIS STILL CANNOT DO, and one case is in the tree it just guarded. It cannot judge
    /// a claim that stands alone rather than joining a list: `architecture.html` also described a
    /// "motion peak (hysteresis 0.6/0.3)" detector with no conjunction anywhere near it, so this
    /// scan is blind to it and it was corrected by hand in the same commit. The list form is
    /// guarded because it is the shape the site produced three times unprompted — motion reads as
    /// a natural fourth item after heart, breath and coherence.
    ///
    /// ⚠️ THE ROW THIS NOTE USED TO WARN ABOUT IS GONE (#755), and the warning is kept because
    /// its SHAPE will come back. `overview.html` carried `Heart rate | Vibrato · filter motion ·
    /// intensity` — "Heart rate" 44 characters before `motion`, inside the precondition window,
    /// green only because the separator was `&middot;` and not a comma. #755 rewrote that row
    /// (heart rate drives vibrato and brightness; the filter belongs to coherence), so the words
    /// "filter motion" no longer occur anywhere under `docs/`. The rule stands: if a future row
    /// puts a comma there, THIS GUARD is wrong and the site is right — narrow the rule, do not
    /// edit the row.
    func testMotionIsNotListedAsABodySignalTheAppSenses() throws {
        XCTAssertFalse(ModSource.motion.hasProducer, """
            `ModSource.motion.hasProducer` is now true — something measures motion again. \
            This test asserts the site does NOT claim motion as an input; if that became true, \
            update the copy FIRST and then invert this guard, in the same commit.
            """)

        let bio = ["breath", "heartbeat", "heart rate", "pulse", "hrv", "coherence"]
        // `trailing` = a conjunction BEFORE motion ("breath and motion"); the bio word must then
        // precede the match. `leading` = a conjunction AFTER motion ("motion, heartbeat"); the
        // bio word must then FOLLOW it. Two patterns rather than one because the side the window
        // is taken from is what differs, and folding that into a single regex would hide it.
        guard let trailing = try? NSRegularExpression(pattern: "(?:and|&amp;|,)\\s+motion\\b",
                                                      options: [.caseInsensitive]),
              let leading = try? NSRegularExpression(pattern: "\\bmotion\\s*(?:,|and\\b|&amp;)",
                                                     options: [.caseInsensitive]) else {
            return XCTFail("a conjunction pattern did not compile — the scan checked nothing")
        }

        var offenders: [String] = []
        for page in try pages() {
            let html = page.html
            let ns = html as NSString
            let whole = NSRange(location: 0, length: ns.length)

            func record(_ range: NSRange) {
                let lo = max(0, range.location - 90)
                let hi = min(ns.length, range.location + range.length + 90)
                offenders.append("\(page.name): …"
                    + ns.substring(with: NSRange(location: lo, length: hi - lo)) + "…")
            }

            for m in trailing.matches(in: html, range: whole) {
                let lo = max(0, m.range.location - 60)
                let preceding = ns.substring(
                    with: NSRange(location: lo, length: m.range.location - lo)).lowercased()
                if bio.contains(where: { preceding.contains($0) }) { record(m.range) }
            }
            for m in leading.matches(in: html, range: whole) {
                let start = m.range.location + m.range.length
                let following = ns.substring(
                    with: NSRange(location: start,
                                  length: min(60, ns.length - start))).lowercased()
                if bio.contains(where: { following.contains($0) }) { record(m.range) }
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) place(s) list motion alongside another body signal: \
            \(offenders.prefix(3).joined(separator: " | ")). Nothing measures motion — \
            `hasProducer` is false and every `BioSampleFrame` writes `motionEnergy: 0`. Name \
            the three real ones (heart, breath, coherence) or say the field is always 0.
            """)
    }

    /// The three bio channels that have NO producer must not be presented as mappings.
    ///
    /// ⛔ WHY THIS EXISTS, AND WHY IT IS A WEBSITE TEST. #496 measured that `breathDepth`,
    /// `lfHf` and `coherenceTrend` are pinned literals at BOTH `PolyBioParams`/`BioParams`
    /// construction sites, and three guards now forbid naming them in the app's own panel copy
    /// (`TheAlwaysOnBioPathIsNamedTests`, `ADropoutSaysWhichHalfLetGoTests`,
    /// `TheBioPanelRowsSayWhoseBodyTests`). All three scan **Swift**. The website was never in
    /// that scan, so `overview.html` kept shipping `Breath depth | Noise level` and
    /// `LF/HF ratio | Spectral tilt` as live mappings — on the page a visitor reads BEFORE
    /// `architecture.html`, which had said "no audible mapping today" the whole time. A cleanup
    /// that fixes the app copy and not the site fixes the quieter half.
    ///
    /// ⚠️ IT IS SCOPED TO ONE SECTION ON PURPOSE, and the alternative was measured first. A
    /// tree-wide ban on the WORDS would go red on honest copy: `faq.html` says "HRV, heart rate,
    /// breath &amp; LF/HF analysis", and that is TRUE — `HRVCoherence` really computes the ratio
    /// (Welch + Lomb-Scargle). What is false is only the MAPPING claim, and the mapping claim
    /// lives in exactly one place: the `<section id="bio">` table. Analysed ≠ mapped.
    ///
    /// ⚠️ AND IT MUST STAY POSSIBLE TO NAME THEM HONESTLY (#364). The corrected table names both
    /// surviving channels in a "Not mapped yet" row; a needle-ban on "breath depth" would have
    /// forbidden the very sentence that repairs the page. So claim 1 anchors on the QUALIFIER
    /// and claim 2 bans only the three dead TARGET names, which have no honest use while their
    /// sources are pinned.
    func testTheProducerlessBioChannelsAreNotSoldAsMappings() throws {
        let pages = try self.pages()
        guard let overview = pages.first(where: { $0.name == "overview.html" })?.html else {
            return XCTFail("docs/overview.html is missing — the Bio-Mappings table lives there")
        }
        guard let start = overview.range(of: "<section id=\"bio\">"),
              let end = overview.range(of: "</section>", range: start.upperBound..<overview.endIndex)
        else {
            return XCTFail("""
                `<section id="bio">` no longer exists in docs/overview.html, so this guard \
                checked nothing (#454: a missing ANCHOR fails, it does not skip). If the \
                Bio-Mappings table moved, point this test at its new home in the same commit.
                """)
        }
        let section = String(overview[start.lowerBound..<end.upperBound]).lowercased()

        XCTAssertTrue(section.contains("drive neither sound nor picture today"), """
            The Bio-Mappings table lost its honesty qualifier. Breath depth, LF/HF and \
            coherence trend are pinned to literals at both bio construction sites \
            (`breathDepth: 0.5`, `lfHf: 0.5`, `coherenceTrend: 0`), so a table that lists \
            any of them without saying they drive nothing is claiming a mapping that does \
            not exist. Re-derive from `docs/architecture.html`, which has said the same in \
            more detail since before #755, and keep ONE wording.
            """)

        for dead in ["spectral tilt", "shape morphing", "color palette"] {
            XCTAssertFalse(section.contains(dead), """
                The Bio-Mappings table names "\(dead)" again. Measured: LF/HF is not read \
                in `applyBioReactive`'s body at all, the coherence-trend spectral morph can \
                never leave its deadband while `coherenceTrend` is 0, and HRV drives pattern \
                COMPLEXITY while COHERENCE drives hue — the palette row had them swapped. If \
                a real producer appears, wire it, then change this line and the table \
                together.
                """)
        }
    }

    /// The accessibility page's SHIPPING list must describe features that exist.
    ///
    /// ⛔ WHAT IT CAUGHT (#758). `accessibility.html` presented five tiles under "what the app
    /// does today". Measured against the tree: "Voice Control — navigate and create using only
    /// your voice" had **zero** implementation (no `SFSpeech`, no speech recogniser, no voice
    /// commands, and `accessibilityCustomAction` occurs nowhere in `Sources/`), while the SAME
    /// PAGE listed "Hands-Free — Voice + switch nav" in its "(planned)" block. One page said a
    /// capability both ships and is coming. "VoiceOver … for all interactive elements"
    /// contradicted the same page's "primary controls" — twice — and the App Store text.
    /// "High Contrast — enhanced visibility mode" implied a setting; there is no contrast
    /// toggle, the interface is high-contrast by design. "Haptic Feedback — tactile responses
    /// for key interactions" was wrong in KIND: `hapticsRow` ("Haptic beat (feel)") sits in
    /// `tempoToolsPanel` and plays a quarter-note pulse — it follows the music, not taps.
    ///
    /// ⚠️ AN ACCESSIBILITY OVERCLAIM IS NOT A MARKETING QUIBBLE. A blind user choosing this app
    /// on "full screen reader support for all interactive elements" and "create using only your
    /// voice" is misled into a purchase decision about whether the app is usable at all. That is
    /// why this guard exists on the accessibility page specifically and not only on the store
    /// copy.
    ///
    /// ⚠️ SCOPED TO THE SHIPPING SECTION, and the scoping was measured before it was written.
    /// The "(planned)" block further down legitimately says "Voice + switch nav"; a page-wide
    /// needle would go red on honest roadmap copy — the #364 trap. The window runs from the
    /// `Accessibility Features` heading to the next `</section>`.
    func testTheAccessibilityPageShipsWhatItLists() throws {
        guard let page = try pages().first(where: { $0.name == "accessibility.html" })?.html else {
            return XCTFail("docs/accessibility.html is missing — this guard checked nothing")
        }
        guard let start = page.range(of: "<h2>Accessibility Features</h2>"),
              let end = page.range(of: "</section>", range: start.upperBound..<page.endIndex)
        else {
            return XCTFail("""
                The `Accessibility Features` heading is gone from docs/accessibility.html, so \
                the shipping list could not be located (#454: a missing ANCHOR fails, it does \
                not skip). If that section was renamed or moved, point this test at it in the \
                same commit.
                """)
        }
        let shipping = String(page[start.lowerBound..<end.upperBound]).lowercased()

        for claim in ["voice control", "using only your voice", "hands-free"] {
            XCTAssertFalse(shipping.contains(claim), """
                The shipping accessibility list claims "\(claim)". Measured: `Sources/` contains \
                no speech recogniser, no voice-command handling and not one \
                `accessibilityCustomAction`. The same page already lists voice navigation under \
                "(planned)", where it belongs. If someone builds it, wire it first, then move \
                the tile up and change this test in the same commit.
                """)
        }

        XCTAssertFalse(shipping.contains("all interactive elements"), """
            The shipping list claims VoiceOver labels on ALL interactive elements. The same \
            page says "primary controls" twice — in the hero badge and in the iPhone platform \
            card — and so does the App Store description. Two spellings of one decision (#416), \
            and the optimistic one is the outlier. The guards that exist cover a SUBSET \
            (`EveryIconOnlyControlSpeaksTests`, `TheStatefulControlsSpeakTheirStateTests`); \
            claim the subset.
            """)
    }
}
