// ControllerEventDrainIsPushedTests.swift
// Echoel — #317. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ WHAT BROKE, AND WHY IT IS NOT A "TUNING" BUG: an external keyboard's note reached the
// bus immediately (`MIDIBusPublisher` → `EngineBus.publish(controller:)`) and then SAT there
// until `BioReactiveSynthVoice`'s 100 ms `PollingLoop` came around. So a note was 0–100 ms
// late depending on where in that window it landed — and the varying part is the damaging
// one. A constant 100 ms is a latency a player adapts to; 100 ms of JITTER means the same
// phrase plays back unevenly every time, which is the difference between an instrument that
// can be played and one that cannot.
//
// #317 makes the drain PUSHED: `EngineBus.onControllerEventEnqueued` fires inside the
// main-actor hop `publish(controller:)` already performed for `latestControllerEvent`, and
// the subscriber installs its drain there. The 100 ms tick keeps its own drain as a backstop
// for anything enqueued while nothing was subscribed.
//
// THE PAIRING THIS FILE PINS — all three, because any one alone silently rots:
//
//   1. the hook is DECLARED and actually INVOKED in `publish(controller:)`. A declared-but
//      -uncalled hook is the worst outcome: the subscriber installs a closure that never
//      runs, everything compiles, and the latency quietly comes back.
//   2. EXACTLY ONE file in `Sources/` assigns it. `controllerEvents` is a single-producer/
//      single-CONSUMER lock-free queue; a second assignment is a second consumer, and the
//      two would STEAL events from each other — half the notes to one voice, half to the
//      other. `BioReactiveSynthVoice.applyBioFrame`'s own doc comment warns about exactly
//      this for the rack bio units.
//   3. the subscriber both SETS it on subscribe and CLEARS it on stop. Without the clear, a
//      stopped voice keeps consuming, and the next `start` becomes that illegal second
//      setter.
//
// ⚠️ WHAT THIS FILE CANNOT REACH: it cannot start an engine, publish a real MIDI event, or
// measure a millisecond. It reads SOURCE TEXT. The actual latency claim is device-only —
// it needs a keyboard and a founder's hands, and nothing here should be read as proving it.

import Foundation
import XCTest

final class ControllerEventDrainIsPushedTests: XCTestCase {

    private static let hook   = "onControllerEventEnqueued"
    private static let bus    = "Sources/Echoelmusic/Core/EngineBus.swift"
    private static let voice  = "Sources/Echoelmusic/Tools/BioReactiveSynthVoice.swift"

    func testTheHookIsDeclaredAndActuallyCalledWhenAnEventIsPublished() throws {
        let code = try source(Self.bus)
        XCTAssertTrue(code.contains("public var \(Self.hook)"), """
            `EngineBus.\(Self.hook)` is gone. External MIDI then depends again on \
            `BioReactiveSynthVoice`'s 100 ms poll tick for its timing — 0–100 ms of jitter \
            on every note (#317). If this was removed on purpose, remove its setter in \
            `BioReactiveSynthVoice` in the SAME commit and delete this file with them.
            """)
        XCTAssertTrue(code.contains("self.\(Self.hook)?()"), """
            `EngineBus.\(Self.hook)` is declared but never invoked. That is worse than not \
            having it: the subscriber installs a drain closure, everything compiles, and \
            notes silently wait for the poll tick again. It must be called inside \
            `publish(controller:)`'s existing main-actor hop — and AFTER \
            `latestControllerEvent` is assigned, so a consumer reading that snapshot during \
            its drain sees this event and not the previous one.
            """)
    }

    /// The single-consumer contract, expressed as the only thing a text guard can actually
    /// see: how many files assign the hook.
    func testExactlyOneFileInstallsTheDrainHook() throws {
        let assigning = try swiftFilesUnderSources()
            .filter { try String(contentsOf: $0, encoding: .utf8).contains("\(Self.hook) =") }
            .map(\.lastPathComponent)
            .sorted()

        XCTAssertEqual(assigning, ["BioReactiveSynthVoice.swift"], """
            \(assigning.count) file(s) assign `\(Self.hook)`: \(assigning.joined(separator: ", ")).
            `EngineBus.controllerEvents` is single-CONSUMER. Two installers means two \
            drains racing over one queue, so each would get roughly half the notes and \
            neither would sound right — the failure `applyBioFrame(from:)` already warns \
            about for rack bio units. If ownership genuinely moved to another type, update \
            the expected name here in the same commit; do not add a second one.
            """)
    }

    func testTheSubscriberBothInstallsAndReleasesTheHook() throws {
        let code = try source(Self.voice)
        XCTAssertTrue(code.contains("bus.\(Self.hook) = { [weak self, weak bus]"), """
            The drain hook is not installed on subscribe, or no longer captures both ends \
            weakly. The bus STORES this closure, so a strong capture of the voice or of the \
            bus keeps both alive for the process lifetime.
            """)
        XCTAssertTrue(code.contains("bus?.\(Self.hook) = nil"), """
            `stop()` no longer releases the drain hook. A stopped voice keeps consuming \
            controller events, and the next `start(subscribing:)` becomes the second setter \
            of a single-consumer hook — the exact condition the test above exists to stop.
            """)
    }

    // MARK: - helpers

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

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(path), encoding: .utf8)
    }

    private func swiftFilesUnderSources() throws -> [URL] {
        let dir = try repoRoot().appendingPathComponent("Sources/Echoelmusic")
        guard let walk = FileManager.default.enumerator(at: dir,
                                                        includingPropertiesForKeys: nil) else {
            throw XCTSkip("could not enumerate Sources/Echoelmusic")
        }
        return walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
