// TheBluetoothCodecReachesTheScreenTests.swift
// Echoel — the picker says what the route can CARRY, not only what it costs. #670.
//
// WHY THIS EXISTS. The founder asked (2026-08-20) for "Interface per Kabel und auch per
// Bluetooth … alle Latenzen und Kombinationen optimiert für Sessions". Two warnings already
// stood in `AudioInputPickerView` and BOTH are about DELAY ("~150–250 ms"). Neither covers the
// effect that actually ruins a take: `recordOptions` carries `.allowBluetooth` (HFP) — and it
// has to, that is how a Bluetooth mic works at all — so once the mic is claimed iOS pulls the
// WHOLE shared route down to the mono call codec. The music goes with it. A player hears his
// own instrument turn into a telephone while every number on screen still reads healthy,
// because no LATENCY number can express a BANDWIDTH collapse.
//
// ⚠️ HONEST LIMITS. 7 test methods under 6 numbered sections (section 1 has two), 29
// `XCTAssert*` — re-derive both, do not re-type:
//   grep -c "    func test" <this file>
//   grep -n "XCTAssert" <this file> | grep -vc ':[[:space:]]*//'
// Sections 1–3 are END-TO-END BEHAVIOUR: the verdict and both sentences are driven with real
// port lists, including the values a session answers with mid-route-change. Test 2 is the one
// that closes the string-literal hole — it asserts the AVFoundation constants still equal the
// text `AudioConfiguration` compares against, so an iOS rename turns this red instead of
// turning the verdict silently permissive. Sections 4–6 are SOURCE-TEXT SCANS, because the
// gathering and the view sit behind `AVAudioSession` and `@MainActor`.
// What NO test here can prove: that iOS actually reports `BluetoothHFP` on the founder's
// HI-X25BT while monitoring. That is a device probe, and the note is written to be correct
// either way — `.telephonySuspected` says "looks like", never "is".

import XCTest
#if canImport(AVFoundation)
import AVFoundation
#endif
@testable import Echoelmusic

final class TheBluetoothCodecReachesTheScreenTests: XCTestCase {

    private static let config = "Sources/Echoelmusic/Audio/AudioConfiguration.swift"
    private static let picker = "Sources/Echoelmusic/Studio/AudioInputPickerView.swift"

    // MARK: - 1. The verdict is a fact first and an inference second

    func testAnHFPPortIsDefinitiveAndARateAloneIsNot() {
        let hfp = AudioConfiguration.routeCodec(outputPortTypes: ["BluetoothHFP"],
                                                sampleRate: 16_000)
        XCTAssertEqual(hfp, .telephony, """
            An HFP port in the route no longer reads as call mode. iOS NAMES this port; it is \
            the one case here that is a fact rather than an inference, and losing it means the \
            picker falls back to guessing about the very route it can see.
            """)

        // Definitive beats corroborating: the port wins even when the rate looks healthy.
        XCTAssertEqual(AudioConfiguration.routeCodec(outputPortTypes: ["BluetoothHFP"],
                                                     sampleRate: 48_000),
                       .telephony, """
            A named HFP port was downgraded because the sample rate looked fine. The rate is \
            CORROBORATION for the case where iOS did not name the port — it can never overrule \
            the port that was named.
            """)

        let a2dpLow = AudioConfiguration.routeCodec(outputPortTypes: ["BluetoothA2DPOutput"],
                                                   sampleRate: 16_000)
        XCTAssertEqual(a2dpLow, .telephonySuspected, """
            A Bluetooth output running at a call-mode rate produced no warning. This is the \
            shape the founder's HI-X25BT is most likely to present, and it is exactly the case \
            where the numbers on screen all look healthy while the sound does not.
            """)

        XCTAssertEqual(AudioConfiguration.routeCodec(outputPortTypes: ["BluetoothLE"],
                                                     sampleRate: 8_000),
                       .telephonySuspected,
                       "an LE audio output at 8 kHz stopped being suspected of call mode.")
    }

    func testAHealthyRouteIsNotWarnedAbout() {
        XCTAssertEqual(AudioConfiguration.routeCodec(outputPortTypes: ["BluetoothA2DPOutput"],
                                                     sampleRate: 48_000),
                       .wideband, """
            A Bluetooth route carrying full bandwidth was warned about anyway. A red line on a \
            healthy route is not a harmless extra: it trains the founder to ignore the row, \
            and the row exists for the one case where it matters.
            """)
        XCTAssertEqual(AudioConfiguration.routeCodec(outputPortTypes: ["Speaker"],
                                                     sampleRate: 16_000),
                       .wideband, """
            A WIRED route at a low rate was called Bluetooth call mode. The rate is only \
            evidence in the presence of a Bluetooth port — on a cable it means something else \
            entirely and this row must stay quiet about it.
            """)
        XCTAssertEqual(AudioConfiguration.routeCodec(outputPortTypes: [], sampleRate: 16_000),
                       .wideband, "an empty port list produced a claim about a route it cannot see.")

        // A session queried mid-route-change answers with anything. This row fires during a
        // route rebuild, so these are edge cases here, not impossibilities (the same reason
        // `latencyFloorSeconds` filters its parts).
        for bad in [Double.nan, 0, -1, .infinity] {
            XCTAssertEqual(AudioConfiguration.routeCodec(outputPortTypes: ["BluetoothA2DPOutput"],
                                                         sampleRate: bad),
                           .wideband, """
                A non-finite or non-positive sample rate (\(bad)) was read as evidence of call \
                mode. Mid-route-change that value means "no answer yet", and turning it into a \
                red warning puts the alarm on a healthy cable at the worst possible moment.
                """)
        }
    }

