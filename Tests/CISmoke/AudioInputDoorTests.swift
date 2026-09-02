// AudioInputDoorTests.swift
// Echoel — #298. Blocking bundle.
//
// ⭐ THE DEFECT THIS FILE EXISTS FOR, stated as the founder hit it: "kann ich Live-Monitoring
// mit Feedback-Unterdrückung machen, und werden Audiointerfaces unterstützt?" The answer was
// "built, reachable, and it shows you an EMPTY list the first time you look".
//
// The mechanism is a two-step the code never closed:
//   1. Echoel's default audio session is `.playback`, deliberately — `.playAndRecord` makes iOS
//      drag a connected Bluetooth headset to the HFP call codec SYSTEM-WIDE, which would wreck
//      every other app's sound (`AudioConfiguration.configureAudioSession`, and the long comment
//      above it says exactly this).
//   2. `AVAudioSession.availableInputs` returns nothing in `.playback`.
// So the door opened, `refresh()` ran once in `.onAppear` against a `.playback` session, found
// zero ports, and rendered the empty state. Only turning monitoring ON upgrades the category —
// and nothing refreshed after that. The USB interface the performer just plugged in was
// invisible until they closed the sheet and opened it again.
//
// ⚠️ SCOPE, HONESTLY. This proves the three refresh points are WRITTEN. It cannot prove iOS
// actually publishes a given interface, that `setPreferredInput` succeeds for it, or that the
// monitor path is latency-acceptable — all of that is device-verify, and it is open.
//
// ⚠️ WHY A SOURCE SCAN: the picker's members are `private`, `@testable import` grants `internal`
// not `private`, and there is no simulator here. House pattern — see `SoundPanelReflowsTests`,
// `ChipStripScrollsToSelectionTests`, `SaveDoorNamingTests`.
//
// NOT DUPLICATED HERE: the duck maths itself (`gainReductionDB`) is already covered by
// `Tests/EchoelmusicTests/FeedbackGuardTests.swift`. That suite is NON-blocking (#208), so the
// coverage is real but it cannot redden a merge — stating that is part of the finding, not a
// reason to copy four assertions across.

import Foundation
import XCTest

final class AudioInputDoorTests: XCTestCase {

    private static let picker = "Sources/Echoelmusic/Studio/AudioInputPickerView.swift"
    private static let guardBrain = "Sources/Echoelmusic/Core/FeedbackGuard.swift"
    private static let engine = "Sources/Echoelmusic/Audio/AudioEngine.swift"

    // MARK: - The list is current when the user looks at it

    /// ⭐ THE ONE THAT MATTERS. Three refresh points, not one. A single `.onAppear` is exactly
    /// the shipped bug.
    func testTheInputListRefreshesOnAppearAfterTheToggleAndOnRouteChange() throws {
        let code = try codeLines(Self.picker).joined(separator: "\n")
        XCTAssertTrue(code.contains(".onAppear { inputs.refresh() }"), """
        the picker no longer refreshes on appear — the route can change between two openings \
        of this sheet, so the list would show whatever was true last time.
        """)
        // ⛔ BOUNDED, AND THE FIRST VERSION WAS NOT. It asserted `code.contains(
        // "routeChangeNotification")` over the WHOLE file — which proves the notification is
        // NAMED, not that anything happens when it fires. `.onReceive(…) { _ in }` with an
        // empty body would have passed. This file's own doc comment demands bounding for the
        // empty-state case eleven lines below and then failed to do it here.
        let observer = slice(of: code, from: ".onReceive(", to: "#endif")
        XCTAssertTrue(observer.contains("routeChangeNotification"), """
        the picker no longer observes `AVAudioSession.routeChangeNotification`. Plugging an \
        interface in WHILE this sheet is open is the normal case, not an edge case, and \
        without this the list silently keeps showing the old route.
        """)
        XCTAssertTrue(observer.contains("inputs.refresh()"), """
        the route-change observer exists but does not refresh the list — it names the \
        notification and does nothing with it, which is worse than not observing at all \
        because it reads as covered.
        """)
        XCTAssertTrue(observer.contains("receive(on:"), """
        the route-change observer lost its main-actor hop. AVAudioSession posts this from its \
        OWN thread, and `AudioInputManager` is `@MainActor` — but `onReceive`'s action \
        inherits `@MainActor` from this `@MainActor` View, so the compiler ASSUMES main and \
        emits no hop and no check. Removing `.receive(on:)` therefore buys a silent data race, \
        not a compile error. (The other `onReceive` sites in this repo omit it correctly: they \
        observe notifications Echoel itself posts from SwiftUI button actions.)
        """)
        // The toggle's setter must refresh too. Bounded to the setter so a stray `refresh()`
        // elsewhere in the file cannot satisfy this.
        let setter = slice(of: code, from: "set: {", to: "))")
        XCTAssertTrue(setter.contains("inputs.refresh()"), """
        the monitoring toggle no longer refreshes the input list. Turning monitoring on is the \
        moment `AudioConfiguration.upgradeToPlayAndRecord` changes the session category, and \
        that is the FIRST moment iOS publishes any input at all. Without a refresh here the \
        user sees an empty list immediately after doing the one thing that fills it.
        """)
    }

