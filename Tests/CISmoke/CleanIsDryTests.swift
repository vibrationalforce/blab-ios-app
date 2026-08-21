// CleanIsDryTests.swift
// Echoel — "Clean (dry)" has to actually be dry, in the BLOCKING bundle.
//
// THE DEFECT (found 2026-07-29). `EchoelStudioView.applyFX()` stamps the chosen FX character
// onto the live chain and then, immediately after, calls `applyDelaySync(bpm:)`. That function
// ended with `synth.fxChain.delayEnabled = true` — unconditional, and one line past what its
// own doc comment promised ("Re-apply the user's tempo-synced delay note value … so the chosen
// division is never clobbered"; nothing about switching an effect ON).
//
// Two controls lied because of it:
//
//   1. Choosing **Clean** could not produce a dry signal. `FXCharacter.clean`'s preset sets
//      `delayEnabled: false` under the comment *"Everything off — a dry reset"*, and that value
//      survived for exactly one statement. Five of the twelve characters were affected —
//      `.clean`, `.telephone` and `.vinyl` say so outright, `.harmonizer` and `.room` inherit it
//      from `GenreFXPreset.init`'s default by omitting the parameter. No GENRE preset is
//      affected: every `MusicStyle.fxPreset` enables delay (`GenreFXTests`).
//   2. The **Delay switch** in the "All parameters" panel could not stay off. Switching it off
//      writes `chain.delayEnabled = false`; the next `applyFX()` or re-seed put it back, so the
//      switch flipped itself with no input from the user.
//
// THE RULE THIS FILE PINS: an AUTOMATIC re-stamp may set the delay TIME, never the enable. A
// direct user gesture may do both — the Effects panel's division picker arms the delay in its own
// `onChange`, because that row carries no enable of its own and a division that silently did
// nothing would be the same lying control one row over. That gesture is NOT what this file
// guards; the automatic path is.
//
// TWO GUARDS, because neither alone is enough:
//   • The BEHAVIOURAL one below pins what "Clean" MEANS — every stage off. It would not have
//     caught this defect, because the defect was a write that happened AFTER the preset landed.
//   • The SOURCE one pins the absence of that write. It is the ugly kind of test, and it is the
//     only kind that can reach a `private func` on a SwiftUI `View` with no local toolchain.
//
// ⚠️ THE BEHAVIOURAL HALF IS A DELIBERATE DUPLICATE. `Tests/EchoelmusicTests/FXCharacterTests`
// already pins "Clean resets a stamped chain to dry", and pinned it slightly harder than the
// first draft of this file did. The only reason for the copy is that it sits in the bundle which
// can turn a merge red — so it is kept at least as strong as the original rather than quietly
// becoming the weaker survivor.
//
// WHY HERE AND NOT `Tests/EchoelmusicTests`: that bundle builds only under `full-tests.yml`,
// which carries `continue-on-error: true` on both its build and its run step (#208).

import Foundation
import XCTest
@testable import Echoelmusic

final class CleanIsDryTests: XCTestCase {

    // MARK: - What "Clean" means

