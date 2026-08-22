// MIDIOutQualitySwitchesTests.swift
// Echoel — #713. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ WHAT THIS SLICE RESTORED, and why a guard belongs with it. `MIDIOutput.mpeEnabled` and
// `.expressionEnabled` gate LIVE code — the MPE zone RPN sent when the port opens, and the
// Glide/Slide/Press bytes that ride with each note-on out of `PianoRollModel`. Both lost their
// only control when the Tools grid was removed, so a player routing to a hardware rig got plain
// channel-1 notes and had no way to ask for anything else. CLAUDE.md has carried them as an open
// capability gap since ("gehören in die Routing-Fläche").
//
// ⛔ #713 DATED THAT REMOVAL "2026-07-02" AS A FACT AND THIS CLONE CANNOT SHOW IT (#714 finding
// F): the history is shallow and grafted, so `git log -S "mpeEnabled"` reports the flags as
// first appearing in one deploy commit. What IS measured is the present — no control existed
// anywhere before this slice — plus CLAUDE.md's register naming these two among the opt-ins the
// Tools grid took with it. The date is repo prose; the state is measurement.
//
// ⚠️ THE HALF THAT CAN GO WRONG QUIETLY IS THE DEPENDENCY, not the switches. `MIDIOutput`'s send
// path reads `if mpeEnabled, expressionEnabled`: per-note bend and pressure need one member
// channel per note, so expression ALONE changes nothing. An expression switch that can be turned
// on while MPE is off would move, persist, and do nothing — this repo's own lying-control class
// (#135/#164/#227), shipped into the surface whose stated rule is "a capability with no switch is
// not a feature". Claim 2 is therefore the sharpest claim in the file, and it is written to break
// if EITHER side of the pair moves: the engine's `if mpeEnabled, expressionEnabled` or the view's
// `.disabled(!midiOutMPE)`.
//
// ⚠️ WHAT THIS FILE CANNOT REACH, so the cover is not overread. It cannot instantiate
// `PatchbayView` or `MIDIOutput` (`@MainActor`, and the view's members are `private`), cannot
// prove a toggle is on screen, and cannot prove a byte leaves the device. It reads SOURCE TEXT
// plus the two pure `StudioDefault` values. That is weaker than a device run — the switches are
// NOT device-verified — and stronger than nothing.

import Foundation
import XCTest
@testable import Echoelmusic

final class MIDIOutQualitySwitchesTests: XCTestCase {

    private static let engine = "Sources/Echoelmusic/Audio/MIDIOutput.swift"
    private static let surface = "Sources/Echoelmusic/Studio/PatchbayView.swift"

    // MARK: - Claim 1 — the persisted contract

    /// Both switches must default OFF, or an install that never opens Routing silently changes
    /// what it sends to a rig. Off is also byte-for-byte the stream that shipped before #713.
    func testBothSwitchesDefaultOff() {
        XCTAssertFalse(StudioDefaultKeys.midiOutMPE.value,
                       "the MPE layout now defaults ON. Every fresh install would start spreading "
                       + "notes across 15 channels; a plain synth on channel 1 would hear a "
                       + "fraction of the take.")
        XCTAssertFalse(StudioDefaultKeys.midiOutExpression.value,
                       "per-note expression now defaults ON.")
        XCTAssertEqual(StudioDefaultKeys.midiOutMPE.key, "midi.out.mpe",
                       "the MPE key moved. A stored preference from an older install can no "
                       + "longer be found, so the switch silently resets for everyone who set it.")
        XCTAssertEqual(StudioDefaultKeys.midiOutExpression.key, "midi.out.expression",
                       "the expression key moved — same consequence as above.")
    }

    // MARK: - Claim 2 — the dependency, from BOTH ends

    /// The engine gates expression on MPE, and the surface must gate the switch the same way.
    /// One assertion per end, because the two can drift independently and the repair differs.
    func testExpressionIsGatedOnMPEInEngineAndSurface() throws {
        let engine = try codeOf(Self.engine)
        XCTAssertTrue(engine.contains("if mpeEnabled, expressionEnabled"), """
            `MIDIOutput` no longer gates expression on MPE.

            If that gate was REMOVED because expression now works standalone, delete the \
            `.disabled(!midiOutMPE)` in \(Self.surface) and the dependency copy in the same \
            commit — the switch would then be lying in the other direction, refusing something \
            that works. If it merely moved or was respelled, re-anchor this claim on the new form.
            """)

        let surface = try codeOf(Self.surface)
        XCTAssertTrue(surface.contains(".disabled(!midiOutMPE)"), """
            The per-note expression switch is no longer disabled while MPE is off, but the engine \
            still reads `if mpeEnabled, expressionEnabled`.

            That is a control a player can turn on, that persists, and that changes nothing — the \
            lying-control class this surface's own `networkMIDISection` note argues against. \
            Restore the gate, or remove the engine's gate and this claim together.
            """)
    }

