// CopyNamesTheLiveControlTests.swift
// Echoel — #355. ONE defect class: user-facing copy that names a control which does not do
// what the sentence says. It is the most expensive kind of stale text, because it does not
// look stale — it reads as help, so the reader trusts it and hunts for something that is not
// there. This repo has now paid for it four times (#272, #307, #351, #355) — and, as the ⛔
// blocks below record, twice more INSIDE the fix for it.
//
// ⚠️ THREE FILES NOW COVER THIS CLASS, so here is the map rather than three overlapping bans:
//   · `OneStartControlTests` — the START specifically: how many controls begin a session, and
//     a ban on `"Press"` AND `"Create from Within"` together (one dead label, by name).
//   · `FirstInstructionIsTrueTests` (#351) — `FloatingVisualWindow`'s first-run instruction and
//     the precondition behind it.
//   · this file — the two sentences #355 found, and the class in general.
// They assert on disjoint text; nothing here duplicates either.
//
// ⚠️ WHY NOT SIMPLY WIDEN `OneStartControlTests`. Its ban is a PAIR scoped to one specific dead
// label. #355(b) sat six thousand lines away saying "Start with the pulse button (next to
// Play)" and contained NEITHER token, so it stayed green through the whole #307 cleanup that
// repaired its own sister sentence. Widening that pair would have made it enforce more than
// the decision behind it — its own ⛔ says so in as many words.
//
// ⛔ HONEST LIMIT — read before trusting a green. This proves the WORDS are right. It cannot
// prove the control they name is reachable, that VoiceOver reads the button in a sensible
// order, or that a first-run user finds it. Device-verify with VoiceOver is open. And the two
// BANS are literal: `testNoAccessibilityLabelPromisesAStrapWhereThereIsNone` matches the
// phrase "heart-rate strap"/"heart rate strap", so "Open Routing to pair a chest strap" would
// pass. Literal is the right trade for a guard (a semantic one would fire on prose), but do not
// read a green as "no accessibility string overclaims".
//
// ⚠️ WHY A SOURCE SCAN: these are strings inside `private` members of views, `@testable import`
// grants `internal` not `private`, and there is no simulator here. House pattern —
// `OneStartControlTests`, `SaveDoorNamingTests`, `SoundPanelReflowsTests`.

import Foundation
import XCTest

final class CopyNamesTheLiveControlTests: XCTestCase {

    /// ⛔ THE PILL'S **TAP** STARTS NOTHING — it opens the Bio panel, and its own hint says so
    /// (`HeaderMonitors`: "Opens the bio panel … Touch and hold to choose a bio source"). Its
    /// LONG-PRESS is a different matter and the first version of this note got it wrong: the
    /// three "Play with …" entries call `selectBioSource`, which begins a session when idle, and
    /// `OneStartControlTests` enumerates that path by name. So the ban is not "the pill never
    /// starts" — it is that a sentence naming the pill as THE start is wrong about the gesture
    /// people actually try first, and about which control is the one start.
    ///
    /// ⚠️ SCOPED TO CODE, NOT TO COMMENTS, and the discrimination is load-bearing rather than
    /// decorative. Two live code lines in `EchoelStudioView` carried `// chrome mirror
    /// (TransportBar pulse button)` as a TRAILING comment, which a whole-line filter does not
    /// remove — a bare phrase ban would have reddened the only blocking bundle over two stale
    /// breadcrumbs. (Stale, not accurate: `WorkspaceView` records that the transport pulse
    /// button was DELETED on 2026-07-15, not moved. They deserved renaming; a copy guard is the
    /// wrong tool to force it, which is exactly why trailing comments are cut out here instead
    /// of banned. ⛔ #1107 renamed both breadcrumbs to `PlaybackToggleButton`; the example is
    /// history since #1108, the stripping stays — the next trailing comment will not ask first.)
    ///
    /// ⚠️ AND IT MATCHES THE WHOLE FILE, NOT A LINE. The first version required the phrase and a
    /// `"` on the SAME raw line — so a re-added sentence wrapped across two lines, or written as
    /// a `"""` literal, would have passed. That is not hypothetical here: the Routing hint one
    /// declaration away was 257 characters, over SwiftLint's 200-char error threshold, so
    /// "wrap the long line" is a realistic edit in this exact block. Cost of the file-wide join:
    /// the failure names the FILE, not the line. Worth it — a guard that a reformat disarms is
    /// the failure mode this bundle keeps paying for.
    func testNoCopyTellsTheUserToStartWithThePulseButton() throws {
        let liars = try codeByFile().filter { $0.value.contains("pulse button") }.keys.sorted()
        XCTAssertTrue(liars.isEmpty, """
        \(liars.joined(separator: ", ")) contains "pulse button" in CODE (comments excluded).

        The pill's tap opens the Bio panel; it is not the control that starts a session. The ONE \
        start is the play triangle whose VoiceOver label is "Play" — name that.

        If this is a log or diagnostic string rather than user-facing copy, rename it anyway: \
        the control has not been a button since 2026-07-15, and a breadcrumb naming a control \
        that does not exist misleads exactly the person reading a device log to find out what \
        happened.
        """)
    }

