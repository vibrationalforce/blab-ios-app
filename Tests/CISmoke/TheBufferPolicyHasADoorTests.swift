// TheBufferPolicyHasADoorTests.swift
// Echoel — the latency policy had no producer, and the obvious way to give it one would have
// re-shipped a device-diagnosed defect. #674.
//
// WHY THIS EXISTS. `AudioConfiguration.LatencyMode` describes three buffer tiers and
// `setLatencyMode` applies them. Measured 2026-08-21: `setLatencyMode` had ZERO callers in
// `Sources/`, so `currentBufferSize` never left `normalBufferSize` (512) whatever the session
// was doing. That is the Doctor §C shape — a mechanism that exists, reads as live in every
// file that mentions it, and nothing can select.
//
// ⛔ AND THE OBVIOUS FIX WAS A TRAP. "Monitoring is on, so drop the buffer" would have
// re-introduced 10.76.49: 256 frames was the shipped default until dense polyphonic chords
// missed the render deadline and the founder heard "Aussetzer / Kratzen" on the device. The
// declaration of `currentBufferSize` records it. A monitoring session on this app is usually
// the generative music PLUS the live voice — the dense case AND a monitor path — so an
// automatic switch would have aimed the regression at exactly the session it claimed to
// optimise. So the DEFAULT IS UNCHANGED and the choice is the player's, with the cost written
// beside it. Claim 1 is what stops a later session from "finishing the job".
//
// ⚠️ HONEST LIMITS. 6 test methods, 28 `XCTAssert*` — re-derive both, do not re-type:
//   grep -c "^    func test" <this file>
//   grep -n "XCTAssert" <this file> | grep -vc ':[[:space:]]*//'
// Claim 2 mixes EXECUTED BEHAVIOUR on the enum with source scans; claims 1 and 3–6 are
// SOURCE-TEXT SCANS, because the view is `@MainActor` and `setLatencyMode` touches
// `AVAudioSession`.
// ⛔ The first header said "claims 1–2 are executed behaviour on shipped VALUE TYPES". Claim 2
// read `currentBufferSize`, a `nonisolated(unsafe) static var` — process-global mutable state,
// order-dependent inside the bundle, and not a value type. Claim 1 executed nothing that could
// fail. Overstating what a guard proves is the same defect as overstating what the app does.
// What NO test here can prove: that Low does not crackle on the founder's device under his
// material. That is the whole reason it is a choice with a warning and not a default.

import XCTest
@testable import Echoelmusic

final class TheBufferPolicyHasADoorTests: XCTestCase {

    private static let config = "Sources/Echoelmusic/Audio/AudioConfiguration.swift"
    private static let picker = "Sources/Echoelmusic/Studio/AudioInputPickerView.swift"

    // MARK: - 1. The shipped default did not move

    func testTheShippedDefaultIsStillTheSafeBuffer() throws {
        let config = try Self.codeText(Self.config)
        // ⛔ The first version asserted `normalBufferSize == LatencyMode.normal.bufferSize`,
        // which is `return AudioConfiguration.normalBufferSize` compared with itself. It could
        // not fail, and it is not even about the default: the SHIPPED default is a different
        // declaration, `currentBufferSize = normalBufferSize`. A later session reading this
        // slice's own "~14.7 ms is at the >15 ms FAIL line" argument could have edited that one
        // line to `lowLatencyBufferSize` — the 10.76.49 regression verbatim — with all
        // seventeen assertions green and this section still titled "the default did not move".
        XCTAssertTrue(config.contains("static var currentBufferSize: AVAudioFrameCount = normalBufferSize"), """
            The shipped default buffer is no longer `normalBufferSize`. 256 frames WAS the \
            default until dense polyphonic chords missed the render deadline and it was heard \
            on the device as crackle (10.76.49). Changing it back is a founder decision and a \
            device probe, not a one-line edit — the tier picker exists so nobody has to make it \
            for everyone.
            """)
        XCTAssertEqual(AudioConfiguration.LatencyMode.normal.bufferSize,
                       AudioConfiguration.normalBufferSize, """
            `LatencyMode.normal` no longer names the shipped default, so the control's "Normal" \
            is not the size the app boots with — the one position a player returns to when \
            something crackles.
            """)
        XCTAssertLessThan(AudioConfiguration.LatencyMode.low.bufferSize,
                          AudioConfiguration.LatencyMode.normal.bufferSize,
                          "the tiers stopped being ordered smallest-to-largest by latency.")
        XCTAssertLessThan(AudioConfiguration.LatencyMode.ultraLow.bufferSize,
                          AudioConfiguration.LatencyMode.low.bufferSize,
                          "the tiers stopped being ordered smallest-to-largest by latency.")
    }

