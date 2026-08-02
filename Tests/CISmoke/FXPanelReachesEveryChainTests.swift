// FXPanelReachesEveryChainTests.swift
// Echoel — one panel, one reach. BLOCKING bundle. #318.
//
// THE DEFECT. The Effects panel has three controls stacked in one place, and they had two
// different ideas about how much of the instrument they moved:
//
//   · the character menu   → `for chain in characterFXChains { … }`  — every sounding chain
//   · the delay division   → `applyDelaySync(bpm:)`, same inventory   — every sounding chain
//   · "All parameters"     → `EchoelFXView(chain: synth.fxChain, …)`  — ONE chain
//
// So stamping "Cassette" moved the generated take and the played notes together, and then
// opening the deep surface to widen its delay moved only the take. Half the instrument drifted
// away from the other half with nothing on screen saying so. That is the failure #240 already
// named — "two lists that must agree are one list" — arriving on the surface #240 did not reach,
// and `GenreFX.apply`'s own doc had written it down in advance: the FX panel's character menu is
// the FOURTH stamp site and "writes only the injected chain (`synth.fxChain`), never
// `touchSynth?.fxChain`".
//
// ⚠️ WHAT THE FIX IS NOT. It does NOT add `leadSynth.fxChain` or `bioVoice.fxChain`. The
// inventory (`characterFXChains`) deliberately excludes both and says why at the declaration —
// the lead would suddenly turn wet in every genre (an audible product change in the middle of a
// pending ear-check), and the bio voice's chain never runs. This slice hands the deep surface
// the inventory that already exists; it does not widen it.
//
// ⚠️ WHAT IS STILL BROKEN, so a green here is not read as more than it is. `applyCharacter`
// stamps a character's own delay TIME and no `applyDelaySync(bpm:)` follows it, so the Studio's
// division picker can still SHOW a division the chains do not hold. That is the other half of
// the same `GenreFX` note, it is a Studio-side ordering call, and it is not guarded here.
//
// ⛔ A THIRD SITE WITH THE SAME SHAPE — FIXED, and this note is kept as the record rather than
// deleted, because it was written in the present tense and would otherwise send a future session
// to redo finished work. `FXBioModulator` DID store ONE `EchoelFXChain?` with a single
// `attach(chain:bus:)` call, so the bio-driven FX modulation moved the take and not the played
// notes. Closed by #386: `allChains` + `attach(chain:mirrors:bus:)`, guarded by
// `BioFXReachesEveryChainTests`. As predicted here, it was NOT a copy of this slice — the
// modulator captures and restores a base per parameter, so it needed one base set PER CHAIN
// (`[FXModTarget: [Float]]`), not just a loop.
//
// ⚠️ THE ONE CLAUSE THAT SURVIVES, because it is still true and `snapshot(name:)` still depends
// on it: the chains are NOT identical while a bio route runs. Each rides the same body offset
// around its OWN captured base, so their values differ by exactly the difference in those bases.
//
// ⚠️ WHY A SOURCE SCAN. `FXViewModel`'s chains are `private`, `EchoelStudioView`'s inventory is
// a `private var` on a SwiftUI `View`, and there is no local toolchain to build a UI-test host.
// Same reasoning, and the same house pattern, as `DelayReachesEveryChainTests` — which owns the
// anti-vacuity half of this claim (that the inventory holds MORE than the composer's synth) and
// is deliberately not copied here: two guards asserting the same constant is how they drift into
// disagreeing about it.
//
// WHAT THIS CANNOT PROVE: that `touchSynth` is non-nil at runtime, that the Field is audible, or
// that the resulting sound is right.
//
// NEEDS-FOUNDER-VERIFY: play the Field while a take runs, open Effects → "All parameters", move
// Reverb mix — do the played notes change with the take?

import Foundation
import XCTest

final class FXPanelReachesEveryChainTests: XCTestCase {

    private static let fx = "Sources/Echoelmusic/Studio/EchoelFXView.swift"
    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"