    // MARK: - 2. The string literals still name the ports iOS ships

    func testTheComparedLiteralsStillEqualTheAVFoundationConstants() throws {
        #if os(iOS)
        XCTAssertEqual(AVAudioSession.Port.bluetoothHFP.rawValue, AudioConfiguration.hfpPortType, """
            `AVAudioSessionPortBluetoothHFP`'s raw value no longer equals the literal \
            `routeCodec` compares against. This is the ONLY thing standing between a pure, \
            testable verdict and a typo that makes it silently permissive — a renamed port \
            would mean every HFP route reports `.wideband` and nothing on screen changes.
            """)
        XCTAssertTrue(AudioConfiguration.bluetoothOutputPortTypes
                        .contains(AVAudioSession.Port.bluetoothA2DP.rawValue),
                      "the A2DP port's raw value is no longer in the Bluetooth-output list.")
        XCTAssertTrue(AudioConfiguration.bluetoothOutputPortTypes
                        .contains(AVAudioSession.Port.bluetoothLE.rawValue),
                      "the LE port's raw value is no longer in the Bluetooth-output list.")
        #else
        throw XCTSkip("AVAudioSession.Port is iOS-only; the literals cannot be checked here.")
        #endif
    }

    // MARK: - 3. A guess and a fact do not print the same sentence

    func testTheTwoNotesDifferAndTheInferredOneHedges() throws {
        XCTAssertNil(AudioConfiguration.RouteCodec.wideband.note, """
            A healthy route gained a sentence. `nil` means the row renders NOTHING — an \
            "all good" line would be a reassurance the app was never asked for and cannot \
            always justify.
            """)

        let fact = try XCTUnwrap(AudioConfiguration.RouteCodec.telephony.note,
                                 "the definitive case lost its sentence, so the picker shows a "
                                 + "verdict it cannot explain.")
        let guess = try XCTUnwrap(AudioConfiguration.RouteCodec.telephonySuspected.note,
                                  "the inferred case lost its sentence.")
        XCTAssertNotEqual(fact, guess, """
            The named-port case and the inferred case print the SAME sentence. #654 exists \
            because this file once rendered "could not measure" and "measured zero" \
            identically; collapsing a fact and a guess into one wording is that defect again.
            """)
        XCTAssertTrue(guess.contains("looks like"), """
            The INFERRED verdict stopped hedging. It is built from a sample rate, not from a \
            port iOS named — stating it as certainty is an over-claim on the surface the \
            founder actually reads.
            """)
        XCTAssertFalse(fact.contains("looks like"),
                       "the DEFINITIVE verdict started hedging about a port iOS named outright.")
        for note in [fact, guess] {
            XCTAssertTrue(note.contains("bandwidth"), """
                A codec note stopped naming BANDWIDTH. Its whole reason to exist is that the \
                two warnings beside it are about delay and this one is not; without the word \
                it reads as a third latency line and gets skipped.
                """)
            XCTAssertTrue(note.contains("cable"), """
                A codec note stopped naming the remedy. A warning the player cannot act on in \
                the moment is decoration — "use a cable" is the whole point.
                """)
        }
    }

    // MARK: - 4. ONE verdict, gathered where the numbers are gathered

    func testTheSnapshotCarriesTheVerdictAndNothingDefaultsIt() throws {
        let code = try Self.codeText(Self.config)

        XCTAssertEqual(Self.occurrences(of: "static func routeCodec", in: code), 1, """
            `routeCodec` is declared \(Self.occurrences(of: "static func routeCodec", in: code)) \
            times. Two spellings of one verdict is how the log and the screen start disagreeing \
            about the same route (#416) — the exact drift the shared gathering removed.
            """)
        XCTAssertTrue(code.contains("codec: routeCodec(outputPortTypes:"), """
            `latencySnapshot` no longer derives the verdict from the gathered route. If it is \
            computed anywhere else it is computed from a SECOND read of the session, and the \
            screen can then contradict itself between two lines of the same row.
            """)
        XCTAssertTrue(code.contains("let codec: RouteCodec"), """
            `LatencyReadout.codec` is gone or gained a default. A defaulted field appears in no \
            diff and no call site has to think about it (#431/#440/#443) — and this one is the \
            difference between a session and a phone call.
            """)
        XCTAssertFalse(code.contains("let codec: RouteCodec ="), """
            `codec` acquired a default value, so a new construction site can omit it and \
            silently report `.wideband` about a route it never classified.
            """)
        XCTAssertTrue(code.contains("outputPortTypes: current.outputs.map(\\.portType.rawValue)"), """
            The gathering stopped collecting the output port types, so `routeCodec` is being \
            handed an empty list — which resolves to `.wideband` and renders NOTHING. This is \
            the silent-failure shape: the row disappears and nothing goes red.
            """)
    }