    /// Clean is a dry RESET, not "a bit less". Every switchable stage off, no saturation. The
    /// safety limiter is deliberately not a preset field and stays on — a "dry" character must
    /// never be a way to defeat the output protection.
    ///
    /// ⛔ #694 — THIS TEST'S DOC MADE THE WHOLE CLAIM AND ITS ASSERTIONS COVERED A THIRD OF IT.
    /// "Every switchable stage off" was written here from the first day; the body checked SIX of
    /// the fifteen flags `EchoelFXChain` declares (five off, plus the limiter on). It never
    /// looked at NINE — and seven of those nine were not merely unasserted, they were never
    /// RESET: tape, bitcrush, flanger, tremolo, granular, widener, compressor, exactly the ones
    /// `GenreFXPreset` cannot express. (`harmonizer` and `reverb` are the other two: unchecked,
    /// but written false by the preset, so they were correct by luck rather than by assertion.)
    /// A guard whose PROSE is complete and whose ASSERTIONS are a subset reads as covered and is
    /// not; that is the same defect shape as an enumerating hint under the word "every".
    ///
    /// ⚠️ THE FIRST DRAFT OF THIS VERY PARAGRAPH WROTE "five of the fifteen" AND "the seven it
    /// never looked at", which merged two different quantities into one tidy pair — checked
    /// versus reset. Corrected before commit. In a file about a claim that was complete in prose
    /// and partial in fact, that is the last arithmetic that should be rounded.
    ///
    /// ⛔ AND THE FIXTURE WAS THE REASON IT COULD HIDE. It used to stamp `.underwater` to get a
    /// wet starting state, which arms three stages — so twelve assertions could only ever have
    /// compared `false` against `false`. The file said so about ONE of them ("that protection
    /// does NOT extend to the phaser … its assertion below cannot fail") and stopped there. The
    /// fixture now arms all fifteen by hand: every assertion below has something to disprove.
    func testTheCleanCharacterLeavesEveryStageOff() {
        let chain = EchoelFXChain()
        for flag in Self.switchable { Self.set(flag, true, on: chain) }
        chain.limiterEnabled = true

        // Precondition, asserted rather than assumed: the setter table above must really have
        // moved the chain. A typo in it would otherwise make the whole test vacuous again — the
        // precise failure this rewrite exists to end.
        let armed = Self.switchable.filter { Self.read($0, on: chain) }
        XCTAssertEqual(armed.count, Self.switchable.count, """
            precondition failed: only \(armed.count) of \(Self.switchable.count) stages armed. \
            The setter table in this file does not reach the chain, so every assertion below \
            would compare false against false. Fix the table, do not relax the test.
            """)

        FXCharacter.clean.apply(to: chain, bpm: 120, genre: .dubTechno)

        let stillOn = Self.switchable.filter { Self.read($0, on: chain) }
        XCTAssertTrue(stillOn.isEmpty, """
            "Clean (dry) — No effects, reset to a dry signal" left \(stillOn.count) stage(s) \
            running: \(stillOn.joined(separator: ", ")).

            `GenreFXPreset` carries seven enables and the chain has fifteen, so the preset alone \
            cannot reset the chain. `FXCharacter.apply` adds the missing writes for `.clean` \
            only (#694) — a genre stamp is a character laid over what the player built, not a \
            reset, so the same step deliberately does NOT run for `.auto` or a genre.
            """)
        XCTAssertTrue(chain.limiterEnabled, """
            the safety limiter is never disabled by a character — "dry" must not become a way \
            to defeat the output protection. It is the ONE flag `.clean` must leave alone.
            """)
    }

    /// ⭐ THE ANTI-ROT HALF, and the reason the list above is worth having. The stage names are
    /// enumerated by hand in this file — they have to be, because Swift has no reflection over
    /// stored properties here — so a SIXTEENTH stage would be silently outside every assertion,
    /// which is precisely how the seven above stayed invisible for months. This reads the flags
    /// out of `EchoelFXChain.swift` and fails when the two disagree, naming the difference.
    ///
    /// ⚠️ IT DOES NOT DECIDE WHAT THE NEW STAGE SHOULD DO (#364). A new flag might legitimately
    /// belong with the limiter rather than with the seven; the guard's job is to make that a
    /// decision somebody takes, not one that happens by omission.
    func testTheDryResetCoversEveryEnableTheChainDeclares() throws {
        let url = try repoRoot()
            .appendingPathComponent("Sources/Echoelmusic/DSP/EchoelFXChain.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        var declared: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("public var "), t.contains("Enabled: Bool") else { continue }
            let after = t.dropFirst("public var ".count)
            guard let colon = after.firstIndex(of: ":") else { continue }
            declared.append(String(after[..<colon]))
        }
        XCTAssertGreaterThan(declared.count, 10, """
            Only \(declared.count) `public var …Enabled: Bool` declarations found in \
            `EchoelFXChain.swift`. The scan lost its needle and the comparison below would pass \
            on almost anything — re-point the extraction, do not relax it.
            """)

        let known = Set(Self.switchable + ["limiterEnabled"])
        let unknown = declared.filter { !known.contains($0) }.sorted()
        XCTAssertTrue(unknown.isEmpty, """
            `EchoelFXChain` declares \(unknown.count) enable(s) this file has never heard of: \
            \(unknown.joined(separator: ", ")).

            Decide, in the commit that added them: does "Clean (dry)" silence this stage, or is \
            it protection like the limiter? Then add the name to `switchable` (plus its two \
            lines in `set`/`read`) or to the limiter side, and add the write in \
            `FXCharacter.apply`. Doing nothing means the new stage keeps playing under a \
            control that says "No effects".
            """)
        let missing = known.filter { name in !declared.contains(name) }.sorted()
        XCTAssertTrue(missing.isEmpty, """
            This file names \(missing.count) enable(s) the chain no longer declares: \
            \(missing.joined(separator: ", ")). A stage was renamed or removed; move this list \
            with it rather than leaving a name that can never be checked.
            """)
    }

