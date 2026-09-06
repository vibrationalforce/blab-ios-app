// ThePlugInInvitesButNeverArmsTests.swift
// Echoel — plugging in a USB mic/interface invites, and only invites. #596.
//
// WHAT THIS GUARDS. The founder's "automatische Erkennung" ships as an INVITATION,
// never an auto-arm: `PlugInInvitation` (pure brain) decides which freshly plugged
// port deserves a line, `RoutePlugInWatcher` listens app-wide and exposes the name,
// and the `PlugInInviteRow` leaf in the transport column renders it — its tap opens
// the EXISTING `showInput` sheet (slot reuse). The two red lines this must never
// cross, both already paid for: no auto-arm (#277 — nothing listens until the user
// asks) and no category read-back/upgrade on plug-in (#299 — upgrading drags other
// apps' Bluetooth audio to HFP).
//
// ⚠️ HONEST LIMITS. 7 tests, 23 `XCTAssert*` statements (hand-counted per test,
// 5+4+2+2+4+3+3 — the first hand-count said 24, the recurring §3 defect, corrected
// by re-counting each test body). Tests 1–4 are END-TO-END BEHAVIOUR on the shipped pure brain;
// tests 5–7 are SOURCE-TEXT JOINS (the watcher drives AVAudioSession and the row is
// a private View — neither runs honestly in a test host). What no test here can
// prove: that iOS actually fires `.newDeviceAvailable` for a given device under
// `.playback` — the pure-USB-mic gap is documented in PlugInInvitation.swift — and
// how the line reads on screen. Device probe (NEEDS-FOUNDER-VERIFY: plug a USB-C
// interface in with the app open; the line must appear, its tap must open the input
// sheet, and NOTHING may start listening by itself).
//
// ⭐ GRADING (§3). This file names `PlugInInvitation` and `RoutePlugInWatcher`, both
// created by this same commit — against the parent tree it DOES NOT COMPILE, so no
// assertion has a verdict there; the brain was hand-transcribed in Python against
// the worktree instead (all 13 driven assertions reproduce — the review caught this
// number as "14", one paragraph after the count correction above; §3 again). Join assertions are
// FORWARD guards; test 4 and the classifier joins in test 1 are COUNTERWEIGHTS in
// spirit (they pin the REUSE of `AudioInputClassifier`, #416 — the one pre-existing
// symbol here, unchanged by this commit). Stripper: all 10 source needles measured
// raw vs stripped on the worktree — TRAGEND (1 of 10 verdicts flips): the
// `availableInputs == 0` scan. The watcher's own header EXPLAINS why it refuses to
// read `availableInputs`, so the word occurs once in prose; unstripped, this
// guard's zero-count would be red on correct code — the #364 shape — and the
// stripper is what makes "the CODE never reads it" assertable at all. (The first
// version of this paragraph claimed different numbers BEFORE measuring — the exact
// defect §2 warns about; these are from the transcription script's output.)

import Foundation
import XCTest
@testable import Echoelmusic

final class ThePlugInInvitesButNeverArmsTests: XCTestCase {

    private typealias Port = PlugInInvitation.PortDescription

    // MARK: - 1–4. The brain (END-TO-END, pure)

    /// A deliberate plug (USB interface, wired headset mic, line-in) invites; the
    /// routine or built-in kinds never do. The classification is NOT restated here —
    /// the brain must agree with `AudioInputClassifier` (#416), so the expectations
    /// are phrased through the same classifier the app ships.
    func testDeliberatePlugsInviteAndRoutineOnesDoNot() {
        XCTAssertEqual(
            PlugInInvitation.portName(reasonIsNewDevice: true,
                                      ports: [Port(type: "USBAudio", name: "Scarlett 2i2",
                                                   isInput: true)]),
            "Scarlett 2i2")
        // "MicrophoneWired" is the ACTUAL `AVAudioSession.Port.headsetMic` rawValue —
        // the review found the classifier matching only guessed names ("HeadsetMicrophone"),
        // so this assertion drives the REAL string iOS sends, not the phantom.
        XCTAssertEqual(
            PlugInInvitation.portName(reasonIsNewDevice: true,
                                      ports: [Port(type: "MicrophoneWired",
                                                   name: "EarPods", isInput: true)]),
            "EarPods", "a wired headset mic is a deliberate plug")
        XCTAssertNil(
            PlugInInvitation.portName(reasonIsNewDevice: true,
                                      ports: [Port(type: "BluetoothA2DPOutput",
                                                   name: "AirPods", isInput: false)]),
            "Bluetooth pairing is routine listening, not an instrument gesture — "
            + "and BT monitoring is the high-latency path the sheet already warns about")
        XCTAssertNil(
            PlugInInvitation.portName(reasonIsNewDevice: true,
                                      ports: [Port(type: "MicrophoneBuiltIn",
                                                   name: "iPhone Mikrofon", isInput: true)]),
            "the built-in mic is always there — it cannot be freshly plugged")
        XCTAssertNil(
            PlugInInvitation.portName(reasonIsNewDevice: false,
                                      ports: [Port(type: "USBAudio", name: "Scarlett 2i2",
                                                   isInput: true)]),
            "only a NEW-device route change invites — a route torn down or a category "
            + "shuffle must not resurface the line")
    }