    // MARK: - 5. The bandwidth claim is not folded into the latency number

    func testTheCodecDoesNotContaminateTheFloorOrTheBreakdown() throws {
        let code = try Self.codeText(Self.config)

        // ⛔ The first version ended each slice on the literal "\n        }" — a brace shape,
        // not a symbol. `scripts/dead-needles.py` correctly called it absent from `Sources/`:
        // a needle that is whitespace-and-punctuation can never be verified against the tree,
        // so an anchor that drifted would fail on a CORRECT repo (#408/#454). Both slices now
        // end on the NEXT declaration, and both ends are asserted unique.
        for anchor in ["static func latencyFloorSeconds", "enum RouteCodec: Sendable",
                       "var breakdownText: String", "static func latencySnapshot"] {
            XCTAssertEqual(Self.occurrences(of: anchor, in: code), 1, """
                `\(anchor)` occurs \(Self.occurrences(of: anchor, in: code)) times, so the \
                slices below are cut at the wrong place and their negatives are vacuous. \
                Re-anchor before trusting claim 5 (#408).
                """)
        }

        let floor = try Self.slice(code, from: "static func latencyFloorSeconds",
                                   to: "enum RouteCodec: Sendable")
        XCTAssertFalse(floor.contains("codec") || floor.contains("Codec"), """
            The codec verdict reached `latencyFloorSeconds`. The floor is a SUM OF SECONDS; a \
            bandwidth verdict has no term in it, and folding one in would produce a number \
            that changes when nothing about the timing did.
            """)

        let breakdown = try Self.slice(code, from: "var breakdownText: String",
                                       to: "static func latencySnapshot")
        XCTAssertFalse(breakdown.contains("call mode"), """
            The breakdown line started carrying the codec sentence. It is the parts of ONE \
            number; a warning glued onto it is read as part of the measurement, and the two \
            have to be able to disagree — a wired route can be slow, a fast one can be mono.
            """)
    }

    // MARK: - 6. The freeze law: rendered in the leaf, never in the picker body

    func testTheNoteIsRenderedInTheLeafAndOnlyWhenThereIsSomethingToSay() throws {
        let code = try Self.codeText(Self.picker)

        XCTAssertTrue(code.contains("readout.codec.note"), """
            The picker stopped rendering the codec note, so the verdict is computed on every \
            route change and shown to nobody. That is worse than not computing it: the guard \
            below still passes and the founder still hears a telephone.
            """)
        XCTAssertTrue(code.contains("if let note = readout.codec.note"), """
            The note is rendered unconditionally. `nil` is the healthy case and MUST render no \
            row at all — an empty `Text` still takes a line and a healthy route must look \
            silent, not blank.
            """)

        let leaf = try XCTUnwrap(code.range(of: "private struct MonitorLatencyRow: View"),
                                 "cannot anchor the leaf; re-anchor before trusting claim 6.")
        let above = String(code[code.startIndex..<leaf.lowerBound])
        // The same sentinel the sibling guard carries: the leaf is last in the file today, so
        // `above` is the whole parent. A leaf-first refactor would make it EMPTY and the
        // `== 0` below would then pass on nothing (#454).
        XCTAssertTrue(above.contains("struct AudioInputPickerView"), """
            The leaf is declared BEFORE `AudioInputPickerView`, so the slice below is empty or \
            partial. Re-anchor on the parent's own body before trusting this claim.
            """)
        XCTAssertEqual(Self.occurrences(of: "readout.codec", in: above), 0, """
            The codec is read ABOVE the leaf — i.e. inside `AudioInputPickerView` itself. That \
            body hosts Pickers, and a value read there registers the whole body as an observer: \
            every route change tears down an open `.menu` popover (10.76.41/50). The row is a \
            separate `View` for this reason and no other.
            """)
    }

    // MARK: - Helpers

    /// The text between two declarations, both of which must exist. Ends on a real SYMBOL,
    /// never on a brace shape — see the ⛔ note in claim 5.
    private static func slice(_ text: String, from: String, to: String) throws -> String {
        let start = try XCTUnwrap(text.range(of: from), "cannot anchor on `\(from)` (#454).")
        let end = try XCTUnwrap(text.range(of: to, range: start.upperBound..<text.endIndex),
                                "`\(to)` no longer follows `\(from)`; re-anchor (#454).")
        return String(text[start.lowerBound..<end.lowerBound])
    }

    private static func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    private static func codeText(_ path: String) throws -> String {
        SourceText.codeOnly(try repoText(path))
    }

    private static func repoText(_ path: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            dir.deleteLastPathComponent()
            let candidate = dir.appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
        }
        throw NSError(domain: "TheBluetoothCodecReachesTheScreenTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey:
                        "cannot find \(path) walking up from #filePath — re-anchor (#454)."])
    }
}
