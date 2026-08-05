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
// line closes both gaps: it fires on every launch, before any playing, and it names the restored
// musical identity. The next occurrence has to be answerable from ONE pasted log.
//
// ⛔ HONEST LIMITS, because a guard that oversells itself is the failure mode this bundle exists
// to prevent — and the first version of this header oversold two of the four tests.
//   · Three tests are SOURCE SCANS. They prove which LABEL STRINGS the emitted line contains and
//     that the call is written — never that a label is bound to the value it names (`genre=` would
//     pass for `genre=\(scale.rawValue)`), and never that the line reaches a device log at all
//     (`EchoelCrashLog.breadcrumb` no-ops when its fd is closed, and there is no simulator here).
//   · The fourth is the ORDERING test, and it is the one that guards the property the design
//     actually rests on. It is still a scan — it reads line positions, not runtime behaviour.
//   · NONE of them can say whether the value printed is the one that detuned anything. That is the
//     founder's ear against a future log.
// House pattern: `SoundPromptHasADoorTests`, `SoundPanelPresetBarTests`,
// `BioApplyRateIsTheDedupedRateTests`.
//
// ⛔ AND WHAT IS DELIBERATELY *NOT* HERE. The first version asserted that `touch.patchID` and
// `touch.glide` default to neutral on a fresh install, and its commit message called that "the
// premise of the whole diagnosis, under a test for the first time". Both halves were wrong:
// `TouchSurfaceStorageKeysTests` already pins those two exact defaults, in this same blocking
// bundle — with an explicit note that the comparison must be EXACT because these are constants
// compared to constants. Duplicating it here (and with an `accuracy:` overlay its sibling
// expressly argues against) added no coverage and one contradiction. Deleted; that premise is
// guarded there.

import Foundation
import XCTest
@testable import Echoelmusic

final class LaunchLogsWhatItWokeUpWithTests: XCTestCase {

    private static let sourceFile = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// The breadcrumb's own prefix. Deliberately distinct from `generate[` so the two lines can
    /// never be confused in a pasted log — they report different moments and different scopes.
    private static let marker = "launch/musical:"

    /// The function that emits it, and the name the launch restore must call.
    private static let emitter = "logLaunchMusicalIdentity"

