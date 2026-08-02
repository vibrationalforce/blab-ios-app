// CopyNamesTheLiveControlTests.swift
// Echoel — #355. ONE defect class: user-facing copy that names a control which does not do
// what the sentence says. It is the most expensive kind of stale text, because it does not
// look stale — it reads as help, so the reader trusts it and hunts for something that is not
// there. This repo has now paid for it three times (#272, #307, #355).
//
// ⚠️ WHY NOT IN `OneStartControlTests`, which already guards one instance of this. That file's
// ban fires on `"Press"` AND `"Create from Within"` TOGETHER — a pair scoped to one specific
// dead label. #355(b) sat six thousand lines away saying "Start with the pulse button (next to
// Play)" and contained NEITHER token, so it stayed green through the whole #307 cleanup that
// repaired its own sister sentence. A guard aimed at one dead label does not cover the class;
// widening that file's pair would have made it enforce more than the decision behind it (its
// own ⛔ says so). Two files, two scopes.
//
// ⛔ HONEST LIMIT — read before trusting a green. This proves the WORDS are right. It cannot
// prove the control they name is reachable, that VoiceOver reads the button in a sensible
// order, or that a first-run user finds it. Device-verify with VoiceOver is open.
//
// ⚠️ WHY A SOURCE SCAN: these are strings inside `private` members of views, `@testable import`
// grants `internal` not `private`, and there is no simulator here. House pattern —
// `OneStartControlTests`, `SaveDoorNamingTests`, `SoundPanelReflowsTests`.

import Foundation
import XCTest

final class CopyNamesTheLiveControlTests: XCTestCase {

    /// ⛔ THE PULSE PILL IS NOT A START, AND HAS NOT BEEN SINCE 2026-07-29. It opens the Bio
    /// panel; touch-and-hold picks the bio source (`HeaderMonitors`' own hint says exactly
    /// that). Any sentence that sends a user there to begin sends them to a panel.
    ///
    /// ⚠️ SCOPED TO STRING LITERALS, and the discrimination is load-bearing rather than
    /// decorative. Two live code lines in `EchoelStudioView` carry `// chrome mirror
    /// (TransportBar pulse button)` as a TRAILING comment — `sourceLines()` skips whole-line
    /// comments but not those, so a bare phrase ban would redden the only blocking bundle over
    /// two accurate notes about a control that really was called that before #289 moved it.
    /// Requiring a `"` on the line keeps the ban on copy, where the defect is.
    func testNoCopyTellsTheUserToStartWithThePulseButton() throws {
        let liars = try sourceLines().filter {
            $0.text.contains("pulse button") && $0.text.contains("\"")
        }
        XCTAssertTrue(liars.isEmpty, """
        \(liars.map { "\($0.file):\($0.line)" }.joined(separator: ", ")) contains "pulse button" \
        inside a string.

        The header pill is not a button that starts anything — it opens the Bio panel, and \
        touch-and-hold picks the bio source. The ONE start is the play triangle whose VoiceOver \
        label is "Play". Name that.

        If this is a log or diagnostic string rather than user-facing copy, rename it anyway: \
        the control has not been a button since #289, and a breadcrumb naming a control that \
        does not exist misleads exactly the person reading a device log to find out what \
        happened.
        """)
    }

    /// The positive half. Without it the ban above is satisfied by DELETING the first-run
    /// sentence, which would take the one piece of guidance in that panel with it — the very
    /// thing #272 was filed to add.
    func testTheSaveExportFirstRunLineNamesTheOneStart() throws {
        let hint = try sourceLines().filter { $0.text.contains("then you can record the loop") }
        XCTAssertEqual(hint.count, 1, """
        expected exactly one first-run hint in the Save & Export panel (anchored on \
        "then you can record the loop"), found \(hint.count).

        If it was reworded, re-anchor this guard in the same commit. If it was deleted, read \
        #272 first: the founder could not find saving or recording, and this sentence is the \
        answer that was added.
        """)
        for line in hint {
            XCTAssertTrue(line.text.contains("Press Play"), """
            \(line.file):\(line.line) no longer tells the user to press Play: \
            \(line.text.trimmingCharacters(in: .whitespaces))

            The greyed Save/Record/Export buttons in that panel are the first thing a new user \
            meets, and this is the only sentence that says why. It has to name the control that \
            actually starts a session.
            """)
        }
    }

