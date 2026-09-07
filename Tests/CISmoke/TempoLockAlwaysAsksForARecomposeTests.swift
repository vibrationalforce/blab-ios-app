// TempoLockAlwaysAsksForARecomposeTests.swift
// Echoel — the tempo lock has three doors; all three must ring the same bell.
//
// WHAT THIS GUARDS (#356). `studio.lockBPM` has three DOORS and four assignment statements
// (plus a FIFTH write that is not a door and is silent by design — `EchoelStudioView.open(_:)`
// restoring the lock from the take's saved mode, #494; claim 1 names it as its third shape):
//   1. the Flow | Loop picker      — `WorkspaceView.modeBinding`        (1 write)
//   2. the transport lock button   — `BodyTempoField.toggleLock`        (2 writes, one per
//                                     branch; its one caller posts via `onLockChanged`)
//   3. tap tempo                   — `EchoelStudioView.tapTempoRow`     (1 write)
// (⛔ This header said "exactly three places" while the ⛔ block on `isLockWrite` below spoke
// of a wrongly-reported FIFTH site — which only parses if four is the true count, and the
// usage note listed three offsets for four sites. Doors and writes are different things and
// this file enumerates WRITES; both numbers are spelled out now.)
//
// Two doors posted `.echoelCompositionEdited` with the object `"tempoLock"`; the tap did
// not. That post is the ONLY path to `recomposeIfRunning()` — there is no
// `onChange(of: lockBPM)` in the app. So tapping a tempo moved the clock and left the take
// generated for the OLD tempo, and it flipped the composition mode Flow→Loop with nothing
// audible to explain the flip.
//
// ⭐ WHY A FILE-SCOPED CHECK WOULD HAVE PASSED THE BUG, and this one does not.
// The obvious guard is "a file that writes `lockBPM` must mention `tempoLock`".
// `EchoelStudioView.swift` mentions it — `case "tempoLock":` is the RECEIVER, sitting many
// members ABOVE the write that skipped it. The defect lived between a writer and a receiver
// that were both present in the same file, so only a check anchored at the WRITE SITE can
// see it. That is the whole reason for the window below, and it is worth the brittleness a
// window costs.
// (⛔ The first version said "forty lines" and put the receiver BELOW the write; the review
// measured 65 and above. Both are already wrong again — the Nachlese comments at the write
// pushed it to 78, in the same commit that corrected the number. The distance is not part of
// the argument, so it is gone: no number, nothing to rot. That is the general fix for this
// class, not a more careful count.)
//
// ⚠️ HONEST LIMITS — read these before trusting a green.
// · The window is 12 comment-free code lines FORWARD from the write. Today the four DOOR
//   sites need 1, 1, 2 and 7 (the fifth, the #494 restore, is matched on its own line and
//   needs no window) — so the slack is real only for `BodyTempoField.toggleLock`; the
//   other three sit at 1–2 and almost any refactor there reds this. A post placed BEFORE
//   the write, or behind a helper called from further away, also reds it while being
//   perfectly correct — fix the guard in that commit rather than deleting it, and say what
//   the new shape is.
// · It recognises a write as `lockBPM` followed by `=` (and not `==`, and not a
//   declaration). NOT caught: `UserDefaults.standard.set(true, forKey: "studio.lockBPM")`,
//   `lockBPM.toggle()`, and any write routed through a `Binding`'s `wrappedValue`. Nothing
//   does any of those today; `EchoelmusicApp.swift:986` only READS the key that way.
// · FALSE positive, latent: `codeLines` drops only WHOLE-line comments, so a trailing
//   `// lockBPM = true` on a code line would be reported as a write site. No line in
//   `Sources/` does that today.
// · `onLockChanged` is accepted as "handed the change on" WITHOUT proving that any caller
//   posts. `BodyTempoField`'s parameter defaults to a no-op (`= {}`), so a second
//   `BodyTempoField(compact:)` built without the argument would pass this guard and post
//   nothing — the same defect, one level of indirection out. One call site exists today and
//   it posts (`WorkspaceView.swift`). Closing this would mean following the callee's callers,
//   which is past what a text scan should attempt; it is written down instead.
// · Source-text scan, no simulator. `Tests/CISmoke` is the blocking bundle. SKIPS rather
//   than passes if the tree is not at this file's compile-time path.

import Foundation
import XCTest