    // MARK: - 2. The mode is DERIVED from the buffer, never tracked beside it

    func testTheModeIsComputedFromTheOneBufferValue() throws {
        let config = try Self.codeText(Self.config)
        // ⛔ The first version compared `currentLatencyMode!.bufferSize` with
        // `currentBufferSize` — but `currentLatencyMode` IS `allCases.first { $0.bufferSize ==
        // currentBufferSize }`, so the binding satisfied the assertion by construction. It
        // could not fail on any tree, and its message described a defect (a mode STORED beside
        // the size) that a value comparison is structurally unable to see. The claim it wanted
        // is "this property is computed", and that is a source-text fact.
        XCTAssertTrue(config.contains("static var currentLatencyMode: LatencyMode? {"), """
            `currentLatencyMode` is no longer a COMPUTED property. A stored mode can disagree \
            with `currentBufferSize`, and the size is what the measurement, the log line and \
            the on-screen floor all read — the control would then be lying about a number \
            rendered two lines above it (#416).
            """)
        XCTAssertEqual(AudioConfiguration.LatencyMode.allCases.count, 3,
                       "the tier list changed size; the segmented control's shape follows it.")
        // Distinct sizes, or two positions of the control would be the same setting and
        // `currentLatencyMode` would pick between them by declaration order.
        let sizes = Set(AudioConfiguration.LatencyMode.allCases.map(\.bufferSize))
        XCTAssertEqual(sizes.count, AudioConfiguration.LatencyMode.allCases.count, """
            Two tiers share a buffer size, so two positions of the segmented control do the \
            same thing.
            """)
        for mode in AudioConfiguration.LatencyMode.allCases {
            XCTAssertFalse(mode.shortName.isEmpty,
                           "a tier has no label, so one position of the control is blank.")
            // One spelling per value (#416): `"\(mode)"` and `.description` must agree.
            XCTAssertEqual(String(describing: mode), mode.description, """
                `\(mode)` prints one string in interpolation and another through \
                `.description`. `CustomStringConvertible` is what keeps a log line and a \
                failure message naming the same tier the same way.
                """)
        }
    }

    // MARK: - 3. Nothing switches the buffer on its own

    func testTheBufferIsOnlyEverChangedByADoor() throws {
        // ⛔ The first version scanned THREE named files. `Core/ResourceGovernor.swift` and
        // `Core/AdaptiveQuality.swift` already read `thermalState` and are the single most
        // likely place anyone would automate this — they were not scanned, so the guard would
        // have been green on exactly the change it exists to forbid. Repo-wide now.
        let sources = try Self.allSourceText()
        var callers: [String] = []
        for (path, code) in sources where Self.occurrences(of: "setLatencyMode", in: code) > 0 {
            callers.append(path)
        }
        XCTAssertEqual(Set(callers), [Self.config, Self.picker], """
            `setLatencyMode` is mentioned in \(callers.sorted()) — expected exactly its own \
            declaration and the ONE control a person operates. The buffer must not follow the \
            engine's state, the thermal tier or a route change: 256 frames was the shipped \
            default until dense chords missed the render deadline and it was heard as crackle \
            on the device (10.76.49). Automating it aims that regression at the session it \
            claims to optimise, and the player changed nothing. If this is deliberate it needs \
            the founder and a device probe, not a green test.
            """)
        let picker = try Self.codeText(Self.picker)
        XCTAssertEqual(Self.occurrences(of: "setLatencyMode", in: picker), 1, """
            The picker mentions `setLatencyMode` \(Self.occurrences(of: "setLatencyMode", in: picker)) \
            times, expected exactly once — from the control's own setter. A second call site in \
            a view is a call that is not a person pressing something.
            """)
    }

    // MARK: - 4. The buffer request never re-claims the route (#625/#628)