    // MARK: - Claim 3 — one owner

    /// The flags are written in exactly one file. A view assigning `mpeEnabled` directly would
    /// make the surface a second lifecycle owner — the mistake BLE-3 had to undo when the
    /// patchbay was starting and stopping a heart-rate strap behind the player's back.
    /// ⛔ #713 WROTE THIS AS `contains("mpeEnabled =") && !contains("==")` AND IT MISSED THE
    /// MOST LIKELY REGRESSION OF ALL (#714 finding C): `Toggle(isOn: $midiOut.mpeEnabled)` via
    /// `@Bindable` — the canonical SwiftUI second-owner shape, and the exact thing this claim
    /// exists to stop — contains no `mpeEnabled =` at all. So did `.toggle()`, so did a missing
    /// or doubled space, and the blanket `!contains("==")` exempted any real assignment that
    /// happened to share a line with an unrelated comparison. Now two regexes: an assignment
    /// that is not `==`/`!=`/`<=`/`>=`, and the binding/`toggle()` aliases.
    func testNothingOutsideTheEngineAssignsTheFlags() throws {
        let flags = "(mpeEnabled|expressionEnabled)"
        // `\s*=(?!=)` rejects `expressionEnabled == true` on its own, so the old blanket `==`
        // exemption — and its hole — is gone with it.
        let assignment = "(?<![=!<>])\\b" + flags + "\\s*=(?!=)"
        let alias = "[$.]" + flags + "\\b\\s*\\.toggle\\(\\)"
        let binding = "\\$[a-zA-Z_][a-zA-Z0-9_]*\\." + flags + "\\b"

        let offenders = try swiftFilesUnderSources()
            .filter { $0.key != Self.engine }
            .filter { file in
                let code = SourceText.codeOnly(file.value)
                return [assignment, alias, binding].contains { pattern in
                    code.range(of: pattern, options: .regularExpression) != nil
                }
            }
            .map(\.key)
            .sorted()

        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.joined(separator: ", ")) assigns a MIDI-out flag directly.

            Everything must go through `MIDIOutput.applyOutputPreferences()`, which reads the \
            persisted keys — that is what keeps the switch and the live engine from disagreeing, \
            and it is the shape `MIDIInput.applyNetworkSessionPreference()` established.
            """)
    }

    // MARK: - Claim 4 — the owner is reached from both ends

    /// `applyOutputPreferences()` is useless without callers, and it needs BOTH: the port-open
    /// path so a stored preference is in force before a byte can leave, and the switches so a
    /// change takes effect now.
    ///
    /// ⛔ THIS WAS NAMED `…AtLaunchAndFromTheSwitches` AND "launch" IS NOT THE MECHANISM (#714
    /// finding E). `startIfNeeded()` runs from `enabled`'s didSet, and `enabled` is only set by
    /// `applyRouting()` from the persisted `midi.out` route — with that route off at launch,
    /// this never runs. Harmless (nothing can be sent then), but #374: a name must describe the
    /// path the code takes.
    func testTheOwnerIsCalledWhenThePortOpensAndFromTheSwitches() throws {
        let engine = try codeOf(Self.engine)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        let launchCalls = engine.contains { line in
            line.contains("applyOutputPreferences()") && !line.contains("func applyOutputPreferences")
        }
        XCTAssertTrue(launchCalls, """
            `applyOutputPreferences()` has no caller inside `MIDIOutput` any more, so a stored \
            preference no longer survives a relaunch — the switches would appear set and the \
            engine would send the default stream.
            """)

        // ⛔ #713 ASSERTED AN EXACT COUNT OF 2 HERE, WHICH FORBIDS CORRECT WORK (#364/#714
        // finding D): a third legitimate call site — an `.onAppear` resync, a third out-quality
        // switch — would turn this red under a message about "BOTH switches". Worse, the repair
        // for the RPN defect #714 fixes adds calls, so the guard stood in front of it. Assert
        // the two toggles individually: stricter about what matters, open-ended about the rest.
        let surface = try codeOf(Self.surface)
        for flag in ["midiOutMPE", "midiOutExpression"] {
            XCTAssertTrue(
                surface.contains(".onChange(of: \(flag)) { _, _ in midiOut.applyOutputPreferences() }"), """
                The `\(flag)` toggle no longer applies through the owner.

