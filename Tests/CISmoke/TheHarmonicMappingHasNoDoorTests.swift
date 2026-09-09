// TheHarmonicMappingHasNoDoorTests.swift
// Echoel — two of PolySynthVoice's three bio flags have no reachable writer, and the third does.
//
// WHY IT EXISTS (#1153, measured). `bioModulationEnabled`, `bioMappingHarmonic` and
// `entrainmentEnabled` sit within twenty lines of each other, are all `Bool = false`, and read
// as interchangeable. They are not. `bioModulationEnabled` is set true from `EchoelStudioView`,
// i.e. it is live. The other two are written ONLY by `BioSourceView`'s Toggles, and that view
// has zero construction sites — doorless, deliberately, like `PulseMeasurementView` and
// `BreathGuideView` before it.
//
// The register in CLAUDE.md names the doorless VIEW. It cannot tell a reader which PROPERTIES
// died with it, and that is the #1147 lesson: the entry does not reach the line a session reads
// first. So the notes live at the declarations, and this file keeps them true.
//
// ⚠️ THE COUNTING TRAP THIS FILE MUST NOT FALL INTO, because the repo has already paid for it
// twice in these very files. A bare `git grep -n 'BioSourceView(' -- Sources` returns THREE
// hits and every one is a COMMENT quoting that same recipe — `BioSourceView.swift` and
// `PulseMeasurementView.swift` both warn about it in their headers. A mention is not a
// construction site. `constructionSites` below strips comment lines before counting, which is
// the corrected recipe those two headers already publish.
//
// ⚠️ IT FORBIDS NOTHING (#364). Re-dooring either flag is a call site, not a rebuild, and both
// mechanisms are live tested code. This goes red so the PROSE moves in the same commit — and
// for `entrainmentEnabled` the failure message names the safety copy that has to move with it.

import Foundation
import XCTest

final class TheHarmonicMappingHasNoDoorTests: XCTestCase {

    private static let voice = "Sources/Echoelmusic/Tools/PolySynthVoice.swift"
    private static let bioSource = "Sources/Echoelmusic/Studio/BioSourceView.swift"

    private func root() throws -> URL {
        let r = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: r.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(r.path)") }
        return r
    }

    private func raw(_ relativePath: String) throws -> String {
        let path = try root().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            XCTFail("ANCHOR MISSING: \(relativePath) could not be read — a missing anchor is a "
                    + "finding, not a pass.")
            return ""
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    private func allSources() throws -> [(String, String)] {
        let base = try root().appendingPathComponent("Sources")
        guard let walk = FileManager.default.enumerator(atPath: base.path) else { return [] }
        var out: [(String, String)] = []
        for case let rel as String in walk where rel.hasSuffix(".swift") {
            let full = base.appendingPathComponent(rel)
            if let text = try? String(contentsOf: full, encoding: .utf8) { out.append((rel, text)) }
        }
        return out
    }

    /// Lines that are not comments — the only place a real writer or construction site can live.
    private func codeLines(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                return !t.hasPrefix("//") && !t.hasPrefix("///") && !t.hasPrefix("*")
            }
    }

    /// Files that assign this property in CODE, excluding `BioSourceView` (the doorless setter)
    /// AND `PolySynthVoice` itself.
    ///
    /// ⚠️ EXCLUDING THE DECLARING FILE IS NOT TIDINESS. `bioModulationEnabled`'s `didSet`
    /// forwards to the inner engine (`poly.bioModulationEnabled = bioModulationEnabled`), which
    /// matches the same needle. Counting it would let claim 3 stay green after the last real
    /// SURFACE stopped writing the flag — the guard would be reading its own plumbing and
    /// calling it a door. The first draft of this file did exactly that.
    private func writersOutsideBioSource(_ property: String) throws -> [String] {
        var found: [String] = []
        for (rel, text) in try allSources()
        where !rel.hasSuffix("BioSourceView.swift") && !rel.hasSuffix("PolySynthVoice.swift") {
            for line in codeLines(text) where line.contains(".\(property) =") { found.append(rel) }
        }
        return found
    }

