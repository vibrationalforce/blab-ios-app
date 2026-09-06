import XCTest

/// #1024 — THE MICROPHONE MONITORING DOORS ARE REMOVED, BY FOUNDER ORDER, TWICE STATED.
///
/// 2026-09-06: *"das mit dem Audio Input Monitoren klappt immer noch nicht also fliegt das
/// raus"*, and again the same day with a screenshot of build v10.79.448 (2567) circling the
/// "Voice · your microphone" card itself. It had never once been confirmed working on a
/// device, across several builds and several repairs — the last of them #1022, which found a
/// real launch-time cause (`setCategory` returning -50 left the session unconfigured, so
/// `monitor: on` was REFUSED nine minutes later) and still did not make it audible.
///
/// ⚠️ WHY THE DOORS AND NOT THE MACHINE, and this is the whole point of the slice. The
/// founder's second sentence was about the PATTERN, not the feature: *"erst wird munter drauf
/// los programmiert und dann verhäddert es sich"*. Ripping out the engine, the monitor insert,
/// FeedbackGuard, the autotune stage, the harmonizer and the granular texture in one go is
/// precisely that tangle, in reverse. Removing three call sites is not.
///
/// So: three doors went — the Mix-board strip, the Master panel's "Audio input" button, and
/// the plug-in invitation banner. `AudioInputPickerView`, the `showInput` sheet slot and every
/// line of `AudioEngine`'s monitoring path are untouched and still compile. The feature is
/// invisible and unreachable; the code is intact and re-dooring is three call sites.
///
/// ⚠️ NOTHING IS STRANDED. `isInputMonitoring` is not persisted, so every launch begins with
/// the microphone off. Removing a switch whose flag IS persisted would leave a user with no
/// way back — that trap was checked before cutting, not after.
///
/// ⛔ ONE GUARD IS RETIRED WITH THE STRIP, AND IT IS NAMED HERE RATHER THAN VANISHING.
/// `TheVoiceIsOnTheBoardTests` (#485) existed to keep `micMixStrip` mounted in the Mix
/// board; six of its seven methods pinned text that #1024 deleted, so leaving it in the tree
/// would mean a RED guard on a CORRECT tree — exactly the tangle the founder's second
/// sentence warned about. Its seventh method (the engine still reports whether monitoring
/// engaged) is claim 3 below, and its three FORWARD-facing laws — permission-before-engage,
/// no 15 Hz `feedbackGuardActive` read in a strip builder, no bare `.sheet` on the body chain
/// — are copied verbatim into the `⛔ #1024` obituary in `EchoelStudioView.swift`, which is
/// where a re-doorer will actually be standing. Nothing was deleted silently.
///
/// ⚠️ FIVE MORE GUARDS KEPT THEIR SUBJECTS AND LOST CLAIMS, repaired in this same commit
/// (#456): `ThePlugInInvitesButNeverArmsTests` (the mount claim, inverted, plus a new
/// counterweight that the row and watcher files survive), `TheRefusalLineHasASettingsDoorTests`
/// (its mix-board half; the input-sheet half is untouched and still guards the surviving
/// door), `TheMonitorSaysWhyItIsSilentTests` (same shape — claim 1 inverted, claim 3's studio
/// half re-pointed), `TapTargetFloorTests` (the mix-board site dropped from its two-site
/// sweep) and `TheMonitorToggleAsksForTheMicTests` (its Mix-board claim; the picker and engine
/// claims still stand). Every removed needle is QUOTED at its site, so re-dooring means
/// restoring those claims verbatim, not writing new ones.
///
/// ⛔ THE COUNT ABOVE WAS "FOUR" WHEN FIRST WRITTEN, AND IT WAS WRONG BY ONE. The sweep that
/// produced it used a needle set that did not include the silence-line sentence, so
/// `TheMonitorSaysWhyItIsSilentTests` — which reads `EchoelStudioView` and pinned two needles
/// #1024 deleted — was not in the list. Corrected before the commit, and recorded because it
/// is the #766/#768 shape: "all of them" only ever means "all the ones my needle matched".
///
/// ⛔ AND IT WAS WRONG A SECOND TIME, IN THE SAME SHAPE, FOR THREE WEEKS (#1038). #1024's
/// prose sweep covered `Sources/`, `CLAUDE.md` and `fastlane/metadata` — it struck "Tune to
/// key" in `ContentPipeline/CLAIMS.md` and left the file's THREE OTHER monitor-path rows
/// standing: the harmonizer on your own voice (#841), the granular texture (#849) and the
/// feedback protection (#847/#848). All three named "Tür im Input-Sheet" as their evidence,
/// which was the door that had just been removed. Nothing published them — measured, the only
/// hit across `fastlane/metadata/` and `docs/` is the MUSIC-path harmonizer, which is fine —
/// but CLAIMS.md is the file CLAUDE.md tells a session to read BEFORE writing any script,
/// caption or hashtag, so it AUTHORISES. Claim 5 makes that file part of the sweep instead of
/// a place the sweep forgot. Same lesson, twice: a needle set is a memory of what occurred to
/// somebody, and the file it never touched leaves no trace of having been skipped.
final class TheMicrophoneHasNoDoorTests: XCTestCase {