    func testTheBufferRequestIsOneCallAndNotASessionReconfigure() throws {
        let config = try Self.codeText(Self.config)
        let setter = try Self.body(after: "static func setLatencyMode", in: config)

        // ⛔ THE REASON THIS CLAIM EXISTS. #674 shipped `setLatencyMode` calling
        // `configureAudioSession()`, which ends in `setCategory(.playAndRecord) +
        // setActive(true, options: .notifyOthersOnDeactivation)` — the pair `AudioEngine`
        // documents as able to STOP a running engine underneath it. #625 was the founder
        // reporting exactly that ("Es funktioniert gar nichts und killt den restlichen Sound
        // auch"); #628 added the pause-before-claim discipline. The control's ONLY reachable
        // state is "monitoring live, music playing", so the known failure was aimed at the one
        // session the control was added to improve.
        XCTAssertFalse(setter.contains("configureAudioSession"), """
            `setLatencyMode` reconfigures the whole session again. That means \
            `setCategory(.playAndRecord) + setActive(true)` on a running engine, from a control \
            reachable only while monitoring is live — the #625 silence, re-armed. Changing the \
            buffer needs one call and no category change.
            """)
        XCTAssertFalse(setter.contains("setActive"), """
            `setLatencyMode` activates or deactivates the session. iOS may stop a running \
            `AVAudioEngine` underneath a re-activation (#625/#628); a buffer preference must \
            not touch session lifecycle at all.
            """)
        XCTAssertTrue(setter.contains("setPreferredIOBufferDuration"), """
            The buffer request no longer reaches the session, so the control moves a constant \
            and nothing else — the segment lights up and not one sample changes.
            """)

        // The ORDER is the claim: on a refusal the constant must not move, because it is what
        // the measurement, the log line and the on-screen floor all read.
        let request = try XCTUnwrap(setter.range(of: "setPreferredIOBufferDuration"),
                                    "cannot anchor the request; re-anchor (#454).")
        let commit = try XCTUnwrap(setter.range(of: "currentBufferSize = mode.bufferSize",
                                                range: request.upperBound..<setter.endIndex), """
            `currentBufferSize` is written BEFORE the session is asked, or not written after it \
            at all. Writing first means a refused request still moves the number the floor, the \
            log line and the picker all read — describing a size the session never granted. \
            #674 did exactly that and swallowed the throw with `try?`.
            """)
        XCTAssertGreaterThan(commit.lowerBound, request.upperBound,
                             "the commit no longer follows the request.")

        XCTAssertTrue(setter.contains("latencyBreadcrumb(reason:"), """
            A buffer change writes nothing to the EXPORTABLE log. `log.audio` does not reach \
            `echoel_diag.log` — only `latencyBreadcrumb` does (#653) — so the founder's log \
            would attribute the new size to the incidental "engine reconfigured" line, which \
            is precisely the wrong `reason:` #654 retracted.
            """)

        let picker = try Self.codeText(Self.picker)
        XCTAssertFalse(picker.contains("try? AudioConfiguration.setLatencyMode"), """
            The control swallows the throw again. On a refusal the buffer is unchanged, so a \
            lit segment over an unchanged floor is the app claiming something it did not do — \
            the over-claim this whole family (#653–#674) exists to remove.
            """)
    }

    // MARK: - 5. The cost is on screen, next to the switch

    func testTheSmallerBufferIsOfferedWithItsPrice() throws {
        let picker = try Self.codeText(Self.picker)

        XCTAssertTrue(picker.contains(".pickerStyle(.segmented)"), """
            The buffer control is no longer a segmented `Picker`. This is a NAMED choice of \
            three tiers, which the UI law routes to a `Picker` — the `EchoelValueField` rule is \
            for NUMERIC parameters, and offering 128–512 as a typed number would invite sizes \
            the audio graph never agreed to.
            """)
        // Source text, not the constant: `MonitorLatencyRow` is `private`, so `@testable` does
        // not reach it. The sibling guard pins its neighbour caveat the same way.
        XCTAssertTrue(picker.contains("crackled at Low before"), """
            The buffer caveat stopped naming the failure. 256 frames crackled on a real device \
            under dense chords (10.76.49); a switch whose failure mode is unstated hands the \
            player a mystery instead of a choice.
            """)
        XCTAssertTrue(picker.contains("Normal is the safe default"), """
            The caveat stopped naming the safe position, so a player who hears crackle has no \
            sentence telling them where to go back to.
            """)
        XCTAssertTrue(picker.contains("This is a request"), """
            The caveat stopped saying the tier is a REQUEST. iOS clamps it, hardest on \
            Bluetooth HFP — which `recordOptions` enables by necessity — while the floor above \
            reports what was GRANTED. Without this sentence a lit segment over an unmoved \
            number reads as a broken app instead of an honest one.
            """)
        XCTAssertTrue(picker.contains("resets on relaunch"), """
            The caveat stopped saying the choice does not persist. `currentBufferSize` is a \
            plain `static var` re-initialised every launch; losing a setting the caveat just \
            explained, without a word, is worse than not offering it.
            """)
    }

    // MARK: - 6. The freeze law: the control lives in the leaf it affects