    /// The positive half. Without it the ban above is satisfied by DELETING the first-run
    /// sentence, which would take the one piece of guidance in that panel with it — the very
    /// thing #272 was filed to add.
    /// ⛔ Named `testTheSaveExportFirstRunLineNamesTheOneStart` until GUI-Board Scheibe 5
    /// (UX#7, 2026-08-16) moved the sentence OUT of that panel onto the plate under
    /// `quickActionRow` — a test named for a location the code no longer uses is the #374
    /// class. Same guard, same needles, plus the placement half the move creates.
    func testTheFirstRunLineNamesTheOneStartAndSitsOnThePlate() throws {
        let hint = try sourceLines().filter { $0.text.contains("then you can record the loop") }
        XCTAssertEqual(hint.count, 1, """
        expected exactly one first-run hint (anchored on "then you can record the loop"), \
        found \(hint.count).

        If it was reworded, re-anchor this guard in the same commit. If it was deleted, read \
        #272 first: the founder could not find saving or recording, and this sentence is the \
        answer that was added — and since Scheibe 5 it is the only sentence on the PLATE \
        that explains the grey first-run tiles.
        """)
        for line in hint {
            XCTAssertTrue(line.text.contains("Press Play"), """
            \(line.file):\(line.line) no longer tells the user to press Play: \
            \(line.text.trimmingCharacters(in: .whitespaces))

            The greyed Save/Record/Export tiles in the row under the transport are the first \
            thing a new user meets, and this is the only sentence that says why. It has to \
            name the control that actually starts a session. (⛔ Said the sentence \
            "deliberately stayed behind" in Save & Export until Scheibe 5 — the UX audit \
            found first-run users never open that panel, so the sentence now follows the \
            tiles it explains.)
            """)
        }
        // Placement (Scheibe 5): the sentence renders BETWEEN the action row and the door
        // row — on the plate, not in a panel. All three anchors occur exactly once in the
        // stripped studio source (the bare mount lines are unique; measured at write time
        // and asserted here so the ordering cannot key on a second copy, #408/#610b).
        let studio = try studioCode()
        let mount = "\n            quickActionRow\n"
        let door = "\n            quickDoorRow\n"
        let needle = "then you can record the loop"
        for (token, name) in [(mount, "quickActionRow mount"), (door, "quickDoorRow mount"), (needle, "first-run sentence")] {
            XCTAssertEqual(occurrences(of: token, in: studio), 1, """
            \(name) is no longer unique in EchoelStudioView's stripped source — the \
            placement ordering below keys on the first copy; re-anchor before trusting it.
            """)
        }
        let m = try XCTUnwrap(studio.range(of: mount))
        let s = try XCTUnwrap(studio.range(of: needle))
        let d = try XCTUnwrap(studio.range(of: door))
        XCTAssertTrue(m.lowerBound < s.lowerBound && s.lowerBound < d.lowerBound, """
        The first-run sentence left the plate (it must sit between `quickActionRow` and \
        `quickDoorRow`, next to the grey tiles it explains — Scheibe 5/UX#7). If a redesign \
        moves it deliberately, move this ordering and the panel tombstone in the same commit.
        """)
    }

