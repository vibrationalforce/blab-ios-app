//  TheStoreTextClaimsOnlyWhatShipsTests.swift
//
//  THE FOURTH SURFACE. A user-visible claim in this repo has four homes — the app's own copy
//  (Swift), `docs/**`, `ContentPipeline/CLAIMS.md`, and `fastlane/metadata`. #496 struck three
//  producerless bio channels (`breathDepth`, `lfHf`, `coherenceTrend`) and left three guards
//  behind it; all three read Swift. #755 found the same claim still shipping on the WEBSITE and
//  guarded that. This file is the fourth home, and it is the one where being wrong is not a
//  stale sentence but an App Store 2.3 rejection — the failure #184 already paid for once by
//  removing twelve false claims from this very text.
//
//  ⛔ WHAT IT CAUGHT ON ITS FIRST RUN (#757). `fastlane/metadata/en-US/description.txt` read
//  "Breath shapes the amplitude envelope and filter movement". The swell half is real
//  (`breathPhase` → `amplitude`, every profile). The filter half rides `breathDepth`, whose two
//  `BioParams` construction sites both pass the literal `0.5`, so the factor is exactly 1.0 on
//  every frame the shipped app can produce. `applyBioReactive` says so at that line in words:
//  *"must not be claimed as live in any user-facing copy."*
//
//  ⭐ AND THE GERMAN LOCALE OF THE SAME LISTING WAS ALREADY HONEST — "Atem formt die
//  Hüllkurve", no filter. Two locales of ONE store listing disagreed, and the wrong one was
//  English, the primary market. That is the sharpest form of the multi-surface lesson: the
//  surfaces are not only different FILES, they are different LOCALES of the same file.
//
//  ⚠️ THE RULE IS PROXIMITY, NOT A WORD-BAN (#364). "Filter" on its own is a TRUE claim here —
//  coherence really does drive `filterCutoff`, and the audited in-app truth table
//  (`AlwaysOnBioChannel.shapedParameters`) says so. Banning the word would forbid honest copy.
//  What is false is specifically BREATH attached to a FILTER, so that is what is measured: the
//  two words inside one short window, in either language.
//
//  ⚠️ WHAT IT CANNOT DO. It reads the text that is COMMITTED, not what is live on App Store
//  Connect — a claim edited in the web UI never passes through this file. And it judges three
//  named channels, not truthfulness in general; a fresh false claim about something else walks
//  straight past it.
import XCTest

final class TheStoreTextClaimsOnlyWhatShipsTests: XCTestCase {

    /// Every locale's long-form and short-form store copy, by path.
    ///
    /// ⚠️ ANCHOR, NOT A CONVENIENCE (#454). A missing or empty file FAILS rather than yielding
    /// an empty set that every assertion below would pass vacuously. The whole point of this
    /// file is that nobody was reading this text; a guard that silently reads nothing would be
    /// the same defect wearing a green tick.
    private func storeCopy() throws -> [(path: String, text: String)] {
        let root = try repoRoot()
        var out: [(String, String)] = []
        for locale in ["en-US", "de-DE"] {
            for leaf in ["description.txt", "promotional_text.txt", "subtitle.txt"] {
                let rel = "fastlane/metadata/\(locale)/\(leaf)"
                let url = root.appendingPathComponent(rel)
                guard let text = try? String(contentsOf: url, encoding: .utf8),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    XCTFail("""
                        \(rel) is missing or empty, so this guard checked nothing. The App Store \
                        text is the surface where a false capability claim is a 2.3 rejection; \
                        if the metadata layout moved, point this test at its new home in the \
                        same commit.
                        """)
                    continue
                }
                out.append((rel, text))
            }
        }
        XCTAssertFalse(out.isEmpty, "no store copy was read at all — the walk is broken")
        return out
    }

    /// Breath must not be sold as driving a filter, in any locale.
    ///
    /// The window is 80 characters because these are bullet lines, not paragraphs: the English
    /// offender put the two words 34 apart on one line. A window that spans paragraphs would
    /// pair an honest coherence→filter bullet with an honest breath→amplitude bullet and fail
    /// on correct copy.
    func testBreathIsNotSoldAsDrivingAFilter() throws {
        let breath = ["breath", "atem"]
        let filter = ["filter"]
        var offenders: [String] = []
        for file in try storeCopy() {
            let flat = file.text.lowercased()
            for b in breath {
                var search = flat.startIndex..<flat.endIndex
                while let hit = flat.range(of: b, range: search) {
                    let lo = flat.index(hit.lowerBound, offsetBy: -80, limitedBy: flat.startIndex)
                        ?? flat.startIndex
                    let hi = flat.index(hit.upperBound, offsetBy: 80, limitedBy: flat.endIndex)
                        ?? flat.endIndex
                    let window = String(flat[lo..<hi])
                    if filter.contains(where: { window.contains($0) }) {
                        offenders.append("\(file.path): …\(window)…")
                    }
                    search = hit.upperBound..<flat.endIndex
                }
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) place(s) in the store text put breath next to a filter: \
            \(offenders.prefix(2).joined(separator: " | ")).

            Measured: the filter half of that claim rides `breathDepth`, and BOTH `BioParams` \
            construction sites pass the literal `0.5` — the factor is exactly 1.0 on every \
            frame the shipped app can produce. `applyBioReactive` says at that line that it \
            "must not be claimed as live in any user-facing copy". Breath drives the AMPLITUDE \
            swell; the filter cutoff belongs to COHERENCE. If a real producer for breath depth \
            appears, wire it, then change the copy and this test together.
            """)
    }

    /// The three producerless channels must not be named as drivers anywhere in the store text.
    ///
    /// ⚠️ Unlike the website guard (#755), there is no "not mapped yet" row to protect here —
    /// store copy sells what ships, it does not carry a roadmap table. So the channel NAMES are
    /// banned outright in this surface, and that is deliberate rather than an oversight: if the
    /// text ever wants to say "breath depth is coming", it should say it in the release notes,
    /// which this guard does not read.
    func testTheProducerlessChannelsAreNotNamedAsDrivers() throws {
        let dead = ["breath depth", "atemtiefe", "lf/hf", "lf-hf", "coherence trend",
                    "kohärenz-trend", "spectral tilt", "spektrale neigung"]
        var offenders: [String] = []
        for file in try storeCopy() {
            let flat = file.text.lowercased()
            for term in dead where flat.contains(term) {
                offenders.append("\(file.path): \(term)")
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            The store text names a bio channel that drives nothing: \
            \(offenders.joined(separator: ", ")). All three are pinned to literals at both \
            `BioParams`/`PolyBioParams` construction sites (`breathDepth: 0.5`, `lfHf: 0.5`, \
            `coherenceTrend: 0`). The audited in-app truth table is \
            `AlwaysOnBioChannel.shapedParameters`: coherence → filter cutoff · brightness · \
            harmonicity · noise; HRV → brightness; heart rate → vibrato · brightness; \
            breath phase → amplitude. Claim from that list.
            """)
    }

    // MARK: - file access

    private func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(atPath:
                dir.appendingPathComponent("CLAUDE.md").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        throw NSError(domain: "TheStoreTextClaimsOnlyWhatShips", code: 1, userInfo: [
            NSLocalizedDescriptionKey:
                "could not find the repo root from \(#filePath) — the guard read nothing"
        ])
    }
}
