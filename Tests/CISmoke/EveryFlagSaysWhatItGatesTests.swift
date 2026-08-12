// EveryFlagSaysWhatItGatesTests.swift
// Echoel — the switchboard's summary described a build it does not have. #526.
//
// WHAT WAS WRONG, and it was the two lines a session reads to answer "is it safe to assume
// this flag is off". `FeatureFlags`'s enum doc said "All OFF until their layer's gate is
// device-verified (never flip a default before then)" — while THREE cases in the same enum,
// twenty lines below, say "DEFAULT-ON" in their own doc. `UserDefaults.register(defaults:)`
// runs at startup for `multiRoll`, `voiceKindRouting` and `instrumentHome`, and those three
// are the ones that decide what the app IS: per-lane voices, heterogeneous rack voices, and
// the front door it opens into. The summary was wrong for exactly the three that matter.
//
// ⭐ AND THE SECOND HALF IS BIGGER THAN THE FIRST. The file header promises that "every new
// spatial/collab capability ships behind a flag". Measured over `Sources/` with comments
// stripped: **ELEVEN of the sixteen flags have ZERO deciding readers** — nothing branches on
// them at all. A flag with no reader gates nothing, so whatever sits behind those eleven is
// inert because nothing CALLS it, never because a flag holds it back. CLAUDE.md already
// carries that exact correction — for `echoelAI` alone, written as if it were the singular
// case. It is one of eleven, and the other ten were never counted.
//
// ⭐ THIRD, AND IT IS THE ONE NOBODY HAD WRITTEN DOWN ANYWHERE: `FeatureFlags.set` has ZERO
// production call sites. No shipped surface can flip any flag. So the thirteen default-OFF
// flags are not "off until deliberately turned on" — they are off with no door, and for the
// two of them a branch really consults (`storeKit`, `audioLaneRecording`) that means built,
// compiling code no user or tester can reach. It is the same deadlock the founder named when
// the three keystone flags were registered ON instead: a default-OFF flag with no UI can
// never be device-verified, so its gate can never be lifted.
//
// ⚠️ THIS GUARD DOES NOT FORBID WIRING A FLAG UP (#364). Giving one of the eleven a reader is
// exactly the work this finding argues for; adding a door is too. What it forbids is doing
// either while the header keeps counting eleven. When `testEveryUnreadFlagIsNamedInTheCensus`
// goes red for that reason, the fix is to move the name out of the census IN THE SAME COMMIT,
// not to relax the assertion — the failure message says so.
//
// ⚠️ HONEST GRADING (#433/#464/#486). This file COMPILES against the parent tree — it names no
// symbol this commit adds — so every assertion really has a verdict there. Transcribed by hand
// (a Python rebuild of `SourceText.codeOnly` run against `git show HEAD:` and the worktree):
//   · **TWO needles are red on the parent, and they are ONE finding**: the header paragraph is
//     both wrong ("All OFF", unretracted) and missing (no census names the eleven). One
//     paragraph, two properties — reporting it twice is not two defects (#486).
//   · **THREE are counterweights**, green on both trees, and they are the value. A tree that
//     rewrites the prose and then quietly deletes `guard FeatureFlags.storeKit`, or registers
//     a fourth key ON, or ships a settings toggle, satisfies the two needles above and breaks
//     the thing they describe (#343).
//   · Nothing here proves the app behaves correctly. It proves a sentence and a measurement
//     still agree.
//
// ⚠️ `SourceText.codeOnly` IS LOAD-BEARING here, and that is MEASURED rather than assumed
// (#484 and #485 each had to withdraw the stronger claim once, #486 twice). `FeatureFlags.set(`
// appears in EIGHT comment lines across three files — `FeatureFlags` itself (4), `EchoelmusicApp`
// (2), `WorkspaceView` (2) — each one a rollback lever written out for a reader, and in CODE
// nowhere. So `testNothingInTheAppCanFlipAFlag` is **RED ON CORRECT CODE** without the stripper.
// The census flips too, and by exactly the flags this slice is about: measured on both trees,
// raw reports 8 of 16 as read and stripped reports 5. The three that flip — `spatialEngine`,
// `echoelAI`, `cameraExpression` — are named in prose ONLY, which is precisely the illusion the
// header census exists to dispel. A raw scan would have "found" three gates that do not exist.
//
// ⚠️ AND THE LIMIT FIRST. Every assertion here is a SOURCE SCAN. It proves where text is, not
// what the app runs — it cannot show that a flag is really off on a device, only that no line
// in `Sources/` consults it. `Tests/CISmoke` is the blocking bundle; a missing tree SKIPS
// rather than reporting a green it did not earn (#454).

import Foundation
import XCTest

final class EveryFlagSaysWhatItGatesTests: XCTestCase {

    private static let sourcesRoot = "Sources/Echoelmusic"
    private static let flagsFile = "Sources/Echoelmusic/Core/FeatureFlags.swift"

    /// The eleven with no deciding reader, as measured 2026-08-12.
    private static let expectedUnread: Set<String> = [
        "spatialEngine", "bioSpace", "echoelRender", "motionEngine", "showControl",
        "avObjects", "performerTracking", "liveCollab", "headTracking", "echoelAI",
        "cameraExpression"
    ]