    /// ⭐ THE GUARD. Every write-through observer fans out. A re-introduced `didSet { chain.…`
    /// is #318 coming back one parameter at a time — which is exactly how it would return,
    /// because the next FX parameter will be added by copying the line above it.
    ///
    /// ⚠️ IT KEYS ON THE LITERAL `"didSet {"`, so it is blind to `didSet{` without the space
    /// and it would report a multi-line `didSet` as an offender it cannot diagnose. Both are
    /// acceptable: this file's 63 subjects are one-liners written to one shape, and a scan that
    /// tried to parse Swift properly would be the guard-that-mis-classifies this bundle keeps
    /// paying for. If the shape ever changes, change this helper in the same commit.
    func testEveryWriteThroughFansOutOverTheInventory() throws {
        let lines = try codeLines(Self.fx)
        var offenders: [String] = []
        var fanned = 0
        for l in lines {
            guard l.contains("didSet {") else { continue }
            if l.contains("didSet { for c in allChains {") {
                // ⛔ THE LOOP IS NOT THE CLAIM — the BODY is, and the first version of this
                // check stopped at the prefix. `didSet { for c in allChains { chain.reverb.mix
                // = reverbMix } }` would have counted as fanned while the parameter reached one
                // chain, and that is the single most likely way #318 returns: this file's own
                // header says the next parameter gets added by copying the line above it, and a
                // copy that keeps `chain.` inside the new loop looks right at a glance.
                // Strip the ONE legitimate occurrence of the word first, then any `chain.`
                // left is a write to the stored primary.
                if l.replacingOccurrences(of: "allChains", with: "").contains("chain.") {
                    offenders.append(l.trimmingCharacters(in: .whitespaces))
                    continue
                }
                fanned += 1
                continue
            }
            // The master gate is the one observer that does not write a chain field: it calls
            // the injected `setMaster`, and the fan-out for THAT lives in the closure the call
            // site hands over (asserted separately below).
            if l.contains("didSet { setMaster(") { continue }
            offenders.append(l.trimmingCharacters(in: .whitespaces))
        }
        XCTAssertTrue(offenders.isEmpty, """
            \(offenders.count) `didSet` observer(s) in `FXViewModel` do not write the chain \
            inventory: \(offenders)

            Each one is a control that moves the generated take and leaves the played notes \
            where they were (#318). The shape is `didSet { for c in allChains { c.<field> = \
            <mirror> } }` — field by field, never a whole nested struct, because `EchoelDelay` \
            and friends carry per-chain delay-line state.
            """)
        XCTAssertGreaterThanOrEqual(fanned, 60, """
            only \(fanned) fanned-out `didSet` observers found in `FXViewModel`, expected at \
            least 60 (there were 63 when #318 shipped).

            This is the anti-vacuity half: the assertion above passes trivially if the \
            observers stopped existing. If the surface genuinely shrank, lower this number in \
            the same commit and say what was removed.
            """)
    }

    /// The three paths that write a WHOLE sound at once — a character stamp, a preset recall,
    /// a macro morph. Each used to hand `chain` to something that writes ~50 fields, so each is
    /// a 50-parameter version of the same defect.
    func testTheWholeSoundPathsWriteEveryChainToo() throws {
        for member in ["func applyCharacter(_ character: FXCharacter)",
                       "func apply(_ preset: FXPreset)",
                       "func morph(from a: FXPreset, to b: FXPreset, amount: Float)"] {
            let body = try memberBody(startingWith: member, in: Self.fx)
            XCTAssertTrue(body.contains(where: { $0.contains("allChains") }), """
                `\(member)` does not iterate `allChains`, so it stamps a complete sound on one \
                chain and leaves the others on the previous one (#318):
                \(body.joined(separator: "\n"))
                """)
            XCTAssertFalse(body.contains(where: { $0.contains("(to: chain") }), """
                `\(member)` still writes the single `chain` by name. `chain` is what this \
                view-model READS (the seed, `reseed()`, `snapshot(name:)`); the write side is \
                `allChains`:
                \(body.joined(separator: "\n"))
                """)
        }
    }