                Each switch needs its own `.onChange` calling \
                `midiOut.applyOutputPreferences()` — otherwise it moves the stored key and the \
                live engine keeps the old value until the port next opens.
                """)
        }
    }

    // MARK: - Claim 6 — the placement the RPN correctness rests on

    /// ⭐ THE CLAIM #713 ARGUED FOR IN PROSE AND LEFT UNGUARDED (#714 finding E). Its headline
    /// reason was that `applyOutputPreferences()` must run BEFORE `isReady = true`, so that
    /// `mpeEnabled`'s `didSet` falls into `sendMPEConfiguration()`'s own `guard isReady` and the
    /// zone RPN is announced by the line AFTER the port exists. Claim 4 only asks that some line
    /// calls it — moving the call below `isReady = true` would leave claim 4 green and double
    /// every announce on the first open.
    ///
    /// Asserted as an ORDER, not a line number: line numbers in this repo go stale on the next
    /// insertion, an order does not.
    func testThePreferencesAreReadBeforeThePortIsMarkedReady() throws {
        let lines = try codeOf(Self.engine)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        let apply = lines.firstIndex { line in
            line.contains("applyOutputPreferences()") && !line.contains("func applyOutputPreferences")
        }
        let ready = lines.firstIndex { $0.contains("isReady = true") }

        // #367: anchor both, or a rename lets the comparison below pass on nothing.
        let applyIndex = try XCTUnwrap(apply, "no call to `applyOutputPreferences()` in \(Self.engine)")
        let readyIndex = try XCTUnwrap(ready, "no `isReady = true` in \(Self.engine) — the port "
                                       + "lifecycle was rewritten; re-anchor this claim on it.")

        XCTAssertLessThan(applyIndex, readyIndex, """
            `applyOutputPreferences()` now runs at or after `isReady = true`.

            With the port already marked ready, `mpeEnabled`'s `didSet` sends the MPE zone RPN \
            itself, and the line after `isReady = true` sends it a second time on the very first \
            open. Move the call back above the port setup.
            """)
    }

    // MARK: - Claim 5 — the capability being switched is real

    /// ⭐ THE COUNTERWEIGHT, and the reason this file is not just bookkeeping: a switch over a
    /// flag nothing reads is the defect, not the fix. `expressionEnabled` must still reach a
    /// consumer OUTSIDE its own file. Today that consumer is `PianoRollModel` (in
    /// `PianoRollView.swift`, which kept the model when #475 deleted the view).
    ///
    /// Goes red the day the last consumer disappears — at which point the honest move is to
    /// remove the switch WITH it, not to leave a control over dead code.
    func testTheExpressionFlagStillReachesALiveSender() throws {
        let readers = try swiftFilesUnderSources()
            .filter { $0.key != Self.engine }
            .filter { SourceText.codeOnly($0.value).contains("expressionEnabled") }
            .map(\.key)
            .sorted()

        XCTAssertFalse(readers.isEmpty, """
            Nothing outside `MIDIOutput` reads `expressionEnabled` any more. The Routing switch \
            added by #713 now sits over a flag no sender consults — exactly the shape it was \
            written to remove, one level in. Delete the switch, its `StudioDefaultKeys` entry and \
            this file together, or restore the sender.
            """)
    }

    // MARK: - Helpers

    private func codeOf(_ path: String) throws -> String {
        SourceText.codeOnly(try rawFile(path))
    }

    private func rawFile(_ path: String) throws -> String {
        try String(contentsOf: try repoRoot().appendingPathComponent(path), encoding: .utf8)
    }

    /// Every tracked-looking `.swift` under `Sources/Echoelmusic`, keyed by repo-relative path.
    /// `enumerator(atPath:)` yields relative SUBPATHS, so the key is built by prefixing.
    private func swiftFilesUnderSources() throws -> [String: String] {
        let root = try repoRoot()
        let base = root.appendingPathComponent("Sources/Echoelmusic")
        guard let walk = FileManager.default.enumerator(atPath: base.path) else { return [:] }
        var out: [String: String] = [:]
        for case let sub as String in walk where sub.hasSuffix(".swift") {
            let url = base.appendingPathComponent(sub)
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                out["Sources/Echoelmusic/" + sub] = text
            }
        }
        return out
    }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                Source tree not reachable from the test bundle — skipping rather than reporting \
                a green this file did not earn.
                """)
        }
        return root
    }
}
