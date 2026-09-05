import XCTest
@testable import Echoelmusic

/// #995 — a person can make the app forget their last vital sign.
///
/// WHY IT EXISTS. `BioFeedbackPublisher.publishTick()` writes a decoded body measurement —
/// heart rate, HRV, breath phase, coherence — into the App Group `UserDefaults` suite so the
/// widget and the watch face can read it. A suite lives in `Library/Preferences`, which
/// encrypted backups and iCloud include. Before this slice there was no `removeObject`, no
/// erase method and no backup exclusion anywhere near it: the only way to make Echoel forget a
/// heart rate was to delete the app.
///
/// The sibling case was already handled and made the gap easy to miss. `PerformerSignature` —
/// the fingerprint DERIVED from this reading — is cleared by the factory reset. Its source was
/// not. And this is not a HealthKit-only concern: the key holds the last reading from ANY
/// source and camera rPPG is the default, so it covers everyone who has pressed play, plus
/// anyone who handed the phone to a second performer.
///
/// ⚠️ HONEST GRADING. Four claims. The first is BEHAVIOURAL — it publishes, reads back, erases
/// and re-reads through the real type — and it is therefore the one claim a transcription cannot
/// drive: it is proven by CI's `Run Tests` step, not by reading source. The other three were
/// transcribed against both trees; 2 is load-bearing (green on the worktree, red on `HEAD`), and
/// 3 and 4 are counterweights against the two ways this repair goes wrong later — being filed
/// under the wrong store, or drifting from the key it must remove.
///
/// ⚠️ WHAT THIS FILE DOES NOT CLAIM. Erasing the key is not the same as excluding the file from
/// backup — a backup taken BEFORE the erase still holds the old payload, and nothing in this
/// repo can reach it. Claim 4's message names that limit rather than letting the guard imply a
/// stronger promise than the code makes.
final class TheAppCanForgetYourBodyTests: XCTestCase {

    private static let manager = "Sources/Echoelmusic/Core/BioFeedbackManager.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    private func source(_ relative: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read — a missing anchor is a "
                    + "finding, not a pass.")
            return ""
        }
        return text
    }

    // 1 — BEHAVIOURAL, and the only claim here that runs the real code. Publish a reading into
    // a throwaway suite, prove it reads back, erase it, prove it is gone. A string search
    // cannot tell a `removeObject` on the right key from one on a typo.
    func testAPublishedReadingCanBeErased() throws {
        let suite = "group.com.echoelmusic.tests.\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }

        let manager = BioFeedbackManager(appGroup: suite)
        // NOT `XCTSkipUnless` — a skip is not a pass (#806), and it would hide the one claim
        // here that runs real code. `UserDefaults(suiteName:)` returns nil only for the global
        // domain or the bundle's own id, so a random suite name opening is not in doubt; if it
        // ever is, that is a finding about the store, not a reason to report nothing.
        XCTAssertTrue(manager.isAvailable, """
            The throwaway suite would not open, so this test could not exercise the erase at \
            all. Treat that as a finding about `BioFeedbackManager`'s store, not as a pass.
            """)
        guard manager.isAvailable else { return }

        manager.publish(BioVitals(heartRateBPM: 61, hrvNormalized: 0.42,
                                  breathPhase: 0.25, coherence: 0.7))
        XCTAssertNotNil(manager.refreshFromSharedStore(), """
            The reading did not survive its own round trip, so this test cannot say anything \
            about erasing it. Fix the publish/refresh pair before reading the claim below.
            """)

        BioFeedbackManager.clearSharedVitals(appGroup: suite)
        XCTAssertNil(BioFeedbackManager(appGroup: suite).refreshFromSharedStore(), """
            A published vital sign survives `clearSharedVitals`. The value is a decoded body \
            measurement in a UserDefaults suite — `Library/Preferences`, which encrypted \
            backups and iCloud include — so a person who revokes Health access or hands the \
            phone to another performer has no way to make the app forget it short of deleting \
            the app.
            """)
    }

    // 2 — the factory reset actually calls it. WINDOWED to the function on purpose: a
    // whole-file search would pass on the day the bug exists, which is the lesson
    // `ResetSoundClearsWhatTheLaunchLineReportsTests` wrote down after paying for it once.
    func testTheFactoryResetForgetsTheBody() throws {
        let lines = try source(Self.studio).split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard let start = lines.firstIndex(where: {
            $0.contains("private func resetSoundToDefaults")
        }) else {
            return XCTFail("`resetSoundToDefaults` is gone — if the reset moved, move this guard.")
        }
        guard let end = lines[start...].firstIndex(where: { $0.contains("reset/sound:") }) else {
            return XCTFail("the reset's closing breadcrumb is gone — re-derive this window.")
        }
        let window = lines[start...end].joined(separator: "\n")
        XCTAssertTrue(window.contains("BioFeedbackManager.clearSharedVitals()"), """
            The factory reset no longer erases the shared vitals. Everything else it clears is \
            MUSICAL state in `UserDefaults.standard`; the last decoded body measurement lives \
            in the App Group suite, and this is the only control in the app that removes it. \
            The reset already clears `performerSignature`, which is DERIVED from this value — \
            clearing the derivative and keeping the source is the shape of the original bug.
            """)
    }

    // 3 — COUNTERWEIGHT against the obvious "tidy-up": folding this into `SoundReset.entries`.
    // That list is cleared against `.standard` by the production caller, so an entry naming the
    // group suite would clear NOTHING while reading as though it did — a privacy control that
    // is only a label. It would also demand a launch-line report for a value that has no
    // business appearing in one.
    func testTheEraseIsNotFiledUnderTheWrongStore() throws {
        let reset = try source("Sources/Echoelmusic/Core/SoundReset.swift")
        XCTAssertFalse(reset.contains("bioVitals"), """
            `SoundReset` now names the shared-vitals key. Its production caller passes \
            `.standard`, and this value lives in the App Group suite — so the entry would clear \
            nothing while reading as if it did, and `ResetSoundClearsWhatTheLaunchLineReports` \
            would demand a launch-line report for a body measurement. A different store needs a \
            different call, not a row in a list about another store.
            """)
    }

    // 4 — the erase names the same key the writer uses. Two literals for one key is how an
    // erase silently stops matching what it is supposed to remove.
    func testTheEraseAndTheWriterShareOneKey() throws {
        let text = try source(Self.manager)
        XCTAssertEqual(text.components(separatedBy: "\"bioVitals.v1\"").count - 1, 1, """
            The storage key is written out more than once in `BioFeedbackManager`. The erase \
            must remove exactly what `publish` writes; a second literal is how those two drift \
            and the erase quietly stops matching.

            NOTE the limit this guard does NOT cover: removing the key does not reach a backup \
            taken BEFORE the erase. Nothing in this repo can. Do not let a stronger promise \
            than that reach user-facing copy.
            """)
    }
}
