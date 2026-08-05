// LaunchLogsWhatItWokeUpWithTests.swift
// Echoel — #401. The founder reported the instrument playing "schief" (out of tune), and then
// that DELETING AND REINSTALLING the app cured it. Same binary either side of that sentence, so
// the cause was a value PERSISTED ON THE DEVICE and not a code path — and the reinstall is also
// what destroyed the only copy of the evidence. The question "which stored value was it" is now
// permanently unanswerable for THAT instance.
//
// ⭐ SO THIS FILE GUARDS A DIAGNOSTIC, NOT A FIX, and that is the point. The existing
// `generate[…]` breadcrumb carries four of these values, fires only once the user presses
// Generate, and by then a user who reinstalls first has taken the state with them. The launch
// line closes both gaps: it fires on every launch, before any playing, and it names the whole
// restored musical identity. The next occurrence has to be answerable from ONE pasted log.
//
// ⛔ HONEST LIMITS, because a guard that oversells itself is the failure mode this bundle exists
// to prevent. Three of these four tests are SOURCE SCANS — they prove the call is written and
// what it names, never that the line reaches the log file on a device (`EchoelCrashLog.breadcrumb`
// no-ops when its fd is closed, and there is no simulator here). The fourth is real behaviour and
// needs no scan. None of them can say whether the VALUE printed is the one that detuned anything
// — that is the founder's ear against a future log. House pattern: `SoundPromptHasADoorTests`,
// `SoundPanelPresetBarTests`, `BioApplyRateIsTheDedupedRateTests`.

import Foundation
import XCTest
@testable import Echoelmusic

final class LaunchLogsWhatItWokeUpWithTests: XCTestCase {

    /// The breadcrumb's own prefix. Deliberately distinct from `generate[` so the two lines can
    /// never be confused in a pasted log — they report different moments and different scopes.
    private static let marker = "launch/musical:"

    /// The function that emits it, and the name the launch restore must call.
    private static let emitter = "logLaunchMusicalIdentity"

    /// Every persisted value the line must NAME. Each one is a key that survives a relaunch and
    /// can change what the instrument sounds like; a launch log missing any of them cannot rule
    /// that key in or out, which is the whole job here.
    ///
    /// Adding a persisted musical key later? Add its label here in the SAME commit — that is the
    /// only thing standing between "the log answers it" and another audit like the one #401 paid
    /// for.
    private static let requiredLabels = [
        "key=",            // studio.rootIndex + studio.scale — which notes exist
        "tuning=",         // toneSystemID — the only key that bends the INTERVAL between two notes
        "a4=",             // echoel.a4Hz — concert pitch, applied to all six voices at launch
        "genre=",          // studio.genre — and the roster clamp can rewrite it during restore
        "preset=",         // studio.presetIndex — restores a factory timbre over the genre's own
        "articulation=",   // studio.articulation — the persisted Pluck↔Pad envelope
        "touchPatch=",     // touch.patchID — the one launch path that applies USER-authored JSON
        "glide=",          // touch.glide — a persisted slide between Field notes
    ]

    // MARK: - The line exists, and the launch restore calls it

    /// ⭐ THE HEADLINE. Not anchored to a file name: any production file may own the emitter, and
    /// a later hoist into its own type must keep this green on its own.
    func testTheLaunchBreadcrumbIsEmittedSomewhereInProduction() throws {
        let hits = try filesContaining(Self.marker)
        XCTAssertFalse(hits.isEmpty, """
        nothing in Sources/ emits a "\(Self.marker)" breadcrumb any more.

        That is the pre-#401 state exactly: the only line naming the restored musical identity \
        was `generate[…]`, which fires only after the user presses Generate. A founder who \
        reinstalls before pressing it takes the evidence with them, and the report becomes \
        unfalsifiable — which is precisely what happened on 2026-08-05.

        If the diagnostic was deliberately retired, delete this file in the same commit rather \
        than leaving a test naming a breadcrumb nobody writes.
        """)
    }

    /// A declared-but-uncalled emitter is a doorless diagnostic: it compiles, the test above
    /// passes on the string inside it, and no launch ever writes a line.
    func testTheEmitterIsActuallyCalled() throws {
        var declaringFiles: [String] = []
        var callSites = 0
        for path in try swiftSourcePaths() {
            let lines = try codeLines(path)
            if lines.contains(where: { $0.contains("func \(Self.emitter)") }) { declaringFiles.append(path) }
            callSites += lines.filter {
                $0.contains("\(Self.emitter)()") && !$0.contains("func \(Self.emitter)")
            }.count
        }
        XCTAssertFalse(declaringFiles.isEmpty, """
        no file under Sources/ declares `\(Self.emitter)`. If it was renamed, rename it here too.
        """)
        XCTAssertGreaterThan(callSites, 0, """
        `\(Self.emitter)` is declared in \(declaringFiles.joined(separator: ", ")) but never \
        called.

        A diagnostic nobody invokes is worse than none: every test above stays green while no \
        launch writes a line, so the next "schief" report is investigated against a log that \
        looks complete and silently isn't.
        """)
    }

    // MARK: - What the line must say

    /// The payload is the whole value of the line. A breadcrumb that fires on every launch and
    /// names three of eight persisted keys still leaves five of them un-rulable.
    func testTheLineNamesEveryPersistedMusicalValue() throws {
        let line = try breadcrumbLine()
        for label in Self.requiredLabels {
            XCTAssertTrue(line.contains(label), """
            the "\(Self.marker)" breadcrumb no longer carries `\(label)`.

            Emitted line:
            \(line)

            Every label in `requiredLabels` is a value that survives a relaunch and can change \
            what the instrument sounds like. Dropping one does not break anything visible — it \
            just removes that key from the next investigation's evidence, which is the exact \
            way this class of defect stays expensive.
            """)
        }
    }

