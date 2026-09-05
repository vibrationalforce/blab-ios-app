import XCTest
@testable import Echoelmusic

/// #994 — the safety card stops promising a freeze that does not happen.
///
/// WHY IT EXISTS. `safety.contraindications` is the entry a photosensitive user reads before
/// ticking "I understand", and it said visuals "freeze entirely with Reduce Motion on". Measured
/// on the tree that shipped it, that was false on every surface but one:
///
///   · the pulse tile holds only its per-beat term under Reduce Motion and leaves
///     `0.35 * masterLevel` live on an unpaused 20 Hz `TimelineView`;
///   · the lamp tile drops its animation timer, and its own comment concedes the music-driven
///     hue still re-renders on every published `MusicalFrame`;
///   · `Sources/Echoelmusic/Sync` contains no `reduceMotion` at all, so NO connected fixture
///     honours it;
///   · `MetalBioView` keeps an eased music swell — well under 3 Hz, but not frozen.
///
/// The 3 Hz cap itself is TRUE and stays stated: `FlashGuard` holds it everywhere, and the
/// fixtures are additionally slewed to about 1.2 Hz by `ArtNetSender.applySlewedColour`. This
/// slice narrows an overclaim; it does not weaken a real protection.
///
/// ⚠️ SCOPE. Copy only. The behavioural repair — slewing the two `masterLevel` terms through
/// `FlashGuard.limitedLuminance` — changes how the chrome looks and needs a device look, so it
/// is deliberately a separate slice. Claim 4 goes red the day someone does it, and says to move
/// this copy in the same commit.
///
/// The word-level requirements of the same entry (driving · machinery · alcohol · drugs ·
/// provider · "3 flashes per second" · "not part of a treatment") are pinned once in
/// `LearnLibraryTests.testContraindicationsEntryCarriesEveryMandatedWarning` and are NOT restated here
/// (#416) — a second copy of one list is how two tests drift about different sentences.
final class TheSafetyCopyDescribesWhatReduceMotionDoesTests: XCTestCase {

    private static let learn = "Sources/Echoelmusic/Studio/LearnLibrary.swift"
    private static let header = "Sources/Echoelmusic/Studio/HeaderMonitors.swift"
    private static let syncDir = "Sources/Echoelmusic/Sync"