    /// The inventory must be BUILT from the injected chains, not assembled from a fresh list of
    /// voices inside the view-model — the whole point is that there is one list and the caller
    /// owns it.
    func testTheInventoryIsThePrimaryPlusWhatTheCallerHandedOver() throws {
        // Qualified through `bpm:` on purpose: `EchoelFXView.init` in the same file now opens
        // with the same two parameters, and `firstIndex` would silently pick whichever comes
        // first in the file. A prefix that matches two declarations is not a prefix.
        let body = try memberBody(startingWith: "init(chain: EchoelFXChain, mirrors: [EchoelFXChain] = [], bpm:",
                                  in: Self.fx)
        XCTAssertTrue(body.contains(where: { $0.contains("self.allChains = [chain] + mirrors") }), """
            `FXViewModel.init` no longer builds `allChains` as the injected primary plus the \
            injected mirrors. If the view-model starts naming voices itself, it owns a second \
            inventory and #240 is back one level down:
            \(body.joined(separator: "\n"))
            """)
    }

    /// ⛔ THE CALL SITE, which is where the two halves actually meet. The mirrors must be
    /// DERIVED from `characterFXChains` — writing the voices out again here would compile,
    /// look right, and re-create the exact defect the moment a voice is added to one list only.
    func testTheDoorHandsOverTheStudioInventory() throws {
        let sheet = try sheetBody()
        XCTAssertTrue(sheet.contains(where: { $0.contains("mirrors: characterFXChains") }), """
            the "All parameters" door does not pass `characterFXChains` as the mirrors, so the \
            deep surface can once again reach fewer chains than the two rows above it (#318):
            \(sheet.joined(separator: "\n"))
            """)
        XCTAssertTrue(sheet.contains(where: { $0.contains("touchSynth?.setFXEnabled") }), """
            the master "Insert FX" gate in the deep surface reaches only the composer's synth. \
            A gate that dries the take and leaves the played notes wet is the same split reach \
            as a knob that moves one chain, one control higher:
            \(sheet.joined(separator: "\n"))
            """)
    }

    // MARK: - Source helpers

    /// The `.sheet(isPresented: $showAllFX)` block, bracketed by indentation: it opens at some
    /// column and closes at the first later line that is a bare `}` in that same column.
    /// Structural, not a line count — a comment added inside must not change the answer.
    private func sheetBody() throws -> [String] {
        let lines = try codeLines(Self.studio)
        guard let start = lines.firstIndex(where: {
            $0.contains(".sheet(isPresented: $showAllFX)")
        }) else {
            XCTFail("""
                the `showAllFX` sheet is gone from \(Self.studio). That is the "All parameters" \
                door. If it moved into a consolidated `.sheet(item:)` slot — which the \
                black-screen law asks for eventually — move this guard with it rather than \
                deleting it.
                """)
            return []
        }
        let indent = lines[start].prefix { $0 == " " }.count
        guard let close = lines[(start + 1)...].firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "}"
                && $0.prefix { c in c == " " }.count == indent
        }) else {
            XCTFail("""
                the `showAllFX` sheet has no closing `}` at its own indentation, so this scan \
                cannot bracket it. That is not a layout defect — it just cannot be windowed \
                this way. Re-indent, or replace this helper with a brace-depth counter.
                """)
            return []
        }
        return Array(lines[start..<close])
    }

    /// Lines of a member, from the line that starts with `prefix` to the closing `}` at that
    /// line's OWN indentation. Never a line count and never a "next member" rule: both break
    /// the moment something is inserted, and this file's whole subject is a change that will be
    /// made by copying a neighbouring line.
    private func memberBody(startingWith prefix: String, in path: String) throws -> [String] {
        let lines = try codeLines(path)
        guard let start = lines.firstIndex(where: { $0.contains(prefix) }) else {
            XCTFail("""
                `\(prefix)` is gone from \(path). If it was renamed, move this guard with it — \
                do not leave a check for a member that no longer exists.
                """)
            return []
        }
        let indent = lines[start].prefix { $0 == " " }.count
        let close = lines[(start + 1)...].firstIndex {
            $0.trimmingCharacters(in: .whitespaces) == "}"
                && $0.prefix { c in c == " " }.count == indent
        } ?? lines.endIndex
        return Array(lines[start..<close])
    }

    /// Every line that is not a whole-line comment. Load-bearing here: the ⛔ blocks in both
    /// source files quote `didSet { chain.` and `(to: chain` verbatim while explaining the
    /// defect, and a scan that read them would fail on the explanation of the fix.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
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
                source tree not present at \(sources.path) — this test inspects source text, so \
                it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }
}