    /// ⭐ PRIVACY, AND THE ONE THING A FUTURE EDIT IS MOST LIKELY TO GET WRONG. The obvious
    /// "improvement" to this line is to print WHICH custom patch is loaded — i.e. interpolate
    /// `touchPatchID`, a UUID, into a log the founder pastes into a chat. The diagnostic question
    /// is only whether a user-authored patch drives the play surface at all, so the identifier
    /// buys nothing and the presence flag ("take"/"custom") answers it completely.
    func testTheLineDoesNotLeakTheCustomPatchIdentifier() throws {
        let line = try breadcrumbLine()
        XCTAssertFalse(line.contains("\\(touchPatchID)"), """
        the "\(Self.marker)" breadcrumb interpolates `touchPatchID` directly:
        \(line)

        That writes a raw UUID into a diagnostic log the founder pastes into chat threads. Log \
        the PRESENCE instead (`touchPatchID.isEmpty ? "take" : "custom"`), which answers the only \
        question the line is asked.
        """)
    }

    // MARK: - Real behaviour: the premise the whole diagnosis rests on

    /// ⭐ NOT A SCAN. "Delete and reinstall cured it" is only evidence of persisted state if a
    /// FRESH install is neutral for the keys involved. These two are the pitch-relevant ones that
    /// reach a sounding voice during the launch restore, and both must default to "nothing".
    ///
    /// Give either of them a non-neutral default and the reinstall stops being a control: a user
    /// who wipes the app would land on the same altered sound, and the one clean signal this
    /// investigation had would be gone. (`touch.slideVibrato` already defaults to a non-zero
    /// 0.35 — deliberately, and that is exactly why it could be ruled out here.)
    func testAFreshInstallIsNeutralForTheKeysThatReachAVoiceAtLaunch() {
        XCTAssertTrue(StudioDefaultKeys.touchPatchID.value.isEmpty, """
        `touch.patchID` no longer defaults to empty, so a fresh install would load a stored \
        patch into the play surface — and "delete + reinstall" would stop being able to tell a \
        persisted-state defect from a code defect.
        """)
        XCTAssertEqual(StudioDefaultKeys.touchGlide.value, 0, accuracy: 0.0001, """
        `touch.glide` no longer defaults to 0, so a fresh install would slide between Field \
        notes. Same consequence as above: the reinstall stops being a clean control.
        """)
    }

    // MARK: - Source access

    /// The single emitted line, with comments stripped so the prose ABOVE the emitter (which
    /// quotes the marker and several labels verbatim) can never stand in for the code.
    private func breadcrumbLine() throws -> String {
        for path in try swiftSourcePaths() {
            if let line = try codeLines(path).first(where: { $0.contains(Self.marker) }) { return line }
        }
        XCTFail("""
        no CODE line under Sources/ contains "\(Self.marker)" — only prose, if anything. \
        `testTheLaunchBreadcrumbIsEmittedSomewhereInProduction` explains what that means.
        """)
        return ""
    }

    /// ⛔ The `try` is deliberately in the BODY, not in a `for … where` clause. Whether a throwing
    /// call is accepted in a `where` clause is a corner this repo cannot check locally — there is
    /// no Swift toolchain here, and a guess that compiles nowhere turns the BLOCKING bundle red
    /// for a full CI round-trip. `SoundPromptHasADoorTests` keeps its `try` in the body for the
    /// same reason; its `where` clause carries only a plain comparison.
    private func filesContaining(_ needle: String) throws -> [String] {
        var out: [String] = []
        for path in try swiftSourcePaths() {
            if try codeLines(path).contains(where: { $0.contains(needle) }) { out.append(path) }
        }
        return out.sorted()
    }

    /// Every Swift file under `Sources/`, repo-relative.
    private func swiftSourcePaths() throws -> [String] {
        let root = try repoRoot()
        let sources = root.appendingPathComponent("Sources")
        guard let walk = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil) else {
            throw XCTSkip("cannot enumerate \(sources.path)")
        }
        let prefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var out: [String] = []
        for case let url as URL in walk where url.pathExtension == "swift" {
            out.append(url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path)
        }
        XCTAssertFalse(out.isEmpty, "no Swift source found — a green here would be meaningless")
        return out.sorted()
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw XCTSkip("""
            source tree not present at \(sources.path) — the scanning tests here read source \
            text, so they SKIP rather than reporting a green they did not earn
            """)
        }
        return root
    }

    private func rawLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Every non-empty line of `path` with comments removed — whole-line AND trailing. Stripping
    /// is load-bearing here: this file's own subject is documented in a long prose header that
    /// repeats the marker and most labels, and so is the emitter's doc comment.
    ///
    /// The quote-parity check approximates "is this `//` inside a string literal", and it fails in
    /// BOTH directions — an escaped quote or a `"""` delimiter leaves odd parity and the comment
    /// survives the cut. Copied verbatim from `SoundPromptHasADoorTests`, which measured the
    /// residue: six lines in `Sources/` keep a `//` after stripping, all of them URLs inside
    /// string literals. None of them carries this file's marker.
    private func codeLines(_ path: String) throws -> [String] {
        try rawLines(path)
            .map { Self.stripComment($0) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func stripComment(_ line: String) -> String {
        var quotes = 0
        var previous: Character?
        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]
            if ch == "\"" { quotes += 1 }
            if ch == "/", previous == "/", quotes % 2 == 0 {
                return String(line[line.startIndex..<line.index(before: index)])
            }
            previous = ch
            index = line.index(after: index)
        }
        return line
    }
}
