// TheFinishBandsShareTheNotchNodeTests.swift
// Echoel — #856/#857. Founder 2026-08-28: "der Sound der Stimme muss präsenter" and
// "Telephonmodus optional einführen". Both landed as extra bands on the EXISTING monitor
// EQ (`notchEQ`): bands 0..<4 stay the #848 dynamic howl notches, band 4 is the voice
// PRESENCE peak (gain 0 = neutral), bands 5+6 are the optional TELEPHONE band-pass
// (bypassed unless on). One node, three jobs — and the music never passes it, which is
// the property `TheNotchIsSlewedAndMonitorOnlyTests` already owns (#416: not re-pinned
// here).
//
// ⚠️ WHY THIS FILE EXISTS: the DANGEROUS regression is not a missing feature — it is a
// defence loop that iterates `notchEQ.bands` (ALL bands) instead of `notchBands.indices`
// (the four defence slots). Before #856 the two spellings were equivalent; now an
// all-bands loop silently wipes the presence gain or un-bypasses the telephone bands on
// every howl reset. Claims 2 and 3 pin the SCOPING, which is the half a feature test
// would never look at.
//
// ⚠️ WHAT IS DELIBERATELY NOT PINNED (#364): the presence frequency (3200), its
// bandwidth, the 0…6 range, the telephone corner frequencies (300/3400). All taste, all
// free to move. Pinned is STRUCTURE: the band map, the scoping, the re-apply, the doors.
//
// ⚠️ HONEST LIMIT (§1): source-text scans — this bundle cannot render audio or build the
// SwiftUI sheet. DEVICE PROBE, open: whether +6 dB presence reads as presence rather
// than harshness, and whether the telephone band sounds like a telephone.
//
// ⭐ GRADING (§3), transcribed in Python against this tree and the parent (d13ee04):
// FORWARD in full — every needle names #856/#857 text, red at the parent by the one
// shared absence (#486). Stripper: prophylactic; no needle sits in or contains a `//`.

import Foundation
import XCTest
@testable import Echoelmusic

final class TheFinishBandsShareTheNotchNodeTests: XCTestCase {

    private static let enginePath = "Sources/Echoelmusic/Audio/AudioEngine.swift"
    private static let sheetPath = "Sources/Echoelmusic/Studio/AudioInputPickerView.swift"

    // MARK: - 1: the band map exists — 7 bands, named finish indices

    func testTheNodeCarriesSevenBandsAndNamedFinishIndices() throws {
        let code = try code(Self.enginePath)
        XCTAssertEqual(occurrences(of: "AVAudioUnitEQ(numberOfBands: 7)", in: code), 1, """
            `notchEQ` is no longer the 7-band node (4 defence + presence + 2 telephone). \
            If the finish bands were removed on purpose, this whole file moves with them — \
            doors, re-apply and all; if a band was ADDED, extend the BAND MAP comment at \
            the declaration and this claim in the same commit.
            """)
        for needle in ["static let presenceBand = 4",
                       "static let telephoneHPBand = 5",
                       "static let telephoneLPBand = 6"] {
            XCTAssertEqual(occurrences(of: needle, in: code), 1,
                           "`\(needle)` is gone — the finish bands lost their named index.")
        }
    }

    // MARK: - 2: every defence loop is SCOPED to the four notch slots

    /// The regression this file exists for: an all-bands loop in the defence path wipes
    /// the presence gain / un-bypasses the telephone bands on every reset. Both defence
    /// loops must iterate `notchBands.indices`, and NO loop over `notchEQ.bands` may
    /// remain outside the attach-time configuration.
    func testTheDefenceLoopsAreScopedToTheNotchSlots() throws {
        let code = try code(Self.enginePath)
        XCTAssertEqual(occurrences(of: "for i in notchBands.indices where i < notchEQ.bands.count", in: code), 2, """
            expected exactly TWO scoped defence loops (attach-time notch config and \
            resetNotchDefence). A different count means a loop was widened back to \
            `notchEQ.bands` — which silently wipes the finish bands — or a third loop \
            appeared that this guard has not seen.
            """)
        XCTAssertEqual(occurrences(of: "for band in notchEQ.bands", in: code), 0, """
            an ALL-BANDS loop is back. Before #856 it was equivalent to the scoped \
            spelling; now it configures or zeroes the presence/telephone bands as if \
            they were howl notches. Scope it to `notchBands.indices`.
            """)
    }

    // MARK: - 3: monitoring ON re-applies both finish settings (the #829 pattern)

    func testMonitoringOnReappliesPresenceAndTelephone() throws {
        let code = try code(Self.enginePath)
        guard let fn = code.range(of: "func setInputMonitoring") else {
            XCTFail("setInputMonitoring is gone — re-anchor this claim (§4).")
            return
        }
        guard let mega = code.range(of: "notchEQ.globalGain = megaphoneMode ? Self.megaphoneBoostDB : 0",
                                    range: fn.lowerBound..<code.endIndex)
        else {
            XCTFail("the #829 megaphone re-apply is gone from setInputMonitoring — re-anchor (§4).")
            return
        }
        let window = String(code[mega.lowerBound...].prefix(600))
        for needle in ["notchEQ.bands[Self.presenceBand].gain = voicePresenceDB",
                       "notchEQ.bands[Self.telephoneHPBand].bypass = !telephoneMode",
                       "notchEQ.bands[Self.telephoneLPBand].bypass = !telephoneMode"] {
            XCTAssertTrue(window.contains(needle), """
                `\(needle)` is missing beside the #829 megaphone re-apply. The finish \
                values can be set while monitoring is off, and attach configured the \
                bands from the state at ATTACH time — without the re-apply, a toggle \
                made before monitoring ON silently does nothing.
                """)
        }
    }

    // MARK: - 4: both doors exist in the input sheet

    func testTheSheetCarriesThePresenceFieldAndTheTelephoneToggle() throws {
        let sheet = try code(Self.sheetPath)
        XCTAssertEqual(occurrences(of: "label: \"Presence\"", in: sheet), 1,
                       "the Presence `EchoelValueField` is gone from the input sheet — "
                       + "the engine parameter then has no producer (the doorless trap).")
        XCTAssertTrue(sheet.contains("audioEngine.voicePresenceDB = $0"),
                      "the Presence field no longer writes `voicePresenceDB`.")
        XCTAssertTrue(sheet.contains("audioEngine.telephoneMode = $0"),
                      "the Telephone toggle no longer writes `telephoneMode` — "
                      + "same doorless trap as above.")
        XCTAssertTrue(sheet.contains("accessibilityLabel(\"Telephone mode\")"),
                      "the Telephone toggle lost its accessibility label (a11y law).")
    }

    // MARK: - helpers (the house shape: strip comments, skip on no tree)

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private func code(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let text = try String(contentsOf: root.appendingPathComponent(relativePath),
                              encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }
}
