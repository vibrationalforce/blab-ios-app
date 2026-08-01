// WeatherIsAMoodRubricTests.swift
// Echoel — das Wetter steht bei den Reglern, die es verstellt.
//
// WHAT THIS GUARDS (#359, Founder 2026-08-01: "Weather könnte auch eine Rubrik mit slidern
// in mood, Sound und Field sein oder?"). Weather in Echoel is not a naming gimmick and the
// chip copy already said so before this change: the fetched condition blends into
// darkness / liveliness / tension in the composer, and into hue / saturation / glow / motion
// in the live visual. It nevertheless lived behind a chip labelled "Session", next to the
// one toggle that really is about naming. A control whose ONLY door is a word that does not
// describe it is unfindable — which is exactly what filed task #59 concluded about this
// feature: "es fehlt die Auffindbarkeit, nicht die Synthese".
//
// So `weatherRow` now sits inside `moodPanel`, among the mood knobs it modulates, and the
// panel it left is titled after the one thing left in it: `placeRow` → "Place". That second
// half also settles filed task #284 — a chip called "Session" that saves no session, sitting
// one chip away from a "Save & Export" panel that does.
//
// ⚠️ WHAT THIS FILE CANNOT SEE, said plainly because a guard that oversells itself is worse
// than none: this is a SOURCE-TEXT scan. It proves `weatherRow` is a child of `moodPanel`'s
// builder and is no longer a child of `sessionPanel`'s. It cannot prove the row RENDERS, that
// the panel opens, or that the founder can find it. That is a device check and it stays open.
//
// ⚠️ WHY BOTH DIRECTIONS ARE ASSERTED. Asserting only "moodPanel contains weatherRow" would
// stay green if a future edit re-added the row to `sessionPanel` as well — two weather
// surfaces writing the same `@AppStorage` keys, which is the `visualVJOverlay` defect (open
// task #270) reproduced on a second feature. The pair "in Mood AND not in Place" is the
// claim; either half alone is not.
//
// No simulator; `Tests/CISmoke` is the blocking bundle. SKIPS rather than passes if the tree
// is not at this file's compile-time path — a green it did not earn is the failure mode this
// whole bundle exists to avoid.

import Foundation
import XCTest
@testable import Echoelmusic

final class WeatherIsAMoodRubricTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }

    private func lines(_ path: String) throws -> [String] {
        let text = try String(contentsOf: try repoRoot().appendingPathComponent(path),
                              encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// The declaration's own lines, from the line that opens it up to (not including) the
    /// line that opens the next one. Deliberately a WINDOW and not a whole-file grep: the
    /// claim here is about which builder a row belongs to, and a file-wide match would be
    /// satisfied by the row existing anywhere at all.
    private func window(_ source: [String],
                        opening: String,
                        closing: [String]) throws -> [String] {
        guard let start = source.firstIndex(where: { $0.contains(opening) }) else {
            throw XCTSkip("declaration '\(opening)' not found — the file was restructured")
        }
        var end = source.count
        var i = start + 1
        while i < source.count {
            if closing.contains(where: { source[i].contains($0) }) {
                end = i
                break
            }
            i += 1
        }
        return Array(source[start..<end])
    }

    /// Comment lines are stripped before matching. This file's own header talks about
    /// `weatherRow` and `sessionPanel`; so does the prose inside those declarations. A guard
    /// that matches its own explanation proves nothing — `ScrubNotifiesOnlyOnRealChangeTests`
    /// paid for that lesson by going red for a comment someone added to a pinned block.
    private func code(_ source: [String]) -> [String] {
        source.filter { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return !t.hasPrefix("//") && !t.isEmpty
        }
    }

    // MARK: - The Mood half

    func testTheMoodPanelCarriesTheWeatherRow() throws {
        let source = try lines(Self.studio)
        let mood = code(try window(source,
                                   opening: "private var moodPanel: some View {",
                                   closing: ["private var ", "// MARK:"]))
        let hits = mood.filter { $0.contains("weatherRow") }
        XCTAssertEqual(hits.count, 1, """
            #359: moodPanel must build `weatherRow` exactly once. Found \(hits.count). \
            Weather blends into darkness/liveliness/tension — it belongs among the knobs it \
            modulates, not behind a chip about session names.
            """)
    }

    func testTheWeatherRowStaysBehindItsFrameworkGuard() throws {
        let source = try lines(Self.studio)
        let mood = code(try window(source,
                                   opening: "private var moodPanel: some View {",
                                   closing: ["private var ", "// MARK:"]))
        guard let at = mood.firstIndex(where: { $0.contains("weatherRow") }) else {
            return XCTFail("no weatherRow in moodPanel — see the sibling test")
        }
        let guardLine = at > 0 ? mood[at - 1] : ""
        XCTAssertTrue(guardLine.contains("#if canImport(WeatherKit)"), """
            #359: the line above `weatherRow` must still be its \
            `#if canImport(WeatherKit) && canImport(CoreLocation)` guard, because \
            `weatherRow` itself is declared inside that same guard. Found: '\(guardLine)'. \
            Without it the Mood panel stops compiling wherever WeatherKit is absent.
            """)
    }

    func testTheCaptionStaysTheLastChildOfTheMoodPanel() throws {
        let source = try lines(Self.studio)
        let mood = code(try window(source,
                                   opening: "private var moodPanel: some View {",
                                   closing: ["private var ", "// MARK:"]))
        let weatherAt = mood.firstIndex { $0.contains("weatherRow") }
        let captionAt = mood.firstIndex { $0.contains("Friendly ↔ scary (tension)") }
        guard let weatherAt, let captionAt else {
            return XCTFail("moodPanel lost either `weatherRow` or its explanatory caption")
        }
        XCTAssertLessThan(weatherAt, captionAt, """
            #359: the caption is the panel's closing sentence and the house rule keeps \
            headers and captions OUTSIDE the reflow grid, i.e. last. `weatherRow` was \
            inserted after it.
            """)
    }

    // MARK: - The Place half (this is also filed task #284)

    func testThePlacePanelNoLongerCarriesWeather() throws {
        let source = try lines(Self.studio)
        let place = code(try window(source,
                                    opening: "private var sessionPanel: some View {",
                                    closing: ["private var ", "// MARK:"]))
        let hits = place.filter { $0.contains("weatherRow") }
        XCTAssertTrue(hits.isEmpty, """
            #359: `weatherRow` is back in the Place panel as well. Two surfaces writing the \
            same @AppStorage weather keys is the `visualVJOverlay` defect (open task #270) \
            on a second feature — the row has ONE home, and it is moodPanel.
            """)
    }

    func testThePlaceChipSaysPlace() throws {
        let source = try lines(Self.studio)
        let labels = code(try window(source,
                                     opening: "var label: String {",
                                     closing: ["var fullName: String {"]))
        guard let line = labels.first(where: { $0.contains("case .session:") }) else {
            return XCTFail("the `.session` chip lost its label case")
        }
        XCTAssertTrue(line.contains("\"Place\""), """
            #284/#359: the chip must read "Place". Found: '\(line.trimmingCharacters(in: .whitespaces))'. \
            "Session" named nothing this panel does — it holds one toggle about the city in \
            the session NAME — and it collided with the "Save & Export" panel two chips over, \
            which is where a user reasonably looks to save a session.
            """)
    }

    func testTheVoiceOverNameFollowsTheChip() throws {
        let source = try lines(Self.studio)
        let names = code(try window(source,
                                    opening: "var fullName: String {",
                                    closing: ["private ", "func ", "static "]))
        guard let line = names.first(where: { $0.contains("case .session:") }) else {
            return XCTFail("the `.session` chip lost its VoiceOver name")
        }
        XCTAssertFalse(line.lowercased().contains("weather"), """
            #359: the spoken name still promises weather behind a chip that no longer holds \
            it. Found: '\(line.trimmingCharacters(in: .whitespaces))'. A VoiceOver user \
            following that sentence lands on a panel with one location toggle in it.
            """)
        XCTAssertTrue(line.contains("Place"), """
            #359: the spoken name must start from the same word the chip shows, or the \
            sighted and the spoken app disagree about what the door is.
            """)
    }
}
