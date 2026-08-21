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
// ⚠️ HONEST LIMITS. 7 test methods under 6 numbered sections (section 1 has two), 30
// `XCTAssert*` — re-derive both, do not re-type:
//   grep -c "^    func test" <this file>
//   grep -n "XCTAssert" <this file> | grep -vc ':[[:space:]]*//'
// ⛔ The first recipe was `grep -c "    func test"` and it printed 8, because the recipe LINE
// matched itself — a quoted command that contradicts the prose beside it is read as evidence
// against the prose, and a later session would have "corrected" a correct 7 to 8. The `^`
// anchors it past the comment marker. The sibling recipe already excluded itself; only one of
// the two did, which is exactly how the asymmetry survived being written and read.
// Sections 1 and 3 are END-TO-END BEHAVIOUR; section 2 is a CONSTANT PIN — it asserts two
// AVFoundation raw values still equal two literals and exercises no behaviour at all: the verdict and both sentences are driven with real
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
        XCTAssertEqual(AudioConfiguration.bluetoothOutputPortTypes.count, 2, """
            The Bluetooth-output list has \(AudioConfiguration.bluetoothOutputPortTypes.count) \
            entries, not 2. The two assertions above check MEMBERSHIP only, which is one-way: a \
            spurious third entry passes them while widening `.telephonySuspected` onto routes \
            the array claims not to list. A list whose length nothing checks is sampled, not \
            pinned.
            """)
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
            `LatencyReadout.codec` is gone or was re-declared. A defaulted field appears in no \
            diff and no call site has to think about it (#431/#440/#443) — and this one is the \
            difference between a session and a phone call.
            """)
        // ⛔ The first version tested ONE spelling, `"let codec: RouteCodec ="`. A default
        // written as `var codec: RouteCodec = .wideband`, or `let codec = RouteCodec.wideband`,
        // or with a qualified type, sailed past a message claiming to enforce #431/#440/#443 in
        // general. The declaration is located first and only its own line is examined, so every
        // spelling of "= something" on it is caught and no unrelated `=` elsewhere is.
        let declaration = try XCTUnwrap(Self.line(containing: "codec: RouteCodec", in: code), """
            cannot find the declaration line of `LatencyReadout.codec` — re-anchor before \
            trusting this claim (#454).
            """)
        XCTAssertFalse(declaration.contains("="), """
            `codec` acquired a default value ("\(declaration.trimmingCharacters(in: .whitespaces))"), \
            so a new construction site can omit it and silently report `.wideband` about a route \
            it never classified.
            """)
        // ⛔ And the needle below was the literal expression `current.outputs.map(\\.portType…)`.
        // Hoisting that into a local — which this very file already does two declarations away
        // to dodge #287 type-check blowups — would have reddened a CORRECT tree. Two mechanism
        // tokens instead: the field must be POPULATED, and it must be populated from the port
        // TYPE (port NAMES are what `route=` uses, and they cannot classify a codec).
        XCTAssertTrue(code.contains("outputPortTypes: "), """
            The gathering stopped populating `outputPortTypes`, so `routeCodec` is handed an \
            empty list — which resolves to `.wideband` and renders NOTHING. This is the \
            silent-failure shape: the row disappears and nothing goes red.
            """)
        XCTAssertTrue(code.contains("portType.rawValue"), """
            The port TYPE no longer reaches the verdict. `portName` is what the route string \
            uses and it cannot classify a codec — "HI-X25BT" says nothing about HFP. Feeding \
            names here makes every route report `.wideband`, silently.
            """)
    }

    // MARK: - 5. The bandwidth claim is not folded into the latency number

    func testTheCodecDoesNotContaminateTheFloorOrTheBreakdown() throws {
        let code = try Self.codeText(Self.config)

        // ⛔ TWO earlier versions of this claim were wrong in DIFFERENT ways, and both are
        // recorded because the second was introduced while repairing the first.
        //  (1) The slices ended on the literal "\n        }" — a brace SHAPE, not a symbol.
        //      `scripts/dead-needles.py` correctly called it absent from `Sources/`: a needle
        //      of whitespace and punctuation cannot be verified against the tree (#408/#454).
        //  (2) The repair ended each slice on the NEXT declaration. That only worked because
        //      `RouteCodec` happens to sit right after `latencyFloorSeconds` today: moving the
        //      type up would make the search fail and redden a CORRECT tree, and inserting any
        //      declaration between them would silently WIDEN the slice.
        // The body is now brace-matched from the declaration, so it is exactly the function and
        // nothing near it — the same extraction #658 needed for the render-block ban.
        let floor = try Self.body(after: "static func latencyFloorSeconds", in: code)
        XCTAssertFalse(floor.contains("codec") || floor.contains("Codec"), """
            The codec verdict reached `latencyFloorSeconds`. The floor is a SUM OF SECONDS; a \
            bandwidth verdict has no term in it, and folding one in would produce a number \
            that changes when nothing about the timing did.
            """)

        // ⛔ And the breakdown half asserted `!contains("call mode")` — a fragment of the
        // RENDERED SENTENCE, which lives in `RouteCodec.note` hundreds of lines above and can
        // never be inside this body. The realistic regression is a MECHANISM, not a copy:
        //     return parts + " ms · " + route + (codec.note.map { " · " + $0 } ?? "")
        // contains no "call mode" at all, so the guard stayed green while the exact defect its
        // own four-line message described had shipped. #454 in its most deceptive form: the
        // slice was real, non-empty and correctly anchored — only the needle could not occur.
        let breakdown = try Self.body(after: "var breakdownText: String", in: code)
        XCTAssertFalse(breakdown.contains("codec") || breakdown.contains("Codec"), """
            The breakdown line started carrying the codec verdict. It is the parts of ONE \
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

    /// The brace-matched BODY of the declaration containing `anchor`, exclusive of anything
    /// after its closing brace. Ends on structure, never on a literal brace shape — see the two
    /// ⛔ notes in claim 5.
    ///
    /// ⚠️ `file`/`line` are forwarded so a failure marks the CALLER. Without them every anchor
    /// failure in this file pointed at these two lines, which is diagnosable only by reading
    /// the interpolated message — a guard that misreports its own location is a guard that gets
    /// re-anchored in the wrong place.
    private static func body(after anchor: String, in text: String,
                             file: StaticString = #filePath,
                             line: UInt = #line) throws -> String {
        let count = occurrences(of: anchor, in: text)
        guard count == 1 else {
            XCTFail("`\(anchor)` occurs \(count) times, not once, so the extracted body is "
                    + "ambiguous and every negative below it is vacuous. Re-anchor (#408).",
                    file: file, line: line)
            throw NSError(domain: "TheBluetoothCodecReachesTheScreenTests", code: 2, userInfo: nil)
        }
        let start = try XCTUnwrap(text.range(of: anchor), "unreachable: counted 1, found 0.",
                                  file: file, line: line)
        guard let open = text[start.upperBound...].firstIndex(of: "{") else {
            XCTFail("no `{` follows `\(anchor)`; it is no longer a declaration with a body.",
                    file: file, line: line)
            throw NSError(domain: "TheBluetoothCodecReachesTheScreenTests", code: 3, userInfo: nil)
        }
        var depth = 0
        var i = open
        while i < text.endIndex {
            if text[i] == "{" { depth += 1 }
            if text[i] == "}" {
                depth -= 1
                if depth == 0 { return String(text[open...i]) }
            }
            i = text.index(after: i)
        }
        XCTFail("braces never balance after `\(anchor)` — the file is truncated or the "
                + "comment stripper ate a brace.", file: file, line: line)
        throw NSError(domain: "TheBluetoothCodecReachesTheScreenTests", code: 4, userInfo: nil)
    }

    /// The single source line containing `needle`, or `nil`. Used where the claim is about ONE
    /// declaration and a file-wide `contains` would answer about the whole file.
    private static func line(containing needle: String, in text: String) -> String? {
        // `Character(...)` and an explicit closure rather than `"\n"` + `String.init`: both
        // bare forms have more than one overload here, and an ambiguity in a guard file fails
        // the BUNDLE, not this test — the #666 shape, where the compiler was the thing that
        // could not say what was wrong.
        text.split(separator: Character("\n"), omittingEmptySubsequences: false)
            .first { $0.contains(needle) }
            .map { String($0) }
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