    /// The LABEL STRINGS the emitted line must contain — not, despite how it reads, a proof that
    /// each label is bound to the value it names. See the header's honest-limits block.
    ///
    /// ⛔ THIS IS NOT "every persisted musical key", and the first version claimed it was. It is a
    /// deliberate TEN, chosen as the values that (a) survive a relaunch, (b) are applied during the
    /// launch restore, and (c) change the PITCH or the RHYTHM of every take rather than one voice's
    /// colour. Knowingly outside: `touch.slideVibrato`/`slideChorus`/`life`, `touch.sync.strength`,
    /// the `field.autoPlay.*` block, `studio.lockBPM`/`lockedBPM`, `studio.fxCharacter`. A future
    /// investigation must NOT read their absence as "ruled out" — it means unlogged. Widen the line
    /// and this list together when one of them becomes a suspect.
    ///
    /// Adding a persisted key that meets (a)+(b)+(c)? Add its label here in the SAME commit.
    private static let requiredLabels = [
        "key=",            // studio.rootIndex + studio.scale — which notes exist
        "tuning=",         // toneSystemID — the only key that bends the INTERVAL between two notes
        "a4=",             // echoel.a4Hz — concert pitch, applied to all six voices at launch
        "genre=",          // studio.genre — and the roster clamp can rewrite it during restore
        "preset=",         // studio.presetIndex — restores a factory timbre over the genre's own
        "articulation=",   // studio.articulation — the persisted Pluck↔Pad envelope
        "bassRhythm=",     // studio.bassRhythm — a stored character overrides EVERY genre's bassline
        "padRhythm=",      // studio.padRhythm  — same, on the biggest audible surface since #166/#167
        "touchPatch=",     // touch.patchID — the one launch path that reads USER-authored JSON
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

    // MARK: - Where the call sits — the property the whole design rests on

    /// ⭐ THE ONE CLAIM A CALL-SITE COUNT CANNOT SEE, and the first version of this file did not
    /// guard it at all. The emitter's doc comment states the placement as an absolute — "CALLED
    /// LAST IN `onAppear`, ON PURPOSE … Move it earlier and it prints a de-curated genre that the
    /// clamp has already replaced." Move the call to `:1007`, or into a button handler, and every
    /// other test here stays green while the line reports a genre the clamp then overwrites.
    ///
    /// Checked: the call is INSIDE the root `.onAppear` closure, and comes after both restore
    /// steps whose ordering the doc comment names — the `MusicStyle.offered` clamp (which can
    /// REWRITE `studio.genre`) and `syncTouchSound()`.
    ///
    /// ⛔ Ordering only, NOT adjacency. Requiring the call to sit immediately after
    /// `syncTouchSound()` would go red on a legitimately-added restore step, and a guard that
    /// punishes correct work gets deleted rather than obeyed.
    ///
    /// ⛔ The closure's end is found by brace-counting over comment-stripped lines. A `{` or `}`
    /// inside a STRING LITERAL in this range would miscount it — stated rather than assumed,
    /// because `codeLines`' own doc records that the strip fails in both directions.
    func testTheCallSitsInsideOnAppearAfterEveryRestoreItClaims() throws {
        let lines = try rawLines(Self.sourceFile)

        guard let openIndex = soleIndex(of: ".onAppear {", in: lines, label: "the root .onAppear"),
              let clampIndex = soleIndex(of: "MusicStyle.offered.contains(style)", in: lines,
                                         label: "the genre-roster clamp"),
              let touchIndex = soleIndex(of: "syncTouchSound() }", in: lines,
                                         label: "the launch touch-patch restore"),
              let callIndex = soleIndex(of: "\(Self.emitter)()", in: lines,
                                        label: "the breadcrumb call", excluding: "func ")
        else { return }   // soleIndex already recorded the failure

        // Walk to the line that closes `.onAppear {`.
        var depth = 0
        var closeIndex: Int?
        for i in openIndex..<lines.count {
            let code = Self.stripComment(lines[i])
            depth += code.filter { $0 == "{" }.count
            depth -= code.filter { $0 == "}" }.count
            if depth <= 0 { closeIndex = i; break }
        }
        guard let end = closeIndex else {
            XCTFail("could not find the line closing `.onAppear {` (opened at line \(openIndex + 1))")
            return
        }

        XCTAssertTrue(callIndex > openIndex && callIndex < end, """
        `\(Self.emitter)()` is at line \(callIndex + 1), outside the root `.onAppear` closure \
        (lines \(openIndex + 1)–\(end + 1)) in \(Self.sourceFile).

        The diagnostic only means anything if it fires on EVERY launch. Called from a button, a \
        panel or a second lifecycle hook, it reports whatever state that moment happens to hold \
        — and the header's claim "it fires on every launch, before any playing" becomes false \
        with nothing failing.
        """)

        XCTAssertTrue(clampIndex < callIndex, """
        `\(Self.emitter)()` (line \(callIndex + 1)) now runs BEFORE the `MusicStyle.offered` \
        clamp (line \(clampIndex + 1)).

        That clamp can REWRITE `studio.genre` during the restore. Logging first prints the \
        de-curated genre the user is not hearing — the exact misreading this ordering exists to \
        prevent.
        """)

        XCTAssertTrue(touchIndex < callIndex, """
        `\(Self.emitter)()` (line \(callIndex + 1)) now runs BEFORE the launch touch-patch \
        restore (line \(touchIndex + 1)).

        `touchPatch=` would then report the selection before it was acted on. Keep the log line \
        last in the restore, or update the emitter's doc comment in the same commit — it states \
        this ordering as the reason for the placement.
        """)
    }

    // MARK: - What the line must say

    /// The payload is the whole value of the line. A breadcrumb that fires on every launch and
    /// names three of ten persisted keys still leaves seven un-rulable.
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
    /// "improvement" to this line is to print WHICH custom patch is loaded — i.e. put
    /// `touchPatchID`, a UUID, into a log the founder pastes into a chat. The diagnostic question
    /// is only whether a user-authored patch is selected at all, so the identifier buys nothing
    /// and the presence flag ("take"/"custom") answers it completely.
    ///
    /// ⛔ THE GUARD IS NARROWER THAN THE RULE. It rejects the name `touchPatchID` appearing in the
    /// emitted line at all — which covers `\(touchPatchID)` and `\(touchPatchID.prefix(8))` alike
    /// — but a hoisted `let id = touchPatchID` interpolated as `\(id)` walks straight past it.
    /// Saying so is better than a reassurance that cannot hold: the real enforcement is this
    /// comment plus review, and the test is the cheap half.
    func testTheLineDoesNotLeakTheCustomPatchIdentifier() throws {
        let line = try breadcrumbLine()
        XCTAssertFalse(line.contains("touchPatchID"), """
        the "\(Self.marker)" breadcrumb names `touchPatchID` directly:
        \(line)

        That risks writing a raw UUID into a diagnostic log the founder pastes into chat threads. \
        Log the PRESENCE instead (`touchPatchID.isEmpty ? "take" : "custom"`, hoisted above the \
        breadcrumb), which answers the only question the line is asked.
        """)
    }

    // MARK: - Source access

    /// The single emitted line, with comments stripped so prose can never stand in for code.
    ///
    /// ⛔ The first version justified the stripping with a claim it had not checked — that the
    /// emitter's doc comment "quotes the marker and several labels verbatim". It quotes neither.
    /// What the stripping actually earns is narrower and still worth having: `EchoelStudioView`
    /// carries long prose about the `generate[…]` breadcrumb and about this very line, and a raw
    /// scan would eventually match one of those instead of the code.
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

    /// The index of the ONE code line containing `needle`. Uniqueness is what makes the index
    /// comparisons above mean anything — two matches and the ordering test would silently be
    /// comparing the wrong pair.
    ///
    /// ⛔ FAILS, NEVER SKIPS, and the first version of this helper did skip. The reasoning that
    /// produced the skip was that a broken anchor is the test's problem, not the product's — true,
    /// and beside the point: duplicate the call to a second site and a skipping version would go
    /// quiet in exactly the situation where the ordering is no longer guaranteed. That is the
    /// self-disarming guard this repo already had to fix once (#367's Nachlese). An ambiguous
    /// anchor means the property is UNVERIFIABLE, and unverifiable must read as red.
    ///
    /// `XCTSkip` stays only in `repoRoot()`/`swiftSourcePaths()`, where nothing failed and the
    /// tree genuinely is not there.
    private func soleIndex(of needle: String, in lines: [String], label: String,
                           excluding banned: String? = nil) -> Int? {
        var found: [Int] = []
        for (i, raw) in lines.enumerated() {
            let code = Self.stripComment(raw)
            guard code.contains(needle) else { continue }
            if let banned, code.contains(banned) { continue }
            found.append(i)
        }
        guard found.count == 1, let only = found.first else {
            XCTFail("""
            expected exactly ONE code line for \(label) ("\(needle)") in \(Self.sourceFile), \
            found \(found.count) at lines \(found.map { $0 + 1 }).

            The ordering this file guards cannot be checked while the anchor is ambiguous, so it \
            reports red rather than quiet. Re-anchor it in the same commit that moved or \
            duplicated the line.
            """)
            return nil
        }
        return only
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
            source tree not present at \(sources.path) — every test here reads source text, so \
            they SKIP rather than reporting a green they did not earn
            """)
        }
        return root
    }

    private func rawLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// Every non-empty line of `path` with comments removed — whole-line AND trailing.
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
