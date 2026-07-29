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
    func testTheCleanCharacterLeavesEveryStageOff() {
        let chain = EchoelFXChain()
        // Start from a wet state so a preset that merely FAILED to write a field cannot pass by
        // inheriting a default. ⚠️ That protection does NOT extend to the phaser: no character
        // in the roster enables it, so `phaserEnabled` is false before AND after and its
        // assertion below cannot fail. It is kept as a statement of what Clean means, not as a
        // guard — saying so here rather than letting the fixture imply otherwise.
        FXCharacter.underwater.apply(to: chain, bpm: 120, genre: .dubTechno)
        XCTAssertTrue(chain.delayEnabled && chain.filterEnabled && chain.chorusEnabled,
                      "precondition: the wet character must switch delay, filter and chorus on")

        FXCharacter.clean.apply(to: chain, bpm: 120, genre: .dubTechno)

        XCTAssertFalse(chain.delayEnabled, "Clean (dry) left the delay running")
        XCTAssertFalse(chain.filterEnabled, "Clean (dry) left the filter running")
        XCTAssertFalse(chain.chorusEnabled, "Clean (dry) left the chorus running")
        XCTAssertFalse(chain.phaserEnabled, "Clean (dry) left the phaser running")
        XCTAssertFalse(chain.saturationEnabled, "Clean is truly dry — no warmth drive either")
        XCTAssertTrue(chain.limiterEnabled,
                      "the safety limiter is never disabled by a character — 'dry' must not "
                      + "become a way to defeat the output protection")
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
