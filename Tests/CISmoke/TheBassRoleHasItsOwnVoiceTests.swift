// TheBassRoleHasItsOwnVoiceTests.swift
// Echoel — #983 S2: the `.bass` role has its own instrument, in the BLOCKING bundle.
//
// KINDS, per assertion (Tests/CISmoke/CLAUDE.md §1):
//   · END-TO-END on the pure genre tables (`MusicStyle.bassPatch` / `.bassGrammar` /
//     `.synthPatch`) — Foundation value types, the strong kind.
//   · SOURCE-TEXT for the ROUTING, because `PianoRollModel.outputVoice` is private and
//     `EchoelStudioView.generate()` is a private method on a SwiftUI view this bundle cannot
//     build. Same shape and same honesty as `SubBassFollowsTheToneSystemTests`.
//   · DEVICE PROBE — whether "House Sub" sounds like a house bass — is NOT here. That is the
//     plan's NEEDS-FOUNDER-VERIFY line.
//
// ⭐ THE ONE ASSERTION THAT MATTERS: patch ⇔ grammar. Before S2 the `.bass` role played through
// the PAD's voice and patch an octave down (measured in `PLAN_GENRE_BASS_PAD_LOOPS_2026-09-04.md`),
// so S1's figure alone was "the pad playing a bassline". A genre must carry both halves or
// neither — a timbre on the old walk, or a figure on the pad patch, is the ask done by halves.
//
// ⛔ WHAT IS NOT PINNED (#364): the patch NUMBERS. A designer may darken "Tech Bass" from 0.26 to
// 0.22 without touching this file; what is pinned is the RELATION to the genre's pad patch —
// darker, shorter, lower — which is the design and survives any re-tune that keeps it.

import XCTest
@testable import Echoelmusic

final class TheBassRoleHasItsOwnVoiceTests: XCTestCase {

    // MARK: - END-TO-END: the genre tables

    /// A genre has a bass patch IF AND ONLY IF it has a bass figure — swept over every case.
    func testABassPatchAndABassFigureComeTogetherOrNotAtAll() {
        for style in MusicStyle.allCases {
            XCTAssertEqual(style.bassPatch != nil, style.bassGrammar != nil,
                           "\(style.rawValue): bassPatch \(style.bassPatch == nil ? "nil" : "set") but "
                           + "bassGrammar \(style.bassGrammar == nil ? "nil" : "set") — S1 and S2 are "
                           + "one feature; give the genre both halves or neither")
        }
    }

    /// Every bass patch is darker, shorter, lower-cut, dry and mono next to its genre's pad patch.
    func testEveryBassPatchIsADarkerShorterLowerMonoCousinOfItsPad() {
        for style in MusicStyle.allCases {
            guard let bassPatch = style.bassPatch else { continue }
            let pad = style.synthPatch
            XCTAssertLessThan(bassPatch.brightness, pad.brightness, "\(style.rawValue): bass must be darker than its pad")
            XCTAssertLessThan(bassPatch.release, pad.release, "\(style.rawValue): bass must be shorter than its pad")
            XCTAssertLessThan(bassPatch.filterCutoff, pad.filterCutoff, "\(style.rawValue): bass must be lower-cut than its pad")
            XCTAssertEqual(bassPatch.reverbMix, 0, "\(style.rawValue): the bass is dry — the Bass bus and the sub carry the space")
            XCTAssertEqual(bassPatch.unisonVoices, 1, "\(style.rawValue): a detuned unison smears a bass fundamental")
            XCTAssertFalse(bassPatch.name.isEmpty, style.rawValue)
        }
    }