    func testTheControlAndTheNumberItMovesShareOneLeaf() throws {
        let code = try Self.codeText(Self.picker)
        let leaf = try XCTUnwrap(code.range(of: "private struct MonitorLatencyRow: View"),
                                 "cannot anchor the leaf; re-anchor before trusting claim 6.")
        let above = String(code[code.startIndex..<leaf.lowerBound])
        let body = String(code[leaf.lowerBound...])
        XCTAssertTrue(above.contains("struct AudioInputPickerView"), """
            The leaf is declared BEFORE `AudioInputPickerView`, so the slice below is empty or \
            partial. Re-anchor on the parent's own body before trusting this claim (#454).
            """)
        XCTAssertEqual(Self.occurrences(of: "currentLatencyMode", in: above), 0, """
            The buffer mode is read ABOVE the leaf — inside `AudioInputPickerView` itself. That \
            body hosts Pickers, and a value read there registers the whole body as an observer: \
            every write tears down an open popover (10.76.41/50).
            """)
        XCTAssertEqual(Self.occurrences(of: "setLatencyMode", in: above), 0,
                       "the buffer is written from the parent body, not from the leaf's control.")
        // ⛔ Both counts above are ONE-SIDED: deleting the control entirely leaves them green.
        // Presence is asserted here so the section title ("share one leaf") is true of both
        // halves and not only of the absence half (#454).
        XCTAssertTrue(body.contains("bufferPicker"), """
            The buffer control is gone from the leaf. The zero-counts above still pass — \
            nothing is above the leaf because nothing exists — which is why they cannot stand \
            alone.
            """)
        XCTAssertTrue(body.contains("readout.floorText"), """
            The number the control moves is no longer rendered beside it, so the loop this \
            slice's whole argument rests on ("nobody has to believe a label") is broken.
            """)
        // ⛔ Scoped to the LEAF. The first version scanned the whole file while its message
        // said "the latency row acquired a POLL" — a timer in the parent, a different and
        // separately-argued concern, would have failed this test with the wrong cause named.
        XCTAssertFalse(body.contains("Timer.publish") || body.contains("TimelineView"), """
            The latency row acquired a POLL. The buffer changes only when someone presses the \
            control; a timer here rebuilds a view inside a Picker-hosting sheet on a schedule, \
            which is precisely the 10.76.41 freeze.
            """)
    }

    // MARK: - Helpers

    /// Every `.swift` file under `Sources/`, comment-stripped, keyed by repo-relative path.
    ///
    /// ⚠️ Repo-WIDE on purpose. A guard that names the three files it expects to be clean is
    /// green on the fourth, and the fourth is where the defect goes.
    private static func allSourceText() throws -> [(String, String)] {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            dir.deleteLastPathComponent()
            let sources = dir.appendingPathComponent("Sources")
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: sources.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            guard let walk = FileManager.default.enumerator(at: sources,
                                                            includingPropertiesForKeys: nil) else {
                break
            }
            var out: [(String, String)] = []
            let prefix = dir.path.hasSuffix("/") ? dir.path : dir.path + "/"
            for case let url as URL in walk where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                let relative = url.path.hasPrefix(prefix)
                    ? String(url.path.dropFirst(prefix.count)) : url.path
                out.append((relative, SourceText.codeOnly(text)))
            }
            guard !out.isEmpty else { break }
            return out
        }
        throw NSError(domain: "TheBufferPolicyHasADoorTests", code: 2, userInfo:
                        [NSLocalizedDescriptionKey:
                          "cannot walk Sources/ from #filePath — re-anchor (#454)."])
    }

    /// The brace-matched body of the declaration containing `anchor`, which must be unique.
    private static func body(after anchor: String, in text: String,
                             file: StaticString = #filePath,
                             line: UInt = #line) throws -> String {
        let count = occurrences(of: anchor, in: text)
        guard count == 1 else {
            XCTFail("`\(anchor)` occurs \(count) times, not once, so the extracted body is "
                    + "ambiguous and every negative below it is vacuous. Re-anchor (#408).",
                    file: file, line: line)
            throw NSError(domain: "TheBufferPolicyHasADoorTests", code: 3, userInfo: nil)
        }
        let start = try XCTUnwrap(text.range(of: anchor), "unreachable: counted 1, found 0.",
                                  file: file, line: line)
        guard let open = text[start.upperBound...].firstIndex(of: "{") else {
            XCTFail("no `{` follows `\(anchor)`.", file: file, line: line)
            throw NSError(domain: "TheBufferPolicyHasADoorTests", code: 4, userInfo: nil)
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
        XCTFail("braces never balance after `\(anchor)`.", file: file, line: line)
        throw NSError(domain: "TheBufferPolicyHasADoorTests", code: 5, userInfo: nil)
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
        throw NSError(domain: "TheBufferPolicyHasADoorTests", code: 1, userInfo:
                        [NSLocalizedDescriptionKey:
                          "cannot find \(path) walking up from #filePath — re-anchor (#454)."])
    }
}