    private func studioCode() throws -> String {
        let url = try repoRoot().appendingPathComponent("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        var count = 0
        var search = haystack.startIndex..<haystack.endIndex
        while let r = haystack.range(of: needle, range: search) {
            count += 1
            search = r.upperBound..<haystack.endIndex
        }
        return count
    }

    /// ⛔ #355(c) — AN `accessibilityLabel` REPLACES THE VISIBLE LABEL, so a false one is only
    /// ever read by the person who cannot check it against the screen. The Routing button
    /// claimed it connects a BLE heart-rate strap; `PatchbayView` pairs Bluetooth MIDI, opens a
    /// network MIDI session, sets the OSC/ADM/Art-Net/sACN targets and holds the light master,
    /// and contains no heart-rate pairing at all.
    ///
    /// ⛔ THE FIRST VERSION ALSO CARRIED `&& !text.contains("not paired here")` — a
    /// self-exemption for the corrective hint. It was INERT (the hint contains no "Routing", so
    /// the filter was already false one clause earlier) and its stated reason was therefore
    /// wrong, while the hole it opened was real: any future label pairing Routing with a strap
    /// escaped by also containing that phrase. Deleted. A guard should not carry an exemption
    /// for a case that cannot arise.
    ///
    /// Same whole-file scope and the same reason as the first test: on one raw line, a wrapped
    /// `.accessibilityLabel(\n "… strap")` splits the tokens and passes.
    func testNoAccessibilityLabelPromisesAStrapWhereThereIsNone() throws {
        let liars = try codeByFile().filter { file in
            (file.value.contains("accessibilityLabel") || file.value.contains("accessibilityHint"))
                && file.value.contains("Routing")
                && (file.value.contains("heart-rate strap") || file.value.contains("heart rate strap"))
        }.keys.sorted()
        XCTAssertTrue(liars.isEmpty, """
        \(liars.joined(separator: ", ")) pairs an accessibility string, "Routing" and a \
        heart-rate strap — the shape that told a VoiceOver user Routing connects one.

        It does not. `PatchbayView` is MIDI pairing, network output targets and the light \
        master. The strap has ONE owner — `startBioSource`, reached by touch-and-hold on the \
        heart-rate monitor. If a strap door is ever added to Routing, delete this guard in that \
        commit and say so.

        (File-scoped, so an unrelated co-occurrence in the same file trips it. That is the price \
        of surviving a line wrap; if it fires on something innocent, narrow it to a window \
        rather than back to one line.)
        """)
    }

    /// The other half of (c): Routing must still SAY what it does, or the fix above degrades
    /// into an unlabelled button — a different accessibility defect, not an improvement.
    ///
    /// ⚠️ ANCHORED ON THE BUTTON, not just on the file. The first version asserted only that
    /// SOME hint in `EchoelStudioView.swift` mentions the light master, so moving it onto the
    /// master panel's Routing door would have kept it green while this button went hint-less.
    /// Pinning `"Open Routing"` and `"light master"` to the same file AND requiring the label
    /// costs nothing and closes that.
    func testTheRoutingButtonStillDescribesWhatIsInside() throws {
        let studio = try sourceLines().filter { $0.file == "EchoelStudioView.swift" }
        XCTAssertTrue(studio.contains { $0.text.contains(".accessibilityLabel(\"Open Routing\")") }, """
        the bio panel's Routing button no longer carries `.accessibilityLabel("Open Routing")`.

        It is deliberately identical to the visible `Label` — SwiftUI would derive the same \
        string — so it looks redundant and is not: it is what stops the false "connect a BLE \
        heart-rate strap" label from being re-added, and what the guard above matches on. If \
        the button moved, move this with it; do not delete it as cleanup.
        """)
        let hints = studio.filter {
            $0.text.contains("accessibilityHint") && $0.text.contains("light master")
        }
        XCTAssertEqual(hints.count, 1, """
        the Routing button's accessibility hint (anchored on "light master") is gone or \
        duplicated — found \(hints.count).

        `.accessibilityLabel("Open Routing")` alone tells a VoiceOver user the name of a door \
        and nothing about the room. The hint is what carries MIDI, the network targets and the \
        light master. Reword it freely; re-anchor this guard in the same commit — and keep it \
        short: VoiceOver speaks hints in full, and the app's median is ~57 characters.
        """)
    }

    /// Every Swift file under `Sources/`, as ONE whitespace-normalised string of CODE per file:
    /// whole-line comments dropped, trailing comments cut, lines joined with a space. Two
    /// properties matter and neither is decoration —
    ///   · comments are gone, so the prose explaining a defect never satisfies the guard against
    ///     it, and two stale trailing breadcrumbs do not redden the blocking bundle;
    ///   · lines are joined, so a token pair survives a line wrap and a `"""` literal reads as
    ///     one string.
    ///
    /// ⚠️ THE TRAILING-COMMENT CUT IS QUOTE-AWARE, because a naive cut at the first `//` would
    /// truncate any string holding a URL — `PatchbayView`'s attribution link and the WeatherKit
    /// one both contain `https://`, and silently swallowing the rest of such a line is how a
    /// scanner starts reporting greens it did not earn.
    private func codeByFile() throws -> [String: String] {
        var out: [String: String] = [:]
        for line in try sourceLines() {
            let code = Self.strippingTrailingComment(line.text)
                .trimmingCharacters(in: .whitespaces)
            guard !code.isEmpty else { continue }
            out[line.file, default: ""] += code + " "
        }
        return out
    }

    /// The part of `raw` before a `//` that is not inside a string literal.
    private static func strippingTrailingComment(_ raw: String) -> String {
        var inString = false
        var escaped = false
        let chars = Array(raw)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if escaped { escaped = false; i += 1; continue }
            if c == "\\" && inString { escaped = true; i += 1; continue }
            if c == "\"" { inString.toggle(); i += 1; continue }
            if !inString && c == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
                return String(chars[0..<i])
            }
            i += 1
        }
        return raw
    }

    /// Every line of every Swift file under `Sources/`, minus whole-line comments.
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