final class TempoLockAlwaysAsksForARecomposeTests: XCTestCase {

    /// How far past a write the hook may sit, counted in code lines (comments removed).
    /// Deliberately generous — the point is proximity to the write, not a style rule.
    private static let window = 12

    /// Every place that writes the tempo lock must hand the change on: either by posting the
    /// shared `"tempoLock"` hook, or by calling the `onLockChanged` callback whose caller
    /// posts it. A write that does neither is silent, and silence here means the take keeps
    /// the note density it was generated with while the clock runs at a different tempo.
    func testEveryTempoLockWriteHandsTheChangeOn() throws {
        let sites = try lockWriteSites()

        // ⛔ THIS WAS `XCTAssertFalse(sites.isEmpty)`, WHICH ONLY PROVED THE PARSER RAN.
        // Delete `tapTempoRow` and three compliant sites remain — green, in the file named
        // after that one door. Anchoring on the file (not on a hard count of 4) keeps a
        // legitimate FOURTH door from reddening this while still pinning the site this
        // guard exists for.
        XCTAssertTrue(sites.contains { $0.file.hasSuffix("Studio/EchoelStudioView.swift") }, """
            no write to `lockBPM` in `Studio/EchoelStudioView.swift`. Either tap tempo lost \
            its lock — in which case #356 no longer applies and this guard should say so — \
            or the parse failed and every green below is meaningless. Sites found: \
            \(sites.isEmpty ? "none" : sites.map { "\($0.file):\($0.line)" }.joined(separator: ", ")).
            """)

        for site in sites {
            let joined = site.window.joined(separator: " ")
            let posts = joined.contains("NotificationCenter") && joined.contains("\"tempoLock\"")
            let delegates = joined.contains("onLockChanged")
            // ⭐ THE THIRD COMPLIANT SHAPE, AND IT IS SILENT ON PURPOSE (#494, 2026-08-08).
            // `open(_:)` restores the lock from the take's saved mode — `lockBPM = (savedMode ==
            // .studioLocked)` — and posting there would be the bug: a loaded take's SAVED notes
            // must not be recomposed away, as the site's own comment says. Recognised by the
            // write's RIGHT-HAND SIDE, not by a nearby mention of `savedMode`: a new silent
            // write that merely sits near one does not pass.
            // ⛔ This guard was RED on that site from #494 until #1097 — a month and every
            // deploy in it — because the job-log window (#807) never carried its line. The
            // #1093 sweep's transcription found it; no gate did.
            let restoresSavedMode = site.code.hasSuffix("= (savedMode == .studioLocked)")
            XCTAssertTrue(posts || delegates || restoresSavedMode, """
                \(site.file):\(site.line) writes the tempo lock and then neither posts the \
                shared hook nor calls `onLockChanged` within \(Self.window) code lines, and \
                it is not the `open(_:)` restore of a take's saved mode:

                    \(site.code)

                `.echoelCompositionEdited` with the object "tempoLock" is the ONLY thing that \
                reaches `recomposeIfRunning()` — there is no `onChange(of: lockBPM)` in the \
                app. Without it the mode flips Flow→Loop and the running take keeps composing \
                for the tempo it no longer has. That was #356, and it sat in shipped code for \
                as long as tap tempo existed. Add:

                    NotificationCenter.default.post(name: .echoelCompositionEdited,
                                                    object: "tempoLock")

                AFTER the write (every reader resolves the tempo from the clock and the lock, \
                and `post` is synchronous, so both must already be true).
                """)
        }
    }

