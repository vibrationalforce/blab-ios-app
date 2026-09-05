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
    private func contraindicationDetail() -> String {
        let text = source(Self.learn)
        guard let entry = text.range(of: "id: \"safety.contraindications\""),
              let detail = text.range(of: "detail:", range: entry.upperBound..<text.endIndex),
              let close = text.range(of: "\n            ),", range: detail.upperBound..<text.endIndex)
        else {
            XCTFail("ANCHOR MISSING: the `safety.contraindications` detail — re-derive this guard.")
            return ""
        }
        let body = String(text[detail.upperBound..<close.lowerBound])
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
}
