// TheBluetoothCodecReachesTheScreenTests.swift
// Echoel — the picker says what the route can CARRY, not only what it costs. #670.
//
// WHY THIS EXISTS. The founder asked (2026-08-20) for "Interface per Kabel und auch per
// Bluetooth … alle Latenzen und Kombinationen optimiert für Sessions". Two warnings already
// stood in `AudioInputPickerView` and BOTH are about DELAY ("~150–250 ms"). Neither covers the
// effect that actually ruins a take: with `.allowBluetooth` (HFP) in the record options iOS
// can pull the WHOLE shared route down to the mono call codec once the mic is claimed.
// (⛔ "and it has to, that is how a Bluetooth mic works at all" stood here as the reason it
// was in the DEFAULT set — #824 rejected that and made it an opt-in; #827 struck even the
// opt-in on the founder's verdict "Keine Telefonqualität zulassen": Echoel never requests
// HFP at all now. The verdict this file pins matters regardless: another app or a call can
// put the shared route on HFP whatever Echoel's options say.)
// The music goes with it. A player hears his
// own instrument turn into a telephone while every number on screen still reads healthy,
// because no LATENCY number can express a BANDWIDTH collapse.
//
// ⚠️ HONEST LIMITS. 12 test methods under 8 numbered sections (1 and 7 hold more than one),
// 49 `XCTAssert*` — re-derive both, do not re-type:
//   grep -c "^    func test" <this file>
//   grep -n "XCTAssert" <this file> | grep -vc ':[[:space:]]*//'
// ⛔ The first recipe was `grep -c "    func test"` and it printed 8 where the prose said 7,
// because the recipe LINE matched itself. A quoted command that contradicts the prose beside
// it is read as evidence against the prose, so a later session would have "corrected" a
// correct 7 to 8. The `^` anchors it past the comment marker. The sibling recipe already
// excluded itself; only one of the two did, which is how the asymmetry survived being written
// AND read.
//
// Sections 1, 3 and most of 7 are EXECUTED BEHAVIOUR — the verdict, both sentences, the route
// label and the sanitiser are driven with real inputs, including the values a session answers
// with mid-route-change and a route that exceeds the log's length budget.
// ⚠️ NOT "end-to-end", which the first version of this line said: nothing here composes
// `routeLabel` → `currentSessionLatency` → `latencyLine` → `route=`. That chain is covered by
// an occurrence count and nothing more. The section-2 sentence below was rewritten in an
// earlier commit to stop overstating exactly this, and section 7 then got the looser word. Section 2 is a CONSTANT PIN: it asserts the AVFoundation raw values still
// equal the literals `AudioConfiguration` compares against, so an iOS rename turns this red
// instead of turning the verdict silently permissive. It exercises no behaviour of `routeCodec`
// at all, and saying otherwise would overstate what this file proves. Sections 4–6 and the
// last method of 7 are SOURCE-TEXT SCANS, because the gathering and the view sit behind
// `AVAudioSession` and `@MainActor`.
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
        // ⛔ TWO earlier versions, and the second was broken by a LATER commit rather than by
        // its own author — the rarer failure mode and the one no amount of care at writing
        // time prevents.
        //  (1) The needle was the literal expression `current.outputs.map(\\.portType…)`.
        //      Hoisting that into a local — which this very file already does two declarations
        //      away to dodge #287 — would have reddened a CORRECT tree.
        //  (2) The repair used two file-wide tokens, `"outputPortTypes: "` and
        //      `"portType.rawValue"`. Both were unique to the classifier feed WHEN WRITTEN.
        //      #672 added `routeLabel(portName:portType:)` to both port lists, taking
        //      `portType.rawValue` from 1 occurrence to 3 and `outputPortTypes: ` to 5 — so
        //      deleting the classifier feed entirely would have left BOTH assertions green,
        //      satisfied by the unrelated LABEL path, while `routeCodec` received an empty
        //      list and the red bandwidth warning silently vanished from the picker.
        // A file-wide token is only a mechanism pin while it is unique, and nothing warns you
        // on the day a sibling feature makes it common. Scoped to the gathering and to the
        // LINES that actually feed the field.
        let gathering = try Self.body(after: "private static func currentSessionLatency", in: code)
        let feeds = gathering.split(separator: Character("\n"), omittingEmptySubsequences: false)
            .filter { $0.contains("outputPortTypes:") }
        XCTAssertEqual(feeds.count, 2, """
            The gathering has \(feeds.count) lines feeding `outputPortTypes`, not 2 (one per \
            platform branch). #658 exists because the macOS arm alone once held a claim green \
            while the arm every device runs had lost it.
            """)
        XCTAssertTrue(feeds.contains { $0.contains("portType") }, """
            No branch feeds `outputPortTypes` from the port TYPE any more, so `routeCodec` is \
            handed an empty or name-derived list. `portName` cannot classify a codec — \
            "HI-X25BT" says nothing about HFP — so every route reports `.wideband` and the \
            warning disappears from the picker with nothing going red.
            """)
        XCTAssertTrue(feeds.contains { $0.contains("[]") }, """
            The macOS branch stopped declaring its port list EMPTY. Empty resolves to \
            `.wideband`, which renders no claim at all — silence. Anything else there would be \
            a classification of a HAL route this file cannot classify (#654).
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

    // MARK: - 7. The exported log can explain the red line on screen (#672)

    func testTheRouteStringCarriesThePortTypeForBluetoothOnly() {
        XCTAssertEqual(AudioConfiguration.routeLabel(portName: "HI-X25BT",
                                                     portType: "BluetoothHFP"),
                       "HI-X25BT[HFP]", """
            The route string stopped carrying the port TYPE for a named HFP port. This is the \
            only place the DEFINITIVE half of the verdict reaches `echoel_diag.log`: without \
            it the founder can export a log taken while a red warning was on screen, and \
            nothing in the file explains the warning (#671's retraction, closed by #672).
            """)
        XCTAssertEqual(AudioConfiguration.routeLabel(portName: "HI-X25BT",
                                                     portType: "BluetoothA2DPOutput"),
                       "HI-X25BT[A2DP]",
                       "an A2DP port stopped being distinguishable from HFP in the log.")
        XCTAssertEqual(AudioConfiguration.routeLabel(portName: "AirPods",
                                                     portType: "BluetoothLE"),
                       "AirPods[LE]", "an LE port stopped being marked.")

        // Non-Bluetooth is returned UNCHANGED, and that is a decision, not an omission: a
        // marker on every port is noise on the common case, and the route string feeds an
        // 80-character budget that truncates with `…`.
        XCTAssertEqual(AudioConfiguration.routeLabel(portName: "Built-In Microphone",
                                                     portType: "MicrophoneBuiltIn"),
                       "Built-In Microphone", """
            A wired port gained a marker. Every wired route now spends characters from the \
            80-char budget on a fact its NAME already carries, and the truncation that budget \
            enforces eats the far end — where the output port is.
            """)
        // ⛔ The first version asserted `routeLabel("", "Speaker") == ""` and called it "an
        // empty port name grew content out of nothing" — but "Speaker" takes the early return,
        // the one branch that is DEFINITIONALLY identity. The named risk can only occur on the
        // Bluetooth branch, and there it genuinely happens. It is pinned as INTENDED, because
        // it is: before #672 an unnamed Bluetooth port collapsed to `route=none→…` while
        // `inputAvailable` said `true` on the same line — the file contradicting itself.
        XCTAssertEqual(AudioConfiguration.routeLabel(portName: "", portType: "Speaker"), "",
                       "a wired port with no name grew content out of nothing.")
        XCTAssertEqual(AudioConfiguration.routeLabel(portName: "", portType: "BluetoothHFP"),
                       "[HFP]", """
            An unnamed Bluetooth port stopped reporting its type. It then collapses the joined \
            string to empty and the gathering prints `route=none→…` — while `inputAvailable` \
            reports `true` on the SAME line. A file that contradicts itself in two fields is \
            worse than one that says "there is a port here and iOS did not name it".
            """)
    }

    func testTheMarkerSurvivesTheLogSanitiserAndTheListStaysDerived() {
        // The marker is useless if the step between it and the file removes it. `sanitisedRoute`
        // masks "CRASH", flattens newlines and truncates at 80 — none of which should touch a
        // bracket, but "should not" is what a guard is for.
        let sanitised = AudioConfiguration.sanitisedRoute("Built-In Microphone→HI-X25BT[HFP]")
        XCTAssertTrue(sanitised.contains("[HFP]"), """
            `sanitisedRoute` now strips the port marker, so the fact is computed, put in the \
            string, and then removed one step before it reaches the file. Nothing else would \
            go red — the log would simply stop explaining itself.
            """)

        // ⛔ The assertion above is 33 characters long and `sanitisedRoute` only truncates past
        // 80 — so its first version drove the masking branch, never the truncation branch, and
        // said "strips OR TRUNCATES" in its failure message anyway. Half the named risk was
        // unguarded, and it was the REAL half: the marker is appended to each port name, the
        // OUTPUT port is the far end of the string, and the case that gets closest to the
        // budget is BT mic + BT headphones — precisely the HFP scenario this file exists for.
        // #673 changed the truncation to keep BOTH ends; this is what proves it.
        let doubled = "Michael Terbuyken's iPhone Mikrofon[HFP]"
                    + "→Michael Terbuyken's Beyerdynamic HI-X25BT[HFP]"
        XCTAssertGreaterThan(doubled.count, 80,
                             "the fixture no longer exceeds the budget, so it proves nothing.")
        let cut = AudioConfiguration.sanitisedRoute(doubled)
        XCTAssertTrue(cut.hasSuffix("[HFP]"), """
            Truncation dropped the OUTPUT port's marker: "\(cut)". The output is where the \
            collapse is HEARD, so it is the end worth guaranteeing — a head-only truncation \
            removes exactly the fact the marker was added to carry, in exactly the case that \
            needs it.
            """)
        XCTAssertLessThanOrEqual(cut.count, 81, """
            The route grew past the bound `currentLog()` depends on — it reads the whole file \
            into one String for the share sheet. Got \(cut.count).
            """)

        // #416: the marker table is THE definition and the list is derived from it. If someone
        // re-types the list as literals, the two can disagree — which is how a port ends up
        // marked in the log and invisible to the verdict, or the reverse.
        XCTAssertEqual(AudioConfiguration.bluetoothOutputPortTypes,
                       AudioConfiguration.bluetoothPortMarkers.keys
                        .filter { $0 != AudioConfiguration.hfpPortType }.sorted(), """
            `bluetoothOutputPortTypes` is no longer the marker table minus HFP. Two lists of \
            "which ports are Bluetooth" can disagree, and then a port is marked in the log but \
            invisible to the verdict, or classified by the verdict but unnamed in the log.
            """)
        XCTAssertNotNil(AudioConfiguration.bluetoothPortMarkers[AudioConfiguration.hfpPortType],
                        "the HFP port lost its marker, so the definitive case reaches no log.")
    }

    func testTheListIsDerivedInSourceAndNotMerelyEqualToTheDerivation() throws {
        // ⛔ #672 claimed "a guard pins the derivation, not just the contents". FALSE as
        // written: the assertion above compares VALUES, so re-typing `bluetoothOutputPortTypes`
        // as the literal `["BluetoothA2DPOutput", "BluetoothLE"]` keeps it green — the #416
        // hazard it says it closed is re-openable with no red test. A value check only fires
        // AFTER the two lists have already drifted, i.e. after the damage. This pins the
        // mechanism instead: the declaration must READ the marker table.
        let code = try Self.codeText(Self.config)
        let declaration = try XCTUnwrap(
            Self.line(containing: "static let bluetoothOutputPortTypes", in: code), """
            cannot find the declaration of `bluetoothOutputPortTypes` — re-anchor (#454).
            """)
        XCTAssertTrue(declaration.contains("bluetoothPortMarkers"), """
            `bluetoothOutputPortTypes` no longer derives from the marker table \
            ("\(declaration.trimmingCharacters(in: .whitespaces))"). Two hand-maintained lists \
            of "which port types are Bluetooth" can drift, and then a port is marked in the \
            log but invisible to the verdict, or classified by the verdict but unnamed in the \
            log — with both lists individually looking correct.
            """)
    }

    func testBothSidesOfTheRouteAreLabelled() throws {
        let code = try Self.codeText(Self.config)
        let gathering = try Self.body(after: "private static func currentSessionLatency", in: code)
        XCTAssertEqual(Self.occurrences(of: "routeLabel(portName:", in: gathering), 2, """
            The gathering labels \(Self.occurrences(of: "routeLabel(portName:", in: gathering)) \
            of its two port lists, not both. The INPUT side matters as much as the output: a \
            Bluetooth MIC is what pulls the shared route into HFP in the first place, so a log \
            that marked only the output would name the symptom and not the cause.
            """)
    }

    // MARK: - 8. The verdict is visible WITHOUT monitoring (#828)

    /// Until #828 the note rendered only inside `MonitorLatencyRow`, i.e. only while
    /// monitoring ran — and the route is SYSTEM-SHARED, so another app or a call could
    /// degrade the music while the warning was hidden (the gap section 6's own ⛔ block
    /// documented). `RouteCodecRow` closes it: mounted in the parent gated on
    /// !monitoring, so exactly ONE copy of the sentence is on screen at any time.
    func testTheVerdictIsVisibleWithoutMonitoring() throws {
        let code = try Self.codeText(Self.picker)
        XCTAssertTrue(code.contains("private struct RouteCodecRow: View"), """
            RouteCodecRow is gone — the codec verdict is again invisible unless \
            monitoring runs, while another app or a call can degrade the SHARED route \
            with Echoel in .playback. Since #827 Echoel never causes HFP itself, so \
            the external case is the ONLY one left to warn about.
            """)
        guard let gate = code.range(of: "if !audioEngine.isInputMonitoring {") else {
            XCTFail("The !monitoring gate is gone from monitoringSection — re-anchor "
                    + "this claim in the same commit if the mount was restructured.")
            return
        }
        let window = String(code[gate.lowerBound...].prefix(700))
        XCTAssertTrue(window.contains("RouteCodecRow()"), """
            RouteCodecRow is no longer mounted inside the !monitoring gate. Ungated it \
            would render the same sentence twice while monitoring runs (MonitorLatency\
            Row carries the other copy); unmounted it is a leaf nobody sees.
            """)
        guard let leaf = code.range(of: "private struct RouteCodecRow: View") else { return }
        let leafBody = String(code[leaf.lowerBound...].prefix(900))
        XCTAssertTrue(leafBody.contains("if let note = codec?.note"), """
            RouteCodecRow renders unconditionally — `nil` is the healthy case and MUST \
            render no row at all (section 6's law, same reason).
            """)
        XCTAssertTrue(leafBody.contains("latencySnapshot().codec"), """
            RouteCodecRow no longer reads the codec in its OWN body. Moving the read \
            into the Picker-hosting parent registers the whole body as an observer — \
            the 10.76.41/50 freeze (section 6's law, same reason).
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