    /// An interface that shows both halves is named by its INPUT half, and a
    /// nameless port falls back to a generic per kind — never an empty invitation.
    func testInputHalfWinsAndNamelessPortsGetGenerics() {
        XCTAssertEqual(
            PlugInInvitation.portName(
                reasonIsNewDevice: true,
                ports: [Port(type: "USBAudio", name: "2i2 Out", isInput: false),
                        Port(type: "USBAudio", name: "2i2 Mic", isInput: true)]),
            "2i2 Mic", "inputs are preferred — the mic half is what the invitation is about")
        XCTAssertEqual(
            PlugInInvitation.portName(reasonIsNewDevice: true,
                                      ports: [Port(type: "USBAudio", name: "",
                                                   isInput: false)]),
            "USB audio device")
        XCTAssertEqual(
            PlugInInvitation.portName(reasonIsNewDevice: true,
                                      ports: [Port(type: "LineIn", name: "",
                                                   isInput: true)]),
            "Wired input")
        XCTAssertNil(PlugInInvitation.portName(reasonIsNewDevice: true, ports: []),
                     "an empty route change carries nothing to invite for")
    }

    /// An interface plugged while headphones/BT are also in the route: the one
    /// qualifying port wins, the surrounding routine ports change nothing.
    func testAMixedRouteInvitesOnlyForTheQualifyingPort() {
        let mixed = [Port(type: "BluetoothA2DPOutput", name: "AirPods", isInput: false),
                     Port(type: "USBAudio", name: "Volt 2", isInput: true),
                     Port(type: "MicrophoneBuiltIn", name: "iPhone Mikrofon", isInput: true)]
        XCTAssertEqual(PlugInInvitation.portName(reasonIsNewDevice: true, ports: mixed),
                       "Volt 2")
        XCTAssertNil(
            PlugInInvitation.portName(
                reasonIsNewDevice: true,
                ports: [Port(type: "BluetoothA2DPOutput", name: "AirPods", isInput: false),
                        Port(type: "MicrophoneBuiltIn", name: "iPhone Mikrofon",
                             isInput: true)]),
            "the same route without the interface invites for nothing")
    }

    /// The unknown-future-port edge rides the classifier's substring fallback: a
    /// port type nobody spelled out still classifies, and the brain follows it.
    func testUnknownPortTypesFollowTheClassifierFallback() {
        XCTAssertEqual(
            PlugInInvitation.portName(reasonIsNewDevice: true,
                                      ports: [Port(type: "USBAudioDeviceFuture",
                                                   name: "NextBox", isInput: true)]),
            "NextBox", "the classifier's USB substring fallback must reach the brain")
        XCTAssertNil(
            PlugInInvitation.portName(reasonIsNewDevice: true,
                                      ports: [Port(type: "BluetoothFutureProfile",
                                                   name: "Buds", isInput: true)]),
            "the Bluetooth substring fallback must keep future BT profiles out")
    }

    // MARK: - 5–7. The wiring joins (SOURCE-TEXT)

    /// The watcher never arms and never touches the session category: no
    /// `setInputMonitoring`, no `startRecording`, no `setCategory`, no
    /// `availableInputs` (empty under `.playback`; reading it invites the #299
    /// category-upgrade temptation this design refuses).
    func testTheWatcherOnlyWatches() throws {
        let watcher = try source("Sources/Echoelmusic/Studio/RoutePlugInWatcher.swift")
        XCTAssertEqual(codeOccurrences(of: "setInputMonitoring", in: watcher), 0,
                       "the watcher must NEVER arm monitoring — the invitation's tap "
                       + "opens the sheet, and arming stays a consent step inside it (#277)")
        XCTAssertEqual(codeOccurrences(of: "startRecording", in: watcher), 0)
        XCTAssertEqual(codeOccurrences(of: "setCategory", in: watcher), 0,
                       "no silent category upgrade on plug-in — the #299 line")
        XCTAssertEqual(codeOccurrences(of: "availableInputs", in: watcher), 0,
                       "the decision uses only what the route change carries under "
                       + ".playback — availableInputs is empty there and populating it "
                       + "means upgrading the category")
    }