    // MARK: - 1 · BioSourceView is still doorless, counted the corrected way

    func testTheOnlyDoorForTheseFlagsIsStillUnmounted() throws {
        var sites: [String] = []
        for (rel, text) in try allSources() where !rel.hasSuffix("BioSourceView.swift") {
            for line in codeLines(text) where line.contains("BioSourceView(") {
                sites.append("\(rel): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertTrue(sites.isEmpty, """
            `BioSourceView` now HAS a construction site, so it may be reachable — and if it is, \
            the two ⛔ notes in PolySynthVoice.swift ("NO REACHABLE WRITER") became false in the \
            commit that mounted it. Re-dooring is allowed and welcome (#364); moving the prose \
            is not optional. And for `entrainmentEnabled` specifically, CLAUDE.md's SAFETY \
            WARNINGS (no vehicles, no alcohol/drugs, coordinate medication, <=3 Hz flash) must \
            reach the user in the SAME commit that lets anyone arm the stimulus.

            Sites: \(sites.joined(separator: " | "))
            """)
        XCTAssertFalse(try raw(Self.bioSource).isEmpty, """
            `BioSourceView.swift` is gone. If the view was deleted rather than mounted, the two \
            flags lost their only setter for good and the notes should say DELETED, not doorless.
            """)
    }

    // MARK: - 2 · The two dead flags have no writer anywhere else

    func testTheTwoDoorlessFlagsHaveNoOtherWriter() throws {
        for property in ["bioMappingHarmonic", "entrainmentEnabled"] {
            let writers = try writersOutsideBioSource(property)
            XCTAssertTrue(writers.isEmpty, """
                `\(property)` is now written outside `BioSourceView` (\(writers.joined(separator: ", "))), \
                so it is no longer doorless and its ⛔ note in PolySynthVoice.swift is false. Move \
                the note in this commit. For `entrainmentEnabled` the safety copy moves with it.
                """)
        }
    }

    // MARK: - 3 · The live one is genuinely live — the contrast is the whole point

    func testTheThirdFlagIsReachableAndStaysTheCounterexample() throws {
        let writers = try writersOutsideBioSource("bioModulationEnabled")
        XCTAssertFalse(writers.isEmpty, """
            `bioModulationEnabled` no longer has a writer outside `BioSourceView`, so all three \
            bio flags are doorless and the notes' central claim — that these three look alike and \
            are NOT alike — no longer holds. Either a reachable surface stopped enabling bio \
            modulation on the polyphonic voice (a real regression, since that is how the body \
            reaches the pad at all), or the write moved. Check which before editing the prose.
            """)
    }

    // MARK: - 4 · Both notes are present, as POSITIVE scans

    /// No negative scan anywhere in this file: a retraction has to quote what it strikes, so an
    /// absence test would match the retraction itself (#1142/#1144/#1147). These assert presence.
    func testBothDeclarationsCarryTheirNote() throws {
        let src = try raw(Self.voice)
        guard !src.isEmpty else { return }
        XCTAssertEqual(src.components(separatedBy: "NO REACHABLE WRITER (#1153").count - 1, 2, """
            PolySynthVoice.swift should carry exactly TWO "NO REACHABLE WRITER (#1153" notes — \
            one at `bioMappingHarmonic`, one at `entrainmentEnabled`. A different count means a \
            flag gained or lost a door without its note moving, which is the drift this file exists \
            to catch.
            """)
        XCTAssertTrue(src.contains("SHIPS THE WARNINGS IN THE SAME COMMIT"), """
            The entrainment note lost the sentence binding a future door to CLAUDE.md's safety \
            warnings. That sentence is the reason this note is worth more than a register line.
            """)
    }
}