    /// The three `register(defaults:)` keys — the only way a flag is ON in a shipped build.
    private static let expectedRegistered: Set<String> = [
        "multiRoll", "voiceKindRouting", "instrumentHome"
    ]

    // MARK: - The finding

    /// The summary must not claim every flag is off while three are registered ON.
    ///
    /// ⛔ SCOPED, not a bare absence scan, and that shape is the #525 lesson. The corrected
    /// doc quotes the withdrawn sentence verbatim in order to withdraw it, so a plain
    /// `contains` would be RED ON CORRECT CODE — and `codeOnly` is the wrong tool too, because
    /// the claim lives in a COMMENT on both trees and the stripper blanks it either way. What
    /// works is per-line: every line carrying the phrase must also carry `SAID`.
    func testTheSummaryNoLongerClaimsEveryFlagIsOff() throws {
        let phrase = "All OFF until"
        let offenders = try rawText(Self.flagsFile)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.contains(phrase) && !$0.contains("SAID") }
        XCTAssertTrue(offenders.isEmpty, """
            `FeatureFlags` asserts again that its flags are "\(phrase) …", outside a retraction:
            \(offenders.joined(separator: "\n"))
            Three of them are not off. `UserDefaults.register(defaults:)` runs at startup for \
            \(Self.expectedRegistered.sorted().joined(separator: ", ")) — the three that decide \
            per-lane voices, heterogeneous rack voices and the app's front door. Three cases in \
            this same enum already say "DEFAULT-ON" in their own doc; the summary above them \
            said the opposite, and the summary is what a session reads first.
            """)
    }

    /// Every flag nothing branches on must be named in the header census.
    ///
    /// Both directions matter. If a flag GAINS a reader the count drops and this goes red —
    /// that is welcome work, and the fix is to move its name out of the census in the same
    /// commit. If a flag LOSES its last reader it must be added to the census, because the
    /// header would otherwise claim a gate that no longer exists.
    func testEveryUnreadFlagIsNamedInTheCensus() throws {
        let unread = try flagsWithoutDecidingReaders()
        XCTAssertEqual(unread, Self.expectedUnread, """
            The set of flags nothing branches on has changed: \(unread.sorted().joined(separator: ", ")).
            If a flag gained a reader, that is the work this guard exists to encourage — move \
            its name OUT of the census block in `FeatureFlags.swift` in the same commit, and \
            check whether CLAUDE.md's `echoelAI` ⛔ block still reads as the singular case. If a \
            flag lost its last reader, add it: the header would otherwise describe a gate that \
            is no longer there.
            """)

        let header = try headerBlock()
        for flag in unread where !header.contains(flag) {
            XCTFail("""
                `\(flag)` has no deciding reader and is not named in `FeatureFlags.swift`'s \
                header census. A flag with no reader gates nothing — leaving it unnamed is how \
                the file went on promising that "every new spatial/collab capability ships \
                behind a flag" while eleven of sixteen gated nothing at all.
                """)
        }
    }

    // MARK: - Counterweights (#343)

    /// COUNTERWEIGHT — the five consulted flags must still be consulted, as BRANCHES.
    ///
    /// A tree that rewrites the prose above and drops `guard FeatureFlags.storeKit` passes both
    /// needles and loses the property they describe. Each needle below is a control-flow
    /// keyword plus the read, so a mere mention cannot satisfy it.
    func testTheConsultedFlagsStillDecideSomething() throws {
        let branches: [(file: String, needle: String, what: String)] = [
            ("Core/EchoelStore.swift", "guard FeatureFlags.storeKit",
             "launch must touch NO StoreKit while the flag is off"),
            ("EchoelmusicApp.swift", "if FeatureFlags.multiRoll",
             "the LaneVoiceRack fan-out is what MultiRoll gates"),
            ("Sequencer/LaneVoiceRack.swift", "if FeatureFlags.voiceKindRouting",
             "heterogeneous rack voices are what VoiceKindRouting gates"),
            ("EchoelmusicApp.swift", "FeatureFlags.audioLaneRecording",
             "the mic-capture wiring is what AudioLaneRecording gates"),
            ("Studio/WorkspaceView.swift", "if FeatureFlags.instrumentHome",
             "the instrument front door is what InstrumentHome gates")
        ]
        for branch in branches {
            let code = SourceText.codeOnly(try rawText("\(Self.sourcesRoot)/\(branch.file)"))
            XCTAssertTrue(code.contains(branch.needle), """
                `\(branch.file)` no longer branches on `\(branch.needle)`. \(branch.what). \
                Five of sixteen flags actually decide something in this build; removing one \
                makes the header's census wrong in the direction that reads as harmless.
                """)
        }
    }

    /// COUNTERWEIGHT — exactly three keys are registered ON, and they are the named three.
    ///
    /// A fourth `register(defaults:)` silently makes a flag default-ON while every doc in the
    /// file still calls it off. That is the defect this slice corrected, re-committed.
    func testExactlyThreeFlagsAreRegisteredDefaultOn() throws {
        let app = SourceText.codeOnly(try rawText("\(Self.sourcesRoot)/EchoelmusicApp.swift"))
        let keys = try flagKeys()
        let registrationLines = app
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.contains("register(defaults:") }
        var registered: Set<String> = []
        for line in registrationLines {
            for flag in keys where line.contains("Key.\(flag).rawValue") {
                registered.insert(flag)
            }
        }
        XCTAssertEqual(registered, Self.expectedRegistered, """
            The registered-ON set is now \(registered.sorted().joined(separator: ", ")) rather \
            than \(Self.expectedRegistered.sorted().joined(separator: ", ")). Registration is \
            the ONLY mechanism that makes a flag on in a shipped build, so a change here flips \
            real behaviour — update the ⛔ block in `FeatureFlags.swift` (which names these \
            three) in the same commit, and say in the case's own doc why it became DEFAULT-ON.
            """)
    }

    /// COUNTERWEIGHT — nothing in the app can flip a flag.
    ///
    /// This is what makes "off by default" mean "off, permanently, with no door" for the
    /// thirteen. The day a developer/staging surface ships, this goes red — correctly: the
    /// header's ⭐ block argues from the absence of exactly this.
    func testNothingInTheAppCanFlipAFlag() throws {
        let writers = try filesUnderSources(containing: "FeatureFlags.set(")
        XCTAssertTrue(writers.isEmpty, """
            `FeatureFlags.set(` is now called from \(writers.joined(separator: ", ")). That is a \
            door, and it changes the header's ⭐ block from true to false: the thirteen \
            default-OFF flags would no longer be unreachable, and `storeKit` / \
            `audioLaneRecording` would become device-verifiable. Rewrite that block in the same \
            commit rather than deleting this assertion.
            """)
    }

    // MARK: - Reading the source

    /// Flags whose name appears after `FeatureFlags.` (or `isOn(.`) in the CODE of any file
    /// other than the declaration itself.
    ///
    /// ⛔ Comments are stripped, and that is load-bearing rather than hygienic: doc comments
    /// quote flag names as rollback levers all over this repo. Raw, this reports 8 of 16 flags
    /// as read; stripped, 5 — and the three that flip (`spatialEngine`, `echoelAI`,
    /// `cameraExpression`) are named in prose only, which is the very illusion being measured.
    private func flagsWithoutDecidingReaders() throws -> Set<String> {
        let keys = try flagKeys()
        var read: Set<String> = []
        let root = try repoRoot().appendingPathComponent(Self.sourcesRoot)
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            throw XCTSkip("cannot enumerate \(Self.sourcesRoot) — refusing to report a green it did not earn")
        }
        for case let relative as String in walker where relative.hasSuffix(".swift") {
            if relative.hasSuffix("Core/FeatureFlags.swift") { continue }
            guard let text = try? String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            else { continue }
            let code = SourceText.codeOnly(text)
            for key in keys where code.contains("FeatureFlags.\(key)") || code.contains("isOn(.\(key)") {
                read.insert(key)
            }
        }
        return keys.subtracting(read)
    }

    /// The declared keys, read from the enum rather than restated here — a hand-kept list
    /// would answer a question about my memory instead of about the switchboard.
    private func flagKeys() throws -> Set<String> {
        let declarationLines = SourceText.codeOnly(try rawText(Self.flagsFile))
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.contains("= \"feature.") }
        var keys: Set<String> = []
        for line in declarationLines {
            guard let caseRange = line.range(of: "case "),
                  let equals = line.range(of: "=", range: caseRange.upperBound..<line.endIndex)
            else { continue }
            let name = line[caseRange.upperBound..<equals.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { keys.insert(name) }
        }
        XCTAssertFalse(keys.isEmpty, "no `feature.` keys parsed out of \(Self.flagsFile) — the anchor moved")
        return keys
    }

    /// Everything above `import Foundation`: the file's own account of itself.
    private func headerBlock() throws -> String {
        let raw = try rawText(Self.flagsFile)
        guard let importLine = raw.range(of: "\nimport Foundation") else {
            XCTFail("`import Foundation` is gone from \(Self.flagsFile) — the header anchor moved")
            return raw
        }
        return String(raw[raw.startIndex..<importLine.lowerBound])
    }

    private func filesUnderSources(containing needle: String) throws -> [String] {
        let root = try repoRoot().appendingPathComponent(Self.sourcesRoot)
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            throw XCTSkip("cannot enumerate \(Self.sourcesRoot) — refusing to report a green it did not earn")
        }
        var hits: [String] = []
        for case let relative as String in walker where relative.hasSuffix(".swift") {
            guard let text = try? String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8)
            else { continue }
            if SourceText.codeOnly(text).contains(needle) { hits.append(relative) }
        }
        return hits.sorted()
    }

    private func rawText(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw XCTSkip("""
                \(relativePath) is not present — this guard inspects source text, so it SKIPS \
                rather than reporting a green it did not earn (#454)
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    private func repoRoot() throws -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