    /// ⛔ #355(c) — AN `accessibilityLabel` REPLACES THE VISIBLE LABEL, so a false one is only
    /// ever read by the person who cannot check it against the screen. The Routing button
    /// claimed it connects a BLE heart-rate strap; `PatchbayView` pairs Bluetooth MIDI, opens a
    /// network MIDI session, sets the OSC/ADM/Art-Net/sACN targets and holds the light master,
    /// and contains no heart-rate pairing at all.
    func testNoAccessibilityLabelPromisesAStrapWhereThereIsNone() throws {
        let liars = try sourceLines().filter {
            ($0.text.contains("accessibilityLabel") || $0.text.contains("accessibilityHint"))
                && $0.text.contains("Routing")
                && ($0.text.contains("heart-rate strap") || $0.text.contains("heart rate strap"))
                // The correction itself says where the strap ISN'T — that sentence must not
                // trip the guard that exists because of it.
                && !$0.text.contains("not paired here")
        }
        XCTAssertTrue(liars.isEmpty, """
        \(liars.map { "\($0.file):\($0.line)" }.joined(separator: ", ")) tells a VoiceOver user \
        that Routing connects a heart-rate strap.

        It does not. `PatchbayView` is MIDI pairing, network output targets and the light \
        master. The strap has ONE owner — `startBioSource`, reached by touch-and-hold on the \
        pulse display. If a strap door is ever added to Routing, delete this guard in that \
        commit and say so.
        """)
    }

    /// The other half of (c): Routing must still SAY what it does, or the fix above degrades
    /// into an unlabelled button — a different accessibility defect, not an improvement.
    func testTheRoutingButtonStillDescribesWhatIsInside() throws {
        let studio = try sourceLines().filter { $0.file == "EchoelStudioView.swift" }
        let hints = studio.filter {
            $0.text.contains("accessibilityHint") && $0.text.contains("light master")
        }
        XCTAssertEqual(hints.count, 1, """
        the Routing button's accessibility hint (anchored on "light master") is gone or \
        duplicated — found \(hints.count).

        `.accessibilityLabel("Open Routing")` alone tells a VoiceOver user the name of a door \
        and nothing about the room. The hint is what carries MIDI, the network targets and the \
        light master. Reword it freely; re-anchor this guard in the same commit.
        """)
    }

    /// Every line of every Swift file under `Sources/`, minus whole-line comments — so the
    /// prose explaining a defect never satisfies the guard against it. Deliberately NOT
    /// stripping trailing comments: see the scoping note on the first test, which depends on
    /// them being visible so the reason for the `"` filter stays checkable.
    private func sourceLines() throws -> [(file: String, line: Int, text: String)] {
        let root = try repoRoot().appendingPathComponent("Sources")
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        var out: [(file: String, line: Int, text: String)] = []
        var scanned = 0
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            scanned += 1
            for (i, raw) in text.components(separatedBy: .newlines).enumerated() {
                guard !raw.trimmingCharacters(in: .whitespaces).hasPrefix("//") else { continue }
                out.append((url.lastPathComponent, i + 1, raw))
            }
        }
        XCTAssertGreaterThan(scanned, 250,
                             "Only \(scanned) Swift files scanned — every search below would "
                             + "pass vacuously on a tree it never read.")
        return out
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`, three levels
    /// up: CISmoke → Tests → repo).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("source tree not present at \(sources.path) — this test inspects "
                          + "source text, so it SKIPS rather than reporting a green it did "
                          + "not earn")
        }
        return root
    }
}