    // MARK: - 1. Nothing can open the microphone sheet

    func testTheInputSheetHasNoSetter() throws {
        let view = try code("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertEqual(occurrences(of: "showInput = true", in: view), 0, """
            Something sets `showInput` again, so the microphone sheet has a door (#1024).
            THIS IS NOT AUTOMATICALLY A BUG — the founder may have asked for it back. But it \
            IS a founder decision, and re-dooring means pulling these prose homes along in the \
            SAME commit, or the repo starts lying about itself again:
              · CLAUDE.md, the "Vokal-Kette" paragraph (it says the chain has a door)
              · CLAUDE.md, the doorless register (`AudioInputPickerView` is listed there)
              · CLAUDE.md, the FeedbackGuard line
              · ContentPipeline/CLAIMS.md, the three struck monitor rows (claim 5 below)
              · this guard's own header
            """)
    }

    // MARK: - 2. COUNTERWEIGHT — the removal really was doors-only

    /// Without this, claim 1 would also pass on a tree where somebody "cleaned up" by deleting
    /// the sheet and the picker — which is a far bigger, far less reversible change than the
    /// one the founder asked for.
    func testTheSheetAndThePickerStillExist() throws {
        let view = try code("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertEqual(occurrences(of: ".sheet(isPresented: $showInput)", in: view), 1, """
            The `showInput` sheet slot is gone. #1024 removed DOORS, deliberately keeping the \
            slot as setter-less headroom under the 10.76.34 presentation ceiling (like \
            `showMeditation`). Deleting the slot turns a reversible removal into a rebuild.
            """)
        let root = try repoRoot()
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(
                    "Sources/Echoelmusic/Studio/AudioInputPickerView.swift").path),
            """
            `AudioInputPickerView.swift` is gone. It carries the input picker, the tune \
            presets, the harmony voices and the granular texture — #1024 took its doors, not \
            the file. Deleting it is a separate decision the founder has not taken.
            """)
    }

    // MARK: - 3. COUNTERWEIGHT — the engine is untouched

    func testTheMonitoringEngineIsStillThere() throws {
        let engine = try code("Sources/Echoelmusic/Audio/AudioEngine.swift")
        for symbol in ["func setInputMonitoring", "isInputMonitoring"] {
            XCTAssertGreaterThan(occurrences(of: symbol, in: engine), 0, """
                `\(symbol)` left `AudioEngine`. #1024 is a UI removal; the audio graph was \
                deliberately not touched, so that re-dooring stays three call sites and so \
                that the #1022 session repair — which matters for the sample rate and the \
                session activation, not only for the microphone — keeps its subject.
                """)
        }
    }

    // MARK: - 4. The flag that made this safe to remove has not become persisted

    /// If a later change starts persisting `isInputMonitoring`, removing the switch stops \
    /// being harmless: a user could be left monitoring with no control to stop it.
    func testMonitoringIsStillNotPersisted() throws {
        let engine = try code("Sources/Echoelmusic/Audio/AudioEngine.swift")
        XCTAssertTrue(engine.contains("isInputMonitoring = false"), """
            `isInputMonitoring` no longer starts `false` in its declaration. The safety of \
            #1024 rests on the microphone being OFF at every launch; if this value now comes \
            from storage, a user can be stranded with monitoring on and no switch (#1024).
            """)
    }

    // MARK: - helpers

    // MARK: - 5. The marketing-claim register may not authorise what has no door

    /// ⭐ #1038 — THE FILE THE SWEEP FORGOT. `ContentPipeline/CLAIMS.md` is not documentation;
    /// CLAUDE.md instructs a session to read it BEFORE writing any script, caption or hashtag,
    /// so a row standing there is a licence to publish. Three rows kept their licence for
    /// three weeks after the door under them was removed.
    ///
    /// ⛔ THIS CLAIM FORBIDS NOTHING (#364). It is anchored to claim 1: while nothing sets
    /// `showInput`, these three rows must read as struck. Restore the door and this goes red
    /// BY DESIGN — un-strike the rows in the same commit and the claim is satisfied again.
    /// The rows are deliberately not deleted from the file either way; a struck row with its
    /// reason is what stops the claim being re-invented from scratch.
    func testTheClaimRegisterStrikesTheMonitorRowsWhileTheDoorIsGone() throws {
        let register = try text("ContentPipeline/CLAIMS.md")

        // The struck form, as the file's own convention writes it.
        let struck = ["~~**Harmoniestimmen auf deiner Stimme**",
                      "~~**Granular-Textur auf deiner Stimme**",
                      "~~**Feedback-Schutz, der Pfeifen VERHINDERT"]
        let unstruck = struck.filter { !register.contains($0) }
        XCTAssertTrue(unstruck.isEmpty, """
            `ContentPipeline/CLAIMS.md` no longer strikes: \(unstruck.joined(separator: " · ")).

            Every one of these sits ONLY in the monitor path, whose single door #1024 removed \
            — claim 1 above measures that nothing sets `showInput`. If the founder restored the \
            door, un-strike the rows here in the same commit and pull the CLAUDE.md paragraphs \
            listed in claim 1 along with them (#456). If the door is still gone, a standing row \
            here is a licence to write a caption about a stage no player can reach, which is \
            the 2.3 class.
            """)

        // COUNTERWEIGHT (#367): a negative that a rename or a deletion would satisfy is not a
        // measurement. The rows must still BE there, struck — and the MUSIC-path harmonizer,
        // which #1024 never touched, must still be claimable.
        XCTAssertTrue(register.contains("Nicht mit dem MUSIK-Harmonizer verwechseln"), """
            The note separating the MUSIC-path harmonizer from the monitor one is gone from \
            `ContentPipeline/CLAIMS.md`. Without it the next reader strikes both, and the App \
            Store release note "third and fifth harmony voices above the melody" — which is \
            TRUE and describes the FX-panel harmonizer — starts looking like an overclaim.
            """)
    }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        return root
    }

    /// Raw file text. `code(_:)` strips SWIFT comments and would mangle Markdown, where `//`
    /// appears inside every URL — the one-stripper rule (#453) says add a reader, not a second
    /// stripper.
    private func text(_ relativePath: String) throws -> String {
        try String(contentsOf: try repoRoot().appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func code(_ relativePath: String) throws -> String {
        let text = try String(contentsOf: try repoRoot().appendingPathComponent(relativePath),
                              encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }
}