    // MARK: - The stage table

    /// Every enable a character may switch OFF. `limiterEnabled` is deliberately absent — see
    /// the two tests above. Kept as strings with hand-written accessors because there is no
    /// key-path table over these and no reflection; the derived test above is what keeps the
    /// list honest.
    private static let switchable = [
        "filterEnabled", "saturationEnabled", "tapeEnabled", "bitcrushEnabled",
        "harmonizerEnabled", "chorusEnabled", "flangerEnabled", "granularEnabled",
        "phaserEnabled", "tremoloEnabled", "delayEnabled", "reverbEnabled",
        "widenerEnabled", "compressorEnabled",
    ]

    private static func set(_ name: String, _ value: Bool, on chain: EchoelFXChain) {
        switch name {
        case "filterEnabled":     chain.filterEnabled = value
        case "saturationEnabled": chain.saturationEnabled = value
        case "tapeEnabled":       chain.tapeEnabled = value
        case "bitcrushEnabled":   chain.bitcrushEnabled = value
        case "harmonizerEnabled": chain.harmonizerEnabled = value
        case "chorusEnabled":     chain.chorusEnabled = value
        case "flangerEnabled":    chain.flangerEnabled = value
        case "granularEnabled":   chain.granularEnabled = value
        case "phaserEnabled":     chain.phaserEnabled = value
        case "tremoloEnabled":    chain.tremoloEnabled = value
        case "delayEnabled":      chain.delayEnabled = value
        case "reverbEnabled":     chain.reverbEnabled = value
        case "widenerEnabled":    chain.widenerEnabled = value
        case "compressorEnabled": chain.compressorEnabled = value
        default: XCTFail("no setter for \(name) — add it beside its entry in `switchable`")
        }
    }

    private static func read(_ name: String, on chain: EchoelFXChain) -> Bool {
        switch name {
        case "filterEnabled":     return chain.filterEnabled
        case "saturationEnabled": return chain.saturationEnabled
        case "tapeEnabled":       return chain.tapeEnabled
        case "bitcrushEnabled":   return chain.bitcrushEnabled
        case "harmonizerEnabled": return chain.harmonizerEnabled
        case "chorusEnabled":     return chain.chorusEnabled
        case "flangerEnabled":    return chain.flangerEnabled
        case "granularEnabled":   return chain.granularEnabled
        case "phaserEnabled":     return chain.phaserEnabled
        case "tremoloEnabled":    return chain.tremoloEnabled
        case "delayEnabled":      return chain.delayEnabled
        case "reverbEnabled":     return chain.reverbEnabled
        case "widenerEnabled":    return chain.widenerEnabled
        case "compressorEnabled": return chain.compressorEnabled
        default: XCTFail("no reader for \(name) — add it beside its entry in `switchable`")
                 return false
        }
    }

    /// Clean is not the only dry configuration, so it is not the only thing the removed write
    /// broke. `.telephone` is a bandpass with the delay deliberately off — proof that
    /// `delayEnabled: false` is a real, reachable preset value and not a one-off in `.clean`.
    /// (`.vinyl` says the same outright; `.harmonizer` and `.room` inherit it by omitting the
    /// parameter. Five of twelve characters in total — deliberately NOT enumerated as assertions
    /// here, because a per-character table would go stale the moment a character is re-voiced,
    /// and the rule being pinned is about `applyDelaySync`, not about any one preset.)
    func testADryCharacterPresetIsNotAnEmptySet() {
        let chain = EchoelFXChain()
        FXCharacter.underwater.apply(to: chain, bpm: 120, genre: .dubTechno)
        FXCharacter.telephone.apply(to: chain, bpm: 120, genre: .dubTechno)
        XCTAssertFalse(chain.delayEnabled,
                       "Telephone is a bandpass with NO delay — its preset says so explicitly.")
        // Anti-vacuity: assert the MODE, not just `filterEnabled`. Underwater already left the
        // filter on, so a bare `filterEnabled` check could not tell "telephone wrote it" from
        // "underwater left it" — it would pass on a preset that never landed at all.
        XCTAssertEqual(chain.filterL.mode, .bandpass,
                       "Telephone's own bandpass never landed (underwater's lowpass survived), "
                       + "so the delay assertion above proves nothing")
    }