    private func repoRoot() -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        return dir
    }

    private func source(_ relative: String) -> String {
        let url = repoRoot().appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read — a missing anchor is a "
                    + "finding, not a pass.")
            return ""
        }
        return text
    }

    /// The runtime value of the `detail:` argument, rebuilt from its concatenated literals —
    /// the source text alone never contains a phrase that straddles a `+`, so a plain
    /// `contains` on the file would report a MISS for wording that is actually there.
    private func contraindicationDetail() -> String { detail(ofEntry: "safety.contraindications") }

    /// Generalised in #1018. The extractor was written for one entry and the defect it guards
    /// turned out to live in two OTHERS — so the shape that finds it again is per-entry, not
    /// per-card.
    private func detail(ofEntry id: String) -> String {
        let text = source(Self.learn)
        guard let entry = text.range(of: "id: \"\(id)\""),
              let detail = text.range(of: "detail:", range: entry.upperBound..<text.endIndex),
              let close = text.range(of: "\n            ),", range: detail.upperBound..<text.endIndex)
        else {
            XCTFail("ANCHOR MISSING: the `\(id)` detail — re-derive this guard.")
            return ""
        }
        // ⛔ COMMENT LINES ARE DROPPED BEFORE THE QUOTE SCAN, and #1018 is why. The retraction
        // notes this repo writes QUOTE the wording they retract, and they sit INSIDE the
        // `detail:` region — so a scanner that only toggles on `"` returns the struck sentence
        // as though it were live copy, and a needle for that sentence matches its own
        // retraction (#491). The same trap #1014 hit one file away. A line-wise rule is enough
        // here and stays honest about its limit: a `//` inside a copy string would be stripped
        // too, so it is checked below that no detail literal contains one.
        let body = text[detail.upperBound..<close.lowerBound]
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        var out = ""
        var inside = false
        var escaped = false
        for ch in body {
            if escaped { if inside { out.append(ch) }; escaped = false; continue }
            if ch == "\\" { escaped = true; if inside { } ; continue }
            if ch == "\"" { inside.toggle(); continue }
            if inside { out.append(ch) }
        }
        return out
    }

    // 1 — the false promise is gone. This is the finding.
    func testTheCardNoLongerPromisesAFreeze() {
        let text = source(Self.learn)
        XCTAssertFalse(text.contains("freeze entirely"), """
            The safety card promises again that visuals "freeze entirely" with Reduce Motion on. \
            They do not: the header monitors keep a live `masterLevel` term, no fixture in \
            Sources/Echoelmusic/Sync honours Reduce Motion at all, and MetalBioView keeps an \
            eased music swell. This is the one screen a photosensitive user consents against — \
            a protection they rely on and do not get is worse than no sentence.
            """)
    }

    // 2 — it says where motion CONTINUES. Deleting the false half without replacing it would
    // leave the reader believing Reduce Motion covers everything by omission.
    func testTheCardNamesWhatKeepsMoving() {
        let detail = contraindicationDetail()
        XCTAssertTrue(detail.contains("rate-limited rather than frozen"), """
            The card no longer says that the header monitors and connected lamps keep following \
            the music. Removing the false claim is only half the repair — silence about the \
            surfaces that DO keep moving reads as "Reduce Motion covers everything".
            """)
    }

    // 3 — it names the instruction that actually works on a rig. Reduce Motion is an iOS
    // accessibility setting the lamps never see; Blackout is a control this app ships.
    func testTheCardNamesTheControlThatWorksOnARig() {
        let detail = contraindicationDetail()
        XCTAssertTrue(detail.contains("Blackout"), """
            The card no longer names Blackout. For a user with fixtures connected it is the \
            only instruction in the app that actually stops them — `ArtNetSender.blackout` and \
            `SACNSender.blackout`, driven from Routing. An advice line that names only an iOS \
            setting the fixtures cannot read is advice that fails exactly where the risk is.
            """)
    }

    // 4 — COUNTERWEIGHT (#364). This does NOT forbid teaching the fixtures Reduce Motion —
    // it goes red the day someone does, because the sentence above would then understate the
    // protection. Move the copy in the same commit (#456).
    func testNoFixtureHonoursReduceMotionYet() throws {
        let dir = repoRoot().appendingPathComponent(Self.syncDir)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertFalse(files.isEmpty, "ANCHOR MISSING: \(Self.syncDir) is empty — re-derive this guard.")
        var honouring: [String] = []
        for name in files where name.hasSuffix(".swift") {
            let text = (try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)) ?? ""
            if text.contains("reduceMotion") { honouring.append(name) }
        }
        XCTAssertTrue(honouring.isEmpty, """
            \(honouring.joined(separator: ", ")) now mentions Reduce Motion. If a fixture sender \
            genuinely honours it, that is GOOD and this claim should be deleted — but delete it \
            in the same commit that rewrites the `safety.contraindications` sentence, which \
            currently tells the user connected lamps keep following the music.
            """)
    }

    // 5 — COUNTERWEIGHT: the two header terms this copy describes are still unslewed. If the
    // registered follow-up lands, the card's "rate-limited rather than frozen" becomes an
    // understatement for the monitors and must be re-worded with it.
    func testTheHeaderLevelTermsAreStillUnslewed() {
        let text = source(Self.header)
        XCTAssertTrue(text.contains("0.35 + 0.30 * pulse + 0.35 * level"), """
            The pulse tile's energy mix changed. The safety card describes these terms as \
            following the music rate-limited rather than frozen; if they are now slewed through \
            FlashGuard, say so on the card in the same commit.
            """)
        XCTAssertTrue(text.contains("let dim: Double = 0.3 + 0.7 * (mf?.masterLevel ?? 0)"), """
            The lamp tile's dimmer term changed. Same reason as above — the card's wording is \
            derived from these two expressions, so they move together.
            """)
    }

    // MARK: - The same promise, in the same file, in different words (#1018)

    /// ⭐ WHY CLAIM 1 DID NOT CATCH THIS, and the lesson is about needles, not about copy.
    /// Claim 1 forbids the literal phrase `freeze entirely`. `guide.see` said "the picture
    /// **holds still entirely**" and `guide.access` said "Reduce Motion **freezes the visual**"
    /// — the same promise, neither spelling matchable. #706 recorded exactly this shape once
    /// already: a needle that matches one wording misses the wording people actually write.
    /// So this claim asks the QUESTION rather than banning a STRING — does any Learn entry tell
    /// the reader that Reduce Motion stops the visuals outright?
    ///
    /// ⚠️ The two entries are checked through `detail(ofEntry:)`, which now drops comment lines
    /// before rebuilding the literal — without that, the ⛔ notes added beside these two
    /// sentences (which quote the struck wording, as this repo's retractions do) would be read
    /// as live copy and this claim would match its own retraction (#491).
    func testNoGuideEntryPromisesTheVisualsStopOutright() {
        // Each pair is (a phrase that says motion STOPS, a phrase that would make it honest by
        // naming what keeps moving). A total-stop phrase is only a defect when it stands ALONE.
        let stopPhrases = ["holds still entirely", "freezes the visual", "freeze entirely",
                           "stops entirely", "stops all motion", "nothing moves"]
        for id in ["guide.see", "guide.access"] {
            let copy = detail(ofEntry: id)
            XCTAssertFalse(copy.isEmpty, "ANCHOR MISSING: \(id) has no detail text.")
            let offenders = stopPhrases.filter { copy.lowercased().contains($0) }
            XCTAssertTrue(offenders.isEmpty, """
                Learn entry "\(id)" promises again that Reduce Motion stops the visuals \
                outright (\(offenders.joined(separator: ", "))). It does not, and the ⛔ block \
                on `safety.contraindications` carries the measurement: the header monitors keep \
                a live masterLevel term, nothing under Sources/Echoelmusic/Sync honours Reduce \
                Motion at all, and MetalBioView keeps an eased music swell. #994 removed this \
                promise from the SAFETY card and left it standing here in other words — which \
                is the whole reason this claim exists. Say what stops and what keeps moving.
                """)
        }
    }

    /// The other half of the repair, stated positively so deleting the false clause without
    /// replacing it cannot pass: each of the two entries must name what KEEPS moving, or the
    /// control that actually cuts it. Silence would leave the reader believing by omission —
    /// the same reasoning as claim 2 for the safety card.
    func testTheTwoGuideEntriesSayWhatSurvivesReduceMotion() {
        let honest = ["keep following the music", "keeps following the music", "Blackout"]
        for id in ["guide.see", "guide.access"] {
            let copy = detail(ofEntry: id)
            XCTAssertTrue(honest.contains(where: { copy.contains($0) }), """
                Learn entry "\(id)" no longer names anything that survives Reduce Motion. \
                Removing the false promise is half the repair; without the second half the \
                reader concludes by omission that Reduce Motion covers everything, which is the \
                belief the whole card exists to correct.
                """)
        }
    }

    /// The extractor drops `//` lines, so a copy string that CONTAINED `//` would be silently
    /// truncated and every needle above would read a shorter sentence than the user sees. No
    /// detail literal has one today; this pins that, so the shortcut stays honest.
    func testNoLearnCopyContainsACommentMarker() {
        for id in ["guide.see", "guide.access", "safety.contraindications"] {
            XCTAssertFalse(detail(ofEntry: id).contains("//"), """
                Learn entry "\(id)" now contains "//" inside its copy. `detail(ofEntry:)` drops \
                lines beginning with that marker before rebuilding the literal, so part of this \
                sentence is invisible to every claim in this file. Either reword the copy or \
                teach the extractor to track quotes across the line.
                """)
        }
    }
}