    /// ⛔ RETRACTED AND INVERTED BY #1024 (2026-09-06, founder order). This method asserted
    /// that `PlugInInviteRow(watcher: plugInWatcher) { showInput = true }` was mounted once
    /// in the transport column, that `EchoelStudioView` owned the watcher, and that
    /// `plugInWatcher.start()` ran once from the root `.onAppear`. All three were true and
    /// all three are now GONE: the invitation banner was one of the three microphone doors
    /// the founder removed ("das mit dem Audio Input Monitoren klappt immer noch nicht also
    /// fliegt das raus"). Left as it stood, this method would be a RED claim on a CORRECT
    /// tree — the tangle his second sentence warned against — so it is inverted rather than
    /// deleted, and the original three needles are quoted above so a re-door can restore
    /// them verbatim instead of re-deriving them.
    ///
    /// ⭐ THE LAW THAT SURVIVES ITS ROW, and it is the reason the third needle existed: a row
    /// that is CONDITIONALLY EMPTY cannot start its own watcher from its own `.onAppear`,
    /// because on a quiet route the row never appears. The watcher starts from the ROOT.
    /// Whoever re-doors this hits that trap again otherwise.
    func testTheRowIsNoLongerMountedAfterTheFounderRemovedTheMicDoors() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        for needle in ["PlugInInviteRow(watcher: plugInWatcher) { showInput = true }",
                       "@State private var plugInWatcher = RoutePlugInWatcher()",
                       "plugInWatcher.start()"] {
            XCTAssertEqual(codeOccurrences(of: needle, in: studio), 0, """
                `\(needle)` is back in EchoelStudioView. THIS IS NOT AUTOMATICALLY A BUG — \
                the founder may have asked for the microphone doors back. But it IS his \
                decision (#1024), and restoring it means restoring this method to its \
                pre-#1024 form (the three needles are quoted in the doc comment above) and \
                pulling the prose homes named in `TheMicrophoneHasNoDoorTests` along in the \
                SAME commit.
                """)
        }
    }

    /// COUNTERWEIGHT to the method above: #1024 removed the MOUNT, not the machinery. Without
    /// this, the inverted claim would also pass on a tree where somebody "finished the job"
    /// by deleting the watcher and the row — a far bigger and far less reversible change than
    /// the one the founder asked for, and one that would strand the four pure-logic claims at
    /// the top of this file with nothing to describe.
    func testTheWatcherAndTheRowStillExist() throws {
        let watcher = try source("Sources/Echoelmusic/Studio/RoutePlugInWatcher.swift")
        XCTAssertEqual(codeOccurrences(of: "struct PlugInInviteRow: View", in: watcher), 1,
                       "PlugInInviteRow is gone. #1024 unmounted the row; deleting it turns "
                       + "a three-call-site re-door into a rebuild.")
        XCTAssertEqual(codeOccurrences(of: "class RoutePlugInWatcher", in: watcher), 1,
                       "RoutePlugInWatcher is gone. It is the subject of the four "
                       + "`PlugInInvitation` claims above and of the only-watches claim below.")
    }

    /// Freeze law: the observable read (`invitePortName`) stays inside the leaf's
    /// own file; the studio body only passes the reference.
    func testTheInviteReadStaysInTheLeaf() throws {
        let studio = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertEqual(codeOccurrences(of: "invitePortName", in: studio), 0,
                       "the studio body must not read the watcher's observable state — "
                       + "the leaf reads it (10.76.41/50)")
        let watcher = try source("Sources/Echoelmusic/Studio/RoutePlugInWatcher.swift")
        XCTAssertEqual(codeOccurrences(of: "watcher.invitePortName", in: watcher), 1,
                       "exactly one view-side read, in PlugInInviteRow's body")
        XCTAssertEqual(codeOccurrences(of: "struct PlugInInviteRow: View", in: watcher), 1,
                       "the leaf lives beside its watcher — the AudioDegradedRow shape")
    }

    // MARK: - helpers (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct InviteAnchorMissing: Error { let reason: String }

    private func codeOccurrences(of needle: String, in stripped: String) -> Int {
        stripped.components(separatedBy: needle).count - 1
    }

    private func source(_ relativePath: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw InviteAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