    // MARK: - The regression guard

    /// ⛔ THE ONE THAT WOULD HAVE CAUGHT IT. `applyDelaySync(bpm:)` may write the delay TIME and
    /// nothing else. If a future edit re-adds an enable write there, the Delay switch silently
    /// stops being able to stay off and Clean silently stops being clean — neither of which
    /// throws, logs, or shows anything on screen.
    ///
    /// Source text rather than behaviour because the function is `private` on a SwiftUI `View`;
    /// there is no seam to call it through and no local toolchain to build a host with. The
    /// scan is bounded to the function body so an unrelated `delayEnabled` elsewhere in the file
    /// cannot fail it — including the legitimate one in the delay-division picker's `onChange`,
    /// which arms the effect on a direct user gesture and is NOT what this guards. Whole-line
    /// comments are dropped, because the doc comment above the function quotes the removed line
    /// by name.
    func testApplyDelaySyncSetsTheTimeAndNothingElse() throws {
        let body = try functionBody(named: "private func applyDelaySync(bpm: Double)",
                                    in: "Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertFalse(body.contains("delayEnabled"),
                       "`applyDelaySync` writes `delayEnabled` again:\n\(body)\n"
                       + "That makes 'Clean (dry) — no effects' wet and makes the Delay switch "
                       + "in the FX panel flip itself back on. If a delay division genuinely "
                       + "must arm the effect, that is a founder decision about what the two "
                       + "controls mean — not a line added inside a time setter.")
        XCTAssertTrue(body.contains("delay.timeSeconds"),
                      "`applyDelaySync` no longer sets the delay time, so the user's chosen "
                      + "division does nothing at all:\n\(body)")
    }

    // MARK: - Reading the source

    /// The lines between a declaration and its matching closing brace, with whole-line comments
    /// dropped. Brace-counting is crude but sufficient here: the target function is four lines
    /// long and contains no string literal holding a brace. It throws rather than returning
    /// empty on a miss — an empty body would make the assertion above pass vacuously, which is
    /// the exact failure mode `Tests/CISmoke` exists to avoid.
    private func functionBody(named declaration: String, in relativePath: String) throws -> String {
        let url = try repoRoot().appendingPathComponent(relativePath)
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: .newlines)
        guard let start = lines.firstIndex(where: { $0.contains(declaration) }) else {
            XCTFail("Declaration not found: \(declaration) in \(relativePath). It was renamed or "
                    + "moved — re-point this test rather than deleting it.")
            throw CocoaError(.fileNoSuchFile)
        }
        var depth = 0
        var collected: [String] = []
        for line in lines[start...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // `continue` BEFORE the brace arithmetic, not just before the append: a comment
            // holding an unbalanced brace (a future line quoting `{` in prose) would otherwise
            // desync `depth` and silently return the wrong span.
            if trimmed.hasPrefix("//") { continue }
            collected.append(line)
            depth += line.filter { $0 == "{" }.count
            depth -= line.filter { $0 == "}" }.count
            if depth == 0 && collected.count > 1 { break }
        }
        return collected.joined(separator: "\n")
    }

    /// `#filePath` is inside `Tests/CISmoke/`, so the repo root is three directories up. A
    /// source-reading test that cannot find the source must SKIP, not pass.
    private func repoRoot() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CISmoke
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
        guard FileManager.default.fileExists(atPath:
                root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("source tree not present — this test inspects source text, so it "
                          + "SKIPS rather than reporting a green it did not earn")
        }
        return root
    }
}
