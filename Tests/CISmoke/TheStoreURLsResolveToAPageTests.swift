// TheStoreURLsResolveToAPageTests.swift
// Echoel — #772. The App Store privacy URL is served by a file no guard could see.
//
// WHAT THIS GUARDS. `fastlane/metadata/<locale>/privacy_url.txt` publishes
// `https://echoelmusic.com/privacy` — **without `.html`**. Nothing in this repo checked that the
// path resolves to anything. Six such URLs are published across two locales (`marketing_url`,
// `privacy_url`, `support_url` × en-US, de-DE); all six resolve today.
//
// ⛔ AND MY FIRST VERSION OF THIS PARAGRAPH SAID `/privacy` IS SERVED BY `docs/privacy/index.html`,
// A REDIRECT STUB — WHICH IS AN OVER-CLAIM, caught by driving the mutation instead of predicting
// it. Deleting that stub changes nothing: GitHub Pages tries `privacy.html` BEFORE
// `privacy/index.html`, and `docs/privacy.html` is real content. The route has two files behind
// it, not one, and the stub is belt-and-braces. **I had written the mutation's expected result
// into the header before running it** — the same defect as #765's claim 4, one cycle apart, and
// it is recorded here rather than quietly deleted because the flattering direction is the easy
// one to slip into (#433).
//
// What survives, and is the reason the file is worth its bytes: the route is unchecked, and the
// way it actually breaks is `docs/privacy.html` being renamed while the stub stays. Resolution
// then falls through to the stub, the stub forwards to a page that is gone, and the visitor gets
// a 404 one hop after a directory listing that looked perfectly healthy. That is claim 3, and it
// is the one mutation of the four that no existing guard in this repo could have caught.
//
// ⛔ AND THE FILE THAT SHOULD HAVE CHECKED IT CANNOT, BY ITS OWN DESIGN.
// `WebsitePagesAreFindableAndHonestTests.pages()` is a NON-RECURSIVE listing of `docs/*.html` —
// the header says so in as many words. Six HTML files live one directory down and are therefore
// invisible to every claim in that file: the three redirect stubs and the three
// `docs/screenshots/demo-*.html` mockups. Measured before writing this: the three mockups carry
// no capability claim (their only "wav" hits are the word *waveform*), so the honesty scan loses
// nothing by not seeing them. The redirects are a different matter — they are not copy, they are
// ROUTING, and routing is what an App Store URL depends on. That limit was DECLARED, not hidden,
// and it stayed declared: the #762 lesson is that an honest "not checked" note lives forever
// unless somebody does the measurement that resolves it.
//
// ⚠️ WHY THIS IS NOT ALARMISM. Everything resolves right now, and this file says so rather than
// dressing a clean measurement as a catch (#464). What it buys is the FUTURE red, and the
// failure it prevents is unusually expensive for how quiet it is: rename `docs/privacy.html` and
// `https://echoelmusic.com/privacy` starts serving a redirect to a 404. Apple requires a working
// privacy URL — a dead one is a review rejection, and the page is a legal obligation
// independently of review. Nothing in the repo would have made a sound: the sitemap lists
// `privacy.html` (not `/privacy`), the website guard cannot see the stub, and the store guard's
// leaf list is description/promo/subtitle/keywords/release-notes — no `*_url.txt`.
//
// ⚠️ THE ROSTER IS READ FROM DISK (#769). Every `*_url.txt` under `fastlane/metadata/` is
// scanned, in every locale directory, so a seventh URL file or a third locale is covered the day
// it is added rather than the day someone remembers to type it in here. That is the trap #768
// and #769 each closed one level further out; this file starts on the far side of it.
//
// ⚠️ THE LIMIT. FILESYSTEM SCAN, NOT AN HTTP CHECK. It proves a file exists in `docs/` at the
// path the URL names, under GitHub Pages' own resolution rules. It cannot prove the site is
// deployed, that DNS points anywhere, or that Apple can reach it. Those need a browser and are
// named as open rather than implied.
//
// ⚠️ ONE REDIRECT HOP, DELIBERATELY. A stub that forwards to another stub is a configuration
// nobody has, and following an arbitrary chain would need cycle detection for no gain. If a
// second hop ever appears, claim 3 fails with a message that says to extend it — better than a
// scan that silently loops.
//
// ⚠️ HONEST GRADING FOR #772 (parent `8da2c3e`): **ZERO REGRESSIONS, and that is correct.** The
// slice adds no page and changes no URL, so every assertion is green on both trees — the same
// shape as #771 and for the same reason. #367 was still driven against mutated trees; the
// results are in `testEveryPublishedURLResolves`'s doc comment.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheStoreURLsResolveToAPageTests: XCTestCase {

    private struct StoreURLAnchorMissing: Error { let reason: String }

    // MARK: - claim 1 — the roster exists and comes from disk

    func testTheStoreListingPublishesURLs() throws {
        let urls = try publishedURLs()
        XCTAssertFalse(urls.isEmpty, """
            No `*_url.txt` found under `fastlane/metadata/`. This scan found NOTHING rather than \
            nothing wrong (#454). If the store URLs moved — to a Fastfile, to App Store Connect \
            by hand, to another directory — re-anchor this file in the same commit, because the \
            privacy URL stops being checked the moment this list comes back empty.
            """)
    }

    // MARK: - claim 2 — every published path has a file behind it

    /// #367, driven in Python against deliberately mutated trees — the results below are what the
    /// driver PRINTED, not what I expected it to print (see the ⛔ block in the file header):
    ///   · a seventh `*_url.txt` naming `/nonexistent`  → this claim RED for that path
    ///   · `docs/privacy.html` deleted, stub kept       → claim 3 RED, this claim GREEN — the
    ///     split that makes claim 3 worth having, since resolution falls through to the stub
    ///   · `docs/privacy/index.html` deleted            → EVERYTHING GREEN, correctly: Pages
    ///     serves `privacy.html` first, so removing the stub breaks nothing
    ///   · every `*_url.txt` removed                    → claim 1 RED (the anchor, #454)
    func testEveryPublishedURLResolves() throws {
        for (source, url) in try publishedURLs() {
            let path = try pathComponent(of: url, declaredIn: source)
            XCTAssertNotNil(try resolve(path), """
                \(source) publishes "\(url)" to the App Store, and nothing under `docs/` serves \
                that path. GitHub Pages would answer it with a 404.

                Tried, in order: `docs/\(path).html`, `docs/\(path)/index.html`, \
                `docs/\(path)` — and `docs/index.html` for the bare domain. Either restore the \
                page or change the URL file; a store listing that points at a 404 is a review \
                rejection, and for the privacy URL it is a legal exposure too.
                """)
        }
    }

    // MARK: - claim 3 — a redirect must land somewhere

    /// The half `WebsitePagesAreFindableAndHonestTests` cannot do: its `pages()` never sees a
    /// file one directory down, so the stub that actually serves `/privacy` is outside every
    /// claim it makes. A stub pointing at a deleted page looks perfectly healthy on disk.
    func testEveryRedirectLandsOnARealPage() throws {
        for (source, url) in try publishedURLs() {
            let path = try pathComponent(of: url, declaredIn: source)
            guard let file = try resolve(path) else { continue }   // claim 2 owns that failure
            let html = try String(contentsOf: file, encoding: .utf8)
            guard let target = redirectTarget(in: html) else { continue }
            XCTAssertNotNil(try resolve(target), """
                \(source) publishes "\(url)", which is served by \
                `\(file.lastPathComponent)` — a redirect to "/\(target)", and nothing under \
                `docs/` serves THAT.

                This is the silent shape: the stub still exists, so a directory listing looks \
                healthy, and the visitor gets a 404 one hop later. If the target page was \
                renamed, update the stub in the same commit (#456). If a second redirect hop \
                was introduced, extend this scan rather than letting it follow a chain it \
                cannot detect cycles in.
                """)
        }
    }

    // MARK: - claim 4 (COUNTERWEIGHT) — the URLs point at the site this repo publishes

    /// #343. Claims 2 and 3 resolve a URL's PATH against `docs/`. That is only meaningful while
    /// the host is the host `docs/CNAME` serves; a URL moved to another domain would keep
    /// "resolving" against a local file of the same name and the two claims above would go on
    /// passing while proving nothing. Green on both trees, and the point of the file.
    func testThePublishedHostIsTheOneThisRepoServes() throws {
        let cname = try repoRoot().appendingPathComponent("docs/CNAME")
        guard let host = try? String(contentsOf: cname, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty else {
            throw StoreURLAnchorMissing(reason: """
                `docs/CNAME` is missing or empty. It is what makes a path check meaningful — \
                without it, claims 2 and 3 resolve store URLs against a tree that may not be \
                the site at all. Re-anchor in the same commit.
                """)
        }
        for (source, url) in try publishedURLs() {
            XCTAssertTrue(url.contains(host), """
                \(source) publishes "\(url)", but `docs/CNAME` says this repo serves "\(host)".

                Either the site moved and `docs/CNAME` needs to move with it, or the store \
                listing points somewhere this repo does not control — in which case the other \
                claims in this file are checking paths against the wrong tree and are worth \
                nothing until it is settled.
                """)
        }
    }

    // MARK: - reading

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

    /// (`<locale>/<file>`, url) for every `*_url.txt` in every locale directory — read from
    /// disk, never typed here (#769).
    private func publishedURLs() throws -> [(source: String, url: String)] {
        let base = try repoRoot().appendingPathComponent("fastlane/metadata")
        let fm = FileManager.default
        var out: [(String, String)] = []
        for locale in ((try? fm.contentsOfDirectory(atPath: base.path)) ?? []).sorted() {
            let dir = base.appendingPathComponent(locale)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            for leaf in ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
            where leaf.hasSuffix("_url.txt") {
                let text = try String(contentsOf: dir.appendingPathComponent(leaf),
                                      encoding: .utf8)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { out.append(("fastlane/metadata/\(locale)/\(leaf)", text)) }
            }
        }
        return out
    }

    /// "https://host/a/b" → "a/b"; the bare domain → "".
    private func pathComponent(of url: String, declaredIn source: String) throws -> String {
        guard let schemeEnd = url.range(of: "://") else {
            throw StoreURLAnchorMissing(reason: """
                \(source) holds "\(url)", which is not an absolute URL. The store needs one; \
                fix the file rather than loosening this parse.
                """)
        }
        let afterScheme = url[schemeEnd.upperBound...]
        guard let slash = afterScheme.firstIndex(of: "/") else { return "" }
        return String(afterScheme[afterScheme.index(after: slash)...])
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    /// GitHub Pages' own resolution order, in the order it applies them.
    private func resolve(_ path: String) throws -> URL? {
        let docs = try repoRoot().appendingPathComponent("docs")
        let fm = FileManager.default
        if path.isEmpty {
            let index = docs.appendingPathComponent("index.html")
            return fm.fileExists(atPath: index.path) ? index : nil
        }
        for candidate in ["\(path).html", "\(path)/index.html", path] {
            let url = docs.appendingPathComponent(candidate)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                return url
            }
        }
        return nil
    }

    /// The path a redirect stub forwards to, or nil when the page is real content. Reads the
    /// `http-equiv="refresh"` meta because that is the hop a browser takes with JavaScript off —
    /// the `location.replace` beside it is the same destination by construction, and asserting
    /// on the weaker of the two would let a stub disagree with itself unnoticed.
    private func redirectTarget(in html: String) -> String? {
        // #408: `url=` alone is not unique enough to anchor on — a page may carry `og:url` or a
        // query string long before the meta tag. Find the refresh tag FIRST and search only
        // after it, so the scan cannot read some other attribute's value as the destination.
        guard let refresh = html.range(of: "http-equiv=\"refresh\"") else { return nil }
        let afterRefresh = html[refresh.upperBound...]
        guard let urlKey = afterRefresh.range(of: "url=", options: .caseInsensitive) else {
            return nil
        }
        let rest = afterRefresh[urlKey.upperBound...]
        let raw = rest.prefix { $0 != "\"" && $0 != "'" && $0 != ">" && !$0.isWhitespace }
        let trimmed = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? nil : trimmed
    }
}