    /// The hook this file insists on must still DO something. If the receiver stops
    /// recomposing, the test above would go on happily guarding a notification into a void.
    func testTheHookStillReachesARecompose() throws {
        let code = try codeLines("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        guard let receiver = code.firstIndex(where: { $0.code.contains("case \"tempoLock\":") }) else {
            return XCTFail("""
                `EchoelStudioView` no longer handles the "tempoLock" case. Three doors post \
                that object; if nothing switches on it, all three are writing to a notification \
                nobody reads.
                """)
        }
        let body = code[receiver..<min(receiver + 6, code.endIndex)].map(\.code).joined(separator: " ")
        XCTAssertTrue(body.contains("recomposeIfRunning"), """
            The "tempoLock" case no longer calls `recomposeIfRunning()`:

                \(body)

            That call is the audible half of a tempo lock. If the recompose moved somewhere \
            else, point this guard at the new place — do not let the three posting doors go on \
            claiming an effect that has left.
            """)
    }

    /// Tapping a tempo also changes the composition MODE. The control has to say so — the
    /// doc comment always did, the hint never did until #356.
    func testTapTempoSaysThatItAlsoLocks() throws {
        let code = try codeLines("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        let hints = code.map(\.code).filter { $0.contains("Tap in time to set the tempo") }
        XCTAssertEqual(hints.count, 1, """
            Expected exactly one "Tap in time to set the tempo" hint, found \(hints.count). \
            A second copy is a second thing to keep true.
            """)
        XCTAssertTrue(hints.first?.contains("lock") == true, """
            The tap-tempo hint no longer mentions that tapping LOCKS the tempo:

                \(hints.first ?? "—")

            The tap is the only control in the app that changes the Flow|Loop mode without \
            being labelled as a mode control. VoiceOver reads hints in full and this one is \
            one sentence past the action — keep it that length. (⛔ This sentence quoted "an \
            app median near 57" while the source comment beside the hint quoted the measured \
            61.5, one commit, two numbers for one fact. The measurement lives at the hint, \
            with the method; do not restate it here.)
            """)
    }

    // MARK: - Reading the source

    private struct Site {
        let file: String
        let line: Int
        let code: String
        let window: [String]
    }

    private struct CodeLine {
        let number: Int
        let code: String
    }

    /// Every `lockBPM` write under `Sources/Echoelmusic/`, with the code lines that follow it.
    private func lockWriteSites() throws -> [Site] {
        let root = try repoRoot()
        let sources = root.appendingPathComponent("Sources/Echoelmusic")
        guard let walk = FileManager.default.enumerator(atPath: sources.path) else {
            throw XCTSkip("could not enumerate \(sources.path)")
        }
        var out: [Site] = []
        for case let relative as String in walk where relative.hasSuffix(".swift") {
            let lines = try codeLines("Sources/Echoelmusic/\(relative)")
            for (index, line) in lines.enumerated() where Self.isLockWrite(line.code) {
                let end = min(index + 1 + Self.window, lines.endIndex)
                out.append(Site(file: relative,
                                line: line.number,
                                code: line.code.trimmingCharacters(in: .whitespaces),
                                window: lines[index..<end].map(\.code)))
            }
        }
        return out.sorted { ($0.file, $0.line) < ($1.file, $1.line) }
    }

    /// A write is `lockBPM` followed by a single `=`, where the name is not being DECLARED.
    /// Comparisons (`==`) are not writes; nor is `"studio.lockBPM"` inside a string, whose
    /// next character is the closing quote.
    ///
    /// ⛔ THE FIRST VERSION EXCLUDED ONLY `var lockBPM` AND REPORTED A FIFTH SITE:
    /// `StudioDefaultKeys.swift` declares `public static let lockBPM = StudioDefault(…)` —
    /// the key's own definition, which of course posts nothing. Caught by re-deriving the
    /// assertion outside Swift before committing, which is the only compiler this repo has.
    /// Excluding `let` as well as `var` is the fix; excluding the FILE would have been the
    /// mistake, because a real write could land there later.
    ///
    /// Checks EVERY occurrence in the line, not just the first: `@AppStorage("studio.lockBPM")
    /// private var lockBPM = false` has two, and only the second looks like an assignment.
    private static func isLockWrite(_ code: String) -> Bool {
        var searchStart = code.startIndex
        while let found = code.range(of: "lockBPM", range: searchStart..<code.endIndex) {
            let before = code[..<found.lowerBound]
            let declares = before.hasSuffix("var ") || before.hasSuffix("let ")
            let rest = code[found.upperBound...].drop { $0 == " " }
            if !declares, rest.first == "=", rest.dropFirst().first != "=" { return true }
            searchStart = found.upperBound
        }
        return false
    }

    /// Numbered lines of `path` that are neither blank nor whole-line comments.
    private func codeLines(_ path: String) throws -> [CodeLine] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .compactMap { offset, raw -> CodeLine? in
                let trimmed = raw.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("//") else { return nil }
                return CodeLine(number: offset + 1, code: String(raw))
            }
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let probe = root.appendingPathComponent("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        guard FileManager.default.fileExists(atPath: probe.path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }
}