    /// The refresh points are worthless if the toggle stops upgrading the category — that is
    /// the other half of the same mechanism, and it lives in a different file.
    ///
    /// ⛔ THIS ASSERTION WAS ORPHANED BY #299 AND REDDENED THE BLOCKING BUNDLE. It matched the
    /// literal `upgradeToPlayAndRecord`; #299 replaced that call with
    /// `claimRecordRoute(.inputMonitoring)`, which upgrades via the owner set. Nothing about
    /// monitoring changed — the guard was pinned to a spelling instead of to the mechanism,
    /// so a rename of the mechanism read as a removal of it. Worth noting HOW it got through:
    /// `Xcode Compile Check` builds `Sources/` only, so a green compile gate cannot see a
    /// broken test assertion; only the CI/CD Pipeline runs this bundle.
    func testMonitoringStillUpgradesTheSessionCategory() throws {
        let code = try codeLines(Self.engine).joined(separator: "\n")
        XCTAssertTrue(code.contains("claimRecordRoute(.inputMonitoring)"), """
        `AudioEngine` no longer raises the audio session when monitoring starts. The mic \
        cannot be read in `.playback`: `inputNode` reports sampleRate 0 and monitoring silently \
        refuses to engage. (Since #299 the raise goes through the record-route owner set, so \
        the call to look for is `claimRecordRoute`, not `upgradeToPlayAndRecord` — and the \
        balance of claims against releases is guarded in `RecordRouteOwnershipTests`.)
        """)
    }

    /// ⛔ The empty state used to be the macOS sentence on every platform ("Input is managed by
    /// the system here"), which on iOS is false AND reads as a dead end in the one moment the
    /// user has something to do about it.
    ///
    /// ⚠️ BOUNDED TO `emptyStateText` ON PURPOSE. The obvious version asserted `#if os(iOS)`
    /// against the WHOLE file — which contains that token **five** times (the import guard, the
    /// nav-bar modifier, the route observer, `monitoringSection`, and this property), so it
    /// would have been green no matter what the empty state said. ⛔ The first version of this
    /// very sentence said "twice over": an undercounted count, in a paragraph about counting,
    /// in a repo whose recurring defect is exactly that. A whole-file `contains` for a token
    /// the file is full of is not a guard.
    func testTheEmptyStateExplainsWhyItIsEmptyOnIOS() throws {
        let code = try codeLines(Self.picker).joined(separator: "\n")
        let text = slice(of: code, from: "private var emptyStateText: String {", to: "\n    }")
        XCTAssertFalse(text.isEmpty, """
        `emptyStateText` is gone from \(Self.picker) — this test can no longer see the string it \
        guards, and a missing marker must fail loudly rather than pass on an empty slice.
        """)
        XCTAssertTrue(text.contains("#if os(iOS)"), """
        the empty state no longer distinguishes iOS from macOS. On macOS the input device \
        genuinely IS system-managed (HAL) and there is nothing to pick; on iOS this app picks it \
        via `setPreferredInput`, so the macOS sentence is simply false there.
        """)
        XCTAssertTrue(text.contains("Turn on live monitoring above"), """
        the iOS empty state no longer tells the user how to populate the list. An empty state \
        that does not say WHY it is empty sends the person away from the one action that fixes \
        it — which is exactly the shipped bug this slice closed.
        """)
    }