    /// Each bass patch's id is STABLE across calls and DISTINCT from every genre pad patch —
    /// the `GenrePatches.patch(_:)` suffix trap `GenreFamilyDistinctnessTests` documents.
    func testBassPatchIdentitiesAreStableAndDoNotCollideWithThePads() {
        var seen: [UUID: String] = [:]
        for style in MusicStyle.allCases {
            seen[style.synthPatch.id] = "\(style.rawValue).synthPatch"
        }
        for style in MusicStyle.allCases {
            guard let bassPatch = style.bassPatch else { continue }
            XCTAssertEqual(bassPatch.id, style.bassPatch?.id, "\(style.rawValue): bass patch id is not stable")
            if let owner = seen[bassPatch.id] {
                XCTFail("\(style.rawValue).bassPatch shares its id with \(owner)")
            }
            seen[bassPatch.id] = "\(style.rawValue).bassPatch"
        }
    }

    // MARK: - SOURCE-TEXT: the routing

    func testTheRollRoutesTheBassRoleToTheBassVoiceOnlyWhenActive() throws {
        let code = SourceText.codeOnly(try source("Sources/Echoelmusic/Studio/PianoRollView.swift"))
        XCTAssertTrue(code.contains("case .bass:    return (bassVoiceActive ? bass : nil) ?? voice"), """
            `PianoRollModel.outputVoice(for:)` no longer routes `.bass` through the dedicated bass \
            voice behind the `bassVoiceActive` gate. Either the bass plays through the pad again \
            (S2 undone) or it plays through the bass voice for EVERY genre — which re-voices \
            thirty ear-curated genres that never got a bass patch.
            """)
        XCTAssertTrue(code.contains("public func setBassVoiceActive(_ on: Bool)")
                      && code.contains("public func applyBassPatch(_ patch: SynthPatch) { bass?.apply(patch) }"),
                      "the two seams the studio drives (`setBassVoiceActive`, `applyBassPatch`) are gone")
        XCTAssertTrue(code.contains("bass?.allNotesOff()"), "`allNotesOff` must release the bass voice too")
    }

    func testTheStudioAppliesTheBassPatchAndTheRouteTogether() throws {
        let code = SourceText.codeOnly(try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift"))
        let apply = code.range(of: "if let bassPatch = style.bassPatch { pianoRoll.applyBassPatch(bassPatch) }")
        let route = code.range(of: "pianoRoll.setBassVoiceActive(style.bassPatch != nil)")
        XCTAssertNotNil(apply, "generate() no longer applies the genre's bass patch")
        XCTAssertNotNil(route, "generate() no longer routes the bass role per genre")
        if let apply, let route {
            XCTAssertLessThan(apply.lowerBound, route.lowerBound,
                              "patch BEFORE route, so the first bass note after a genre switch already sounds through the new patch")
        }
        // The three fans every pitched voice gets (#312/#338), and the panic inventory.
        for needle in ["bassSynth?.setInsert(trackFX.bass)", "bassSynth?.setInsert(fx)",
                       "bassSynth?.setTuningCents(cents)", "bassSynth?.setTuning(a4Hz: a4Hz)"] {
            XCTAssertTrue(code.contains(needle), "fan missing: \(needle)")
        }
        let panic = code.range(of: "private func panicAllNotesOff() {")
        XCTAssertNotNil(panic)
        if let panic {
            let window = code[panic.lowerBound...].prefix(900)
            XCTAssertTrue(window.contains("bassSynth,"), "the panic inventory does not reach the bass voice")
        }
    }

    func testTheAppAttachesStartsAndHandsTheBassVoiceToTheRoll() throws {
        let code = SourceText.codeOnly(try source("Sources/Echoelmusic/EchoelmusicApp.swift"))
        for needle in ["bassVoice.attach(to: audioEngine)", "bassVoice.start(subscribing: bus)",
                       "bass: bassVoice, subVoice: subBass", ".environment(\\.bassSynth, bassVoice)"] {
            XCTAssertTrue(code.contains(needle), "app wiring missing: \(needle)")
        }
    }

    // MARK: - helper

    private func source(_ path: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("Source tree not reachable from the test bundle — skipping rather than reporting a green this file did not earn.")
        }
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }
}
