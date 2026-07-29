// OneStartControlTests.swift
// Echoel — there is ONE button that starts the instrument, and it is a labelled one.
//
// THE ASK (founder 2026-07-29, with a screenshot): *"Ich hab jetzt hier 3 Knöpfe zum Start
// drücken könnte man das zu einem zusammenfassen?"* — three controls on one screen all began
// the same bio-generative session:
//   1. the header pulse pill (tap → `.echoelToggleBio`),
//   2. the transport ▶ (posted the SAME notification whenever nothing was composed),
//   3. the full-width "Create from Within" on the front plate.
// Two of them showed a different truth while doing it: the pill renders CAMERA state
// (`cameraRPPG.isRunning`) and the ▶ renders `transport.isPlaying`, so on the same screen
// three controls for one action could disagree about whether it had happened.
//
// #234 keeps the labelled one. The pill went back to being a monitor (its tap opens the Bio
// panel, which is also the first time that panel has been reachable without a long-press),
// and ▶ is now only on screen WHILE a session runs, where it is the music transport — drop
// the music without dropping a pulse lock that costs ~20 s to re-acquire.
//
// WHY A TEST AND NOT JUST A COMMENT: this is the SECOND time the founder has asked for this
// ("zu viele Play Knöpfe, einer reicht", 2026-07-15). That round moved the duplicate instead
// of removing it, and the count grew back. A comment does not fail; this does.
//
// WHAT THIS CANNOT PROVE: that the one remaining button is reachable, legible, or works — it
// pins the COUNT and the absence of the chrome wire, nothing about rendering. And it is not
// a claim that no other code path can begin a bio session: the Bio panel's own "start pulse"
// row and the Siri/Shortcuts inbox both call `startBiofeedback()` directly, deliberately.
// Those are one level deeper than the front plate, which is exactly where the founder's
// complaint was not.

import XCTest

final class OneStartControlTests: XCTestCase {

    /// Every `.swift` file under `Sources/`, with whole-line comments dropped. Comments are
    /// stripped because the removal is DOCUMENTED in three places by name — a naive search
    /// would find the epitaphs and fail on the very thing it is checking for.
    private func sourceLines() throws -> [(file: String, line: Int, text: String)] {
        let root = try repoRoot().appendingPathComponent("Sources")
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        // Labels declared HERE, not only on the return type: `[(String, Int, String)]` and
        // `[(file: String, line: Int, text: String)]` are distinct types, and Array does not
        // convert between them — the mismatch is a compile error, not a warning.
        var out: [(file: String, line: Int, text: String)] = []
        var scanned = 0
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            scanned += 1
            for (i, raw) in text.components(separatedBy: .newlines).enumerated() {
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                guard !trimmed.hasPrefix("//") else { continue }
                out.append((url.lastPathComponent, i + 1, raw))
            }
        }
        XCTAssertGreaterThan(scanned, 250,
                             "Only \(scanned) Swift files scanned — every search below would "
                             + "pass vacuously on a tree it never read.")
        return out
    }

    /// ⛔ THE REGRESSION GUARD. Add a second control that starts the session and this goes red.
    ///
    /// The front plate's Start/Stop button is the only invoker of `toggleBiofeedback()`. The
    /// declaration itself is excluded — it is the definition, not a caller.
    func testExactlyOneControlInvokesTheFrontPlateSessionToggle() throws {
        let invokers = try sourceLines().filter {
            $0.text.contains("toggleBiofeedback()") && !$0.text.contains("func toggleBiofeedback")
        }
        XCTAssertEqual(invokers.count, 1,
                       "Expected exactly ONE control to start/stop the session, found "
                       + "\(invokers.count): "
                       + invokers.map { "\($0.file):\($0.line)" }.joined(separator: ", ")
                       + ". The founder has asked twice for one Start button (2026-07-15, "
                       + "2026-07-29). If a new control genuinely needs to begin a session, "
                       + "that is a founder decision, not a merge.")
    }

    /// The chrome→studio start WIRE is gone, not merely unused. `echoelToggleBio` let the
    /// header and the transport bar begin a session without owning any of its state; while
    /// the name exists, re-adding a fourth start button is one line and leaves no trace in
    /// the view that starts it. Matched on the raw notification STRING, which no epitaph
    /// comment spells out — so this stays honest even where the symbol name is discussed.
    func testNoChromeNotificationCanStartTheSession() throws {
        let posts = try sourceLines().filter { $0.text.contains("echoel.toggleBio") }
        XCTAssertTrue(posts.isEmpty,
                      "`echoel.toggleBio` is back at "
                      + posts.map { "\($0.file):\($0.line)" }.joined(separator: ", ")
                      + ". Chrome that starts the session is what produced three Start "
                      + "buttons; if a chrome control must start it again, re-add the "
                      + "notification WITH that control, never ahead of it.")
    }

    /// ⛔ THE OTHER REGRESSION GUARD, and it exists because the claim it protects was already
    /// shipped once while FALSE.
    ///
    /// The transport ■ is kept on the argument that it stops the MUSIC without ending the
    /// bio session — the pulse lock costs ~20 s to re-acquire, so that difference is the
    /// button's entire justification. It only holds if something actually REQUESTS a
    /// playback-only stop: `TransportTransition.decide` returns `.endSession` otherwise.
    ///
    /// From 2026-07-26 (the piano roll's door removed) to 2026-07-29 nothing did, and the
    /// founder's device log 2475 shows the consequence — `stop source: transport-bar ■` at
    /// 828.182, `stopEverything(transport-stopped)` 14 ms later. A second full Stop wearing
    /// a different glyph.
    ///
    /// `PianoRollView.swift` is excluded deliberately: it holds both the declaration and the
    /// roll's own pause button, and that view has had no door since 2026-07-26. Counting it
    /// would let this test go green on a producer no user can reach — which is precisely the
    /// state it is meant to detect.
    func testThePlaybackOnlyStopHasAReachableProducer() throws {
        let producers = try sourceLines().filter {
            $0.text.contains("requestPlaybackOnlyStop()") && $0.file != "PianoRollView.swift"
        }
        XCTAssertFalse(producers.isEmpty,
                       "Nothing outside PianoRollView requests a playback-only stop, so the "
                       + "transport ■ ends the whole bio session — camera included — and is a "
                       + "duplicate of the front plate's Stop with a ~20 s pulse re-lock as "
                       + "its hidden price. Either restore a producer or remove the button; "
                       + "do not leave the justification standing without the mechanism.")
    }

    // MARK: - Locating the repo

    /// Same walk-up — and the same SKIP — as the sibling `StringCatalogIsHonestTests`:
    /// `#filePath` is inside `Tests/CISmoke/`, so the repo root is three directories up.
    /// A source-reading test that cannot find the source must skip, not pass: a green it
    /// did not earn is the failure mode this whole directory exists to avoid.
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()   // CISmoke
            .deletingLastPathComponent()              // Tests
            .deletingLastPathComponent()              // repo
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("source tree not present at \(sources.path) — this test inspects "
                          + "source text, so it SKIPS rather than reporting a green it did "
                          + "not earn")
        }
        return root
    }
}