    // MARK: - The brain file may not out-claim its wiring

    /// ⭐ A TWO-WAY GUARD, and the direction that is easy to get backwards matters. This does
    /// NOT assert "the notch and the AEC must stay unwired" — wiring them is an improvement and
    /// a test must never block one. It asserts that the header and the wiring AGREE: wire it,
    /// and you must also delete the sentence that says it is not wired.
    func testFeedbackGuardHeaderMatchesWhatIsActuallyWired() throws {
        let header = try String(contentsOf: try repoRoot().appendingPathComponent(Self.guardBrain),
                                encoding: .utf8)

        // #848: the wiring proxy is `HowlDetector`, not `ringingBin` — production
        // switched to the preventive detector and `ringingBin` deliberately kept its
        // declaration with zero consumers (its own doc says so). A proxy symbol must
        // be the one production actually consumes, or this guard tests a memory.
        let notchWired = try symbolAppearsOutsideItsOwnFile("HowlDetector", ownFile: Self.guardBrain)
        let headerSaysNotchUnwired = header.contains("the NOTCH is NOT wired")
        XCTAssertNotEqual(notchWired, headerSaysNotchUnwired, """
        `FeedbackGuard.swift`'s header and the codebase disagree about the notch. \
        HowlDetector has a consumer: \(notchWired). Header still says it is unwired: \
        \(headerSaysNotchUnwired). If you wired it, delete that sentence in the same commit — \
        a header that under-claims is as misleading as one that over-claims, and this file's \
        whole ⛔ block exists because it over-claimed for months.
        """)

        let aecWired = try symbolAppearsOutsideItsOwnFile("setVoiceProcessingEnabled",
                                                          ownFile: Self.guardBrain)
        let headerSaysAECUnwired = header.contains("the AEC is NOT wired")
        XCTAssertNotEqual(aecWired, headerSaysAECUnwired, """
        `FeedbackGuard.swift`'s header and the codebase disagree about Apple's Voice-Processing \
        I/O. `setVoiceProcessingEnabled` present in Sources: \(aecWired). Header still says the \
        AEC is unwired: \(headerSaysAECUnwired).
        """)
    }

    // MARK: - Helpers

    /// True when `symbol` occurs in any `Sources/` Swift file other than `ownFile`. A
    /// declaration alone is not a consumer, which is the whole point.
    private func symbolAppearsOutsideItsOwnFile(_ symbol: String, ownFile: String) throws -> Bool {
        let root = try repoRoot()
        let sources = root.appendingPathComponent("Sources")
        let own = root.appendingPathComponent(ownFile).standardizedFileURL.path
        guard let walker = FileManager.default.enumerator(at: sources,
                                                          includingPropertiesForKeys: nil) else {
            return false
        }
        for case let url as URL in walker where url.pathExtension == "swift" {
            if url.standardizedFileURL.path == own { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n", omittingEmptySubsequences: false)
            where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                if line.contains(symbol) { return true }
            }
        }
        return false
    }

    /// The text between the first `from` and the next `to` after it. Returns "" when either
    /// marker is missing, so a caller's `contains` assertion fails loudly rather than passing
    /// on a slice that silently covered the whole file.
    private func slice(of text: String, from: String, to: String) -> String {
        guard let start = text.range(of: from) else { return "" }
        let rest = text[start.upperBound...]
        guard let end = rest.range(of: to) else { return "" }
        return String(rest[..<end.lowerBound])
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`, three levels up).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            // ⛔ ONE `"""` LITERAL, NOT A `+` CHAIN. `XCTSkip`'s message is
            // `@autoclosure () -> String?` — optional injection stacked on `+` overload
            // resolution, i.e. strictly MORE type-checker work than the plain `String`
            // autoclosure that hard-errored the blocking gate on `3379bb3`.
            throw XCTSkip("""
            source tree not present at \(sources.path) — this test inspects source text, so it \
            SKIPS rather than reporting a green it did not earn
            """)
        }
        return root
    }

    /// Every line of `path` that is not a whole-line comment. Load-bearing: this file's own
    /// ⛔ blocks quote the strings under test, so without the filter the assertions would pass
    /// on the explanation after the code it explains had been removed.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
    }
}
