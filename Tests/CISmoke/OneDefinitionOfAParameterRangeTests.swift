// OneDefinitionOfAParameterRangeTests.swift
// Echoel — #441. A parameter's range is ONE fact. The row that shows the number and every
// writer that clamps into it must read the same constant.
//
// WHAT WAS WRONG. Each of the Sound panel's seventeen parameters had its range written THREE
// times: as a literal at the `param(…)`/`knob(…)` call site, again inside `SoundPrompt.clamp`,
// and a third time in the hand-written model table of `SoundRowsCanReachTheShippedPatchesTests`
// next door. The first two are now one constant (`SynthPatch.Bounds`). The third stays
// hand-written ON PURPOSE and is not a defect: a guard that reads the constant it is guarding
// cannot catch a wrong constant.
//
// ⭐ THE ONE THAT ACTUALLY COST SOMETHING is `filterLFORate`. Its row spans 0…20 Hz; the prompt
// clamped to 0…12. #430 saw that difference and wrote it off as harmless because the shipped
// bank tops out at 1.2 Hz — which looked at the wrong population. The row lets a FINGER reach
// 20, and `SoundPrompt.apply` ends with an UNCONDITIONAL `clamp(&p)`, so tapping "Describe it"
// with ANY text rewrote a user-set 19 Hz as 12 Hz. Not only recognised words: an entirely
// unrecognised prompt shapes nothing and still clamps, so the value was destroyed by text the
// engine ignores. That is the `Drone Bed` defect #430 fixed one field over, in the harder-to-
// notice direction — no fixture holds a user-set value, so nothing went red.
//
// ⚠️ THE SECOND DIFFERENCE IS COSMETIC AND SAID SO RATHER THAN DRESSED UP. The prompt floored
// `attack` at 0.001 s while its row starts at 0. `EchoelDDSP`'s envelope enforces a ~3 ms
// minimum attack ramp in its `.attack` stage, so 0 s and 0.001 s are the same sound. The floor's
// stated purpose ("a musical minimum below every shipped onset") was already served one layer
// down. It is included here because a test that only covers the exciting half of a change is
// how the other half rots.
//
// ⭐ THE DIRECTION IS A RULE, NOT A CASE-BY-CASE CALL: where the two disagreed, the ROW wins and
// the prompt WIDENS. Widening can never cut a shipped or user-set value — that is exactly the
// invariant that made #430's `decay` fix safe — while narrowing a row to match a prompt would
// silently take reach away from a control the user already has.
//
// ⚠️ WHAT THIS CANNOT SHOW: that any of it is audible. `filterLFORate` drives the patch filter
// LFO, and whether 19 Hz "sounds better" than 12 Hz is a device listen. What is checkable is
// that the number the row offers is the number the app keeps.

import Foundation
import XCTest
@testable import Echoelmusic

final class OneDefinitionOfAParameterRangeTests: XCTestCase {

    // MARK: - The pre-#441 prompt bounds, kept here as the reference to measure against

    /// ⚠️ `min(max(…))` here ON PURPOSE — this is the HISTORICAL arithmetic, transcribed exactly
    /// as it stood before #441, not new code. The house rule (`Core/FloatingPointClamp.swift`)
    /// says never to write it on a live path because it passes NaN through; a reference
    /// implementation that "fixed" it would stop being a reference.
    ///
    /// Every old bound is a SUBSET of its new one (two are strictly narrower, fifteen are equal),
    /// which is what makes `testTheChangeIsInertExceptForTheTwoNamedFields` exact without
    /// reimplementing `shape`: clamping is monotone and idempotent, so applying the OLD bounds to
    /// the NEW result is bit-identical to what the old `clamp` produced from the same raw shape.
    ///
    /// ⚠️ AND THE PRICE OF THAT ARGUMENT, said rather than left for a reader to notice: on the
    /// fifteen fields where old == new, re-clamping is the IDENTITY, so that test cannot fail on
    /// today's tree. It is a counterweight against a future mis-transcription, not evidence about
    /// this change — and it is blind in the NARROWING direction for the same reason (a value
    /// already inside a smaller range comes back unchanged). The narrowing direction is guarded by
    /// the data sweep and the one hand-written ceiling further down, not here.
    private func applyOldPromptBounds(_ p: SynthPatch) -> SynthPatch {
        var q = p
        func c01(_ x: Float) -> Float { min(max(x, 0), 1) }
        q.brightness = c01(q.brightness)
        q.harmonicity = c01(q.harmonicity)
        q.harmonicLevel = c01(q.harmonicLevel)
        q.noiseLevel = c01(q.noiseLevel)
        q.sustain = c01(q.sustain)
        q.reverbMix = c01(q.reverbMix)
        q.filterResonance = c01(q.filterResonance)
        q.lfoToFilterDepth = c01(q.lfoToFilterDepth)
        q.filterLFODepth = c01(q.filterLFODepth)
        q.vibratoDepth = c01(q.vibratoDepth)
        q.attack = min(max(q.attack, 0.001), 5)
        q.decay = min(max(q.decay, 0.0), 10)
        q.release = min(max(q.release, 0.0), 10)
        q.filterCutoff = min(max(q.filterCutoff, 20), 18_000)
        q.filterLFORate = min(max(q.filterLFORate, 0), 12)
        q.reverbDecay = min(max(q.reverbDecay, 0), 10)
        q.vibratoRate = min(max(q.vibratoRate, 0), 12)
        return q
    }

    /// The seventeen fields the Sound panel renders, each with its bound and a reader — one place
    /// to add a row, so a new parameter cannot be half-covered.
    private struct Field {
        let name: String
        let bound: ClosedRange<Float>
        let read: (SynthPatch) -> Float
        let write: (inout SynthPatch, Float) -> Void
    }

    /// ⚠️ BUILT BY `append`, NOT AS ONE ARRAY LITERAL, and that is not style: seventeen
    /// initializers carrying thirty-four closures in a single expression is exactly the shape
    /// that made the blocking gate red in #287 ("expression too complex to type-check"). One
    /// statement per row costs nothing and cannot hit it.
    private var fields: [Field] {
        typealias B = SynthPatch.Bounds
        var out: [Field] = []
        out.append(Field(name: "brightness", bound: B.brightness,
                         read: { $0.brightness }, write: { $0.brightness = $1 }))
        out.append(Field(name: "harmonicity", bound: B.harmonicity,
                         read: { $0.harmonicity }, write: { $0.harmonicity = $1 }))
        out.append(Field(name: "harmonicLevel", bound: B.harmonicLevel,
                         read: { $0.harmonicLevel }, write: { $0.harmonicLevel = $1 }))
        out.append(Field(name: "noiseLevel", bound: B.noiseLevel,
                         read: { $0.noiseLevel }, write: { $0.noiseLevel = $1 }))
        out.append(Field(name: "filterCutoff", bound: B.filterCutoff,
                         read: { $0.filterCutoff }, write: { $0.filterCutoff = $1 }))
        out.append(Field(name: "filterResonance", bound: B.filterResonance,
                         read: { $0.filterResonance }, write: { $0.filterResonance = $1 }))
        out.append(Field(name: "lfoToFilterDepth", bound: B.lfoToFilterDepth,
                         read: { $0.lfoToFilterDepth }, write: { $0.lfoToFilterDepth = $1 }))
        out.append(Field(name: "filterLFORate", bound: B.filterLFORate,
                         read: { $0.filterLFORate }, write: { $0.filterLFORate = $1 }))
        out.append(Field(name: "filterLFODepth", bound: B.filterLFODepth,
                         read: { $0.filterLFODepth }, write: { $0.filterLFODepth = $1 }))
        out.append(Field(name: "attack", bound: B.attack,
                         read: { $0.attack }, write: { $0.attack = $1 }))
        out.append(Field(name: "decay", bound: B.decay,
                         read: { $0.decay }, write: { $0.decay = $1 }))
        out.append(Field(name: "sustain", bound: B.sustain,
                         read: { $0.sustain }, write: { $0.sustain = $1 }))
        out.append(Field(name: "release", bound: B.release,
                         read: { $0.release }, write: { $0.release = $1 }))
        out.append(Field(name: "reverbMix", bound: B.reverbMix,
                         read: { $0.reverbMix }, write: { $0.reverbMix = $1 }))
        out.append(Field(name: "reverbDecay", bound: B.reverbDecay,
                         read: { $0.reverbDecay }, write: { $0.reverbDecay = $1 }))
        out.append(Field(name: "vibratoRate", bound: B.vibratoRate,
                         read: { $0.vibratoRate }, write: { $0.vibratoRate = $1 }))
        out.append(Field(name: "vibratoDepth", bound: B.vibratoDepth,
                         read: { $0.vibratoDepth }, write: { $0.vibratoDepth = $1 }))
        return out
    }

    // MARK: - The defect, named and measured

    /// RED before #441: a user-set 19 Hz LFO rate came back as 12 Hz from a prompt that shapes
    /// nothing at all. `"lorem"` is in no vocabulary, so this isolates the UNCONDITIONAL clamp —
    /// the part that makes the old bound reachable without the user typing anything meaningful.
    func testAnUnrecognisedPromptCannotCutTheLFORate() {
        let patch = SynthPatch(name: "Test", filterLFORate: 19)
        let out = SoundPrompt.apply("lorem", to: patch)
        XCTAssertEqual(out.filterLFORate, 19, accuracy: 1e-6, """
            "Describe it" rewrote a 19 Hz filter LFO rate as \(out.filterLFORate) Hz on text the \
            engine does not even recognise. The row spans \
            \(SynthPatch.Bounds.filterLFORate.lowerBound)…\
            \(SynthPatch.Bounds.filterLFORate.upperBound) Hz, so 19 is a value a finger can set; \
            `SoundPrompt.apply` ends with an unconditional clamp, so a narrower bound there \
            destroys it.
            """)
    }

    /// The recognised-word half of the same defect. "evolving" adds 0.25 Hz, so the honest
    /// expectation is 19.25 — not "unchanged". Old behaviour: 12.
    func testARecognisedPromptShapesTheLFORateInsteadOfCappingIt() {
        let patch = SynthPatch(name: "Test", filterLFORate: 19)
        let out = SoundPrompt.apply("evolving", to: patch)
        XCTAssertEqual(out.filterLFORate, 19.25, accuracy: 1e-5, """
            "evolving" adds 0.25 Hz; from 19 Hz that is 19.25 and the row admits it. Got \
            \(out.filterLFORate).
            """)
    }

    /// The cosmetic half, included so it cannot rot unnoticed. Old behaviour: 0.001.
    func testTheAttackFloorIsTheRowsFloor() {
        let patch = SynthPatch(name: "Test", attack: 0)
        let out = SoundPrompt.apply("lorem", to: patch)
        XCTAssertEqual(out.attack, 0, accuracy: 1e-9, """
            The prompt still floors attack at its own value (\(out.attack) s) rather than the \
            row's 0. Inaudible either way — `EchoelDDSP` enforces a ~3 ms minimum ramp — but it \
            is a second definition of one range, which is the whole point of #441.
            """)
    }

    // MARK: - The general property

    /// Every field, at BOTH ends of its own row, survives a prompt that shapes nothing. This is
    /// the claim the two named cases are instances of; it is here so the next parameter added to
    /// `Bounds` is covered without anyone remembering to write a case for it.
    func testNoBoundOfAnyRowIsCutByAPrompt() {
        for f in fields {
            for edge in [f.bound.lowerBound, f.bound.upperBound] {
                var patch = SynthPatch(name: "Test")
                f.write(&patch, edge)
                let out = SoundPrompt.apply("lorem", to: patch)
                XCTAssertEqual(f.read(out), edge, accuracy: Swift.max(1e-6, abs(edge) * 1e-6), """
                    \(f.name) was set to \(edge) — a value its own row admits — and a prompt that \
                    shapes nothing returned \(f.read(out)). The prompt's bound is narrower than \
                    the row's, which means the panel offers reach it then takes away.
                    """)
            }
        }
    }

    // MARK: - Honest scope: what did NOT move

    /// The counterweight, and the reason this slice can be called inert outside the two named
    /// fields: over every shipped patch × every shipped suggestion, the result differs from the
    /// old arithmetic ONLY in `attack` and `filterLFORate`, and only where the old bound was
    /// actually biting. See `applyOldPromptBounds` for why re-clamping the new result is exact.
    func testTheChangeIsInertExceptForTheTwoNamedFields() {
        var moved: [String] = []
        var checked = 0
        for patch in SynthPatch.factory {
            for prompt in SoundPrompt.suggestions {
                let now = SoundPrompt.apply(prompt, to: patch)
                let before = applyOldPromptBounds(now)
                checked += 1
                for f in fields where f.name != "attack" && f.name != "filterLFORate" {
                    if f.read(now) != f.read(before) {
                        moved.append("\(patch.name)/\(prompt): \(f.name)")
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 0, "The sweep did not run — a green below proves nothing.")
        XCTAssertEqual(moved.count, 0, """
            \(moved.prefix(5).joined(separator: ", ")) — a field OTHER than attack and \
            filterLFORate changed behaviour. #441 is a single-sourcing pass with two named \
            widenings; anything else moving means a bound was transcribed wrong.
            """)
    }

    /// The three shipped banks, named separately so the floor below can notice that ONE of them
    /// went empty — a single flat count cannot, because the factory bank alone clears any
    /// plausible total. Same three the sibling guard sweeps, for the same reason.
    private enum Bank: String, CaseIterable {
        case factory = "SynthPatch.factory"
        case library = "PatchLibrary.all"
        case genres  = "MusicStyle.allCases.synthPatch"

        func patches() -> [SynthPatch] {
            switch self {
            case .factory: return SynthPatch.factory
            case .library: return PatchLibrary.all.map { $0.patch }
            case .genres:  return MusicStyle.allCases.map { $0.synthPatch }
            }
        }
    }

    /// ⛔ THE GAP THIS CLOSES WAS FOUND BY ASKING WHAT THE TESTS ABOVE CANNOT SEE, and it is a
    /// gap #441 CREATED. Every check so far reads `Bounds` on both sides, so NARROWING a bound
    /// moves the row and the prompt together and nothing goes red — while the row would then clip
    /// a patch it used to reach. Before #441 the four full-call-text pins in
    /// `SoundRowsCanReachTheShippedPatchesTests` were the thing standing in the way of that, and
    /// #441 replaced their range half with a binding. So the constant has to be answerable to the
    /// DATA instead: every shipped patch value must fit inside its own bound. That is the same
    /// shape of claim the sibling guard makes against its hand-written table, and the two are not
    /// redundant — that one catches "the row drifted from the model", this one catches "the model
    /// AND the row drifted together".
    ///
    /// ⛔ AND THE FIRST VERSION SWEPT ONLY `SynthPatch.factory` WHILE CLAIMING — here, in the
    /// commit message, and in the sibling's comment — that "`Drone Bed`'s 6.0 s decay is the value
    /// that makes it bite". `Drone Bed` is NOT in that bank. It is built by
    /// `GenrePatches.patch("EE", "Drone Bed", … d: 6.0, …)` and reached through
    /// `MusicStyle.synthPatch`, a separate population that lands in `currentPatch` just the same.
    /// The factory bank's decay maximum is 1.5, so the guard had 85% slack on the one field it
    /// named and `Bounds.decay` could have been narrowed to `0...5` — the literal #430 defect —
    /// with every test in the repo green. **That is the same methodology error the sibling's own
    /// header records** ("the third source it NAMED, `MusicStyle.synthPatch`, was invisible to the
    /// scan"), committed in the slice that cites it, one paragraph after calling #430's reasoning
    /// "the wrong population". Measured over all three banks the maxima are: decay 6.0 (Drone Bed),
    /// release 7.5, reverbDecay 8.5, filterCutoff 8000, attack 3.5, vibratoRate 6.2.
    func testEveryShippedPatchFitsInsideItsOwnBound() {
        var outside: [String] = []
        for bank in Bank.allCases {
            let patches = bank.patches()
            XCTAssertFalse(patches.isEmpty, """
                \(bank.rawValue) is empty — a bank that vanishes takes its coverage with it and \
                leaves the remaining ones looking sufficient.
                """)
            for patch in patches {
                for f in fields where !f.bound.contains(f.read(patch)) {
                    outside.append("\(bank.rawValue)/\(patch.name).\(f.name) = \(f.read(patch)) ∉ \(f.bound)")
                }
            }
        }
        XCTAssertEqual(outside.count, 0, """
            \(outside.prefix(5).joined(separator: ", ")) — a shipped patch holds a value its own \
            row cannot reach. Widen the bound; NEVER round the patch (#430 paid that once: a \
            narrower bound rewrote `Drone Bed`'s 6.0 s decay as 5.0 on first touch).
            """)
    }

    /// ⚠️ AND THE DATA SWEEP ABOVE CANNOT GUARD THE FIELD THIS SLICE EXISTS FOR. Measured across
    /// all three banks, the highest shipped `filterLFORate` is **1.2 Hz** — so re-narrowing the
    /// bound to the old `0...12` leaves every patch comfortably inside and every other test in
    /// this file green, while the row silently loses 8 Hz of reach. The value #441 rescued was a
    /// USER-SET 19 Hz, and no fixture holds a user-set value; that is the whole shape of the
    /// defect. So this one ceiling is pinned by hand, as the independent authority the data
    /// cannot be.
    ///
    /// ⚠️ DELIBERATELY ONE FIELD AND NOT SEVENTEEN. #430 recorded the reason in this same bundle:
    /// pinning every constant makes an ordinary panel edit red, and that is how a guard gets
    /// deleted rather than obeyed. Pinned here is the single bound whose shipped maximum sits far
    /// enough below it that nothing else would notice the loss.
    func testTheLFORateCeilingIsPinnedBecauseNoShippedPatchReachesIt() {
        XCTAssertEqual(SynthPatch.Bounds.filterLFORate.upperBound, 20, accuracy: 1e-6, """
            The patch filter-LFO row's ceiling moved. If it went back to 12, that is #441 undone: \
            a finger can set 19 Hz, `SoundPrompt.apply` ends in an unconditional clamp, and no \
            shipped patch goes above 1.2 Hz — so nothing else in this repo would go red.
            """)
        let shippedMax = Bank.allCases
            .flatMap { $0.patches() }
            .map(\.filterLFORate)
            .max() ?? 0
        XCTAssertLessThan(shippedMax, 12, """
            A shipped patch now reaches \(shippedMax) Hz, at or above the OLD prompt ceiling. The \
            premise of this hand-written pin — that the data cannot see a re-narrowing — no longer \
            holds, so fold this back into the data sweep instead of keeping a second copy.
            """)
    }

    // MARK: - The wiring (source scans, and they say so)

    /// The seventeen rows read the constant rather than a literal. A substring rather than the
    /// whole call text on purpose — #430's sibling guard pins full call sites and pays for it on
    /// every reformat; this one only needs the BINDING to survive.
    func testEveryRowReadsTheSharedBound() throws {
        let text = try source("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        for f in fields {
            XCTAssertTrue(text.contains("SynthPatch.Bounds.\(f.name)"), """
                The Sound panel's \(f.name) row no longer reads `SynthPatch.Bounds.\(f.name)`. \
                If it went back to a literal, that is the third spelling returning — and the \
                prompt will drift away from it again without anything going red.
                """)
        }
    }

    /// And so does the writer on the other side of the same panel.
    func testThePromptClampReadsTheSharedBound() throws {
        let text = try source("Sources/Echoelmusic/DSP/SoundPrompt.swift")
        XCTAssertTrue(text.contains("typealias B = SynthPatch.Bounds"), """
            `SoundPrompt.clamp` no longer aliases `SynthPatch.Bounds`. It is the writer that
            shares the panel with the rows; if it grows its own numbers again, #441 is undone.
            """)
        for f in fields {
            XCTAssertTrue(text.contains("clamped(to: B.\(f.name))"), """
                `SoundPrompt.clamp` no longer clamps \(f.name) into the shared bound.
                """)
        }
    }

    /// The chain, in the #426 form: the cutoff bound is not restated here, it IS the engine's.
    /// The load-bearing half is the SPELLING — a literal that happens to be equal today is a
    /// second definition that can drift tomorrow, and that is not hypothetical for this constant:
    /// `EchoelDDSP.cutoffRange`'s own doc records a "[20-20000 Hz]" comment that survived next to
    /// an 18000 clamp.
    ///
    /// ⚠️ The value assertion below CANNOT FAIL while the spelling holds — `Bounds.filterCutoff`
    /// is *defined* as `cutoffRange`, so the equality is definitional (#367). It stays as the
    /// thing that keeps meaning something if a later slice replaces the chain with a literal for
    /// portability (see the Accelerate note on `Bounds` itself); it is not a second detector.
    func testTheCutoffBoundIsChainedNotCopied() throws {
        XCTAssertEqual(SynthPatch.Bounds.filterCutoff, EchoelDDSP.cutoffRange,
                       "The panel's cutoff row and the engine's cutoff domain disagree.")
        let text = try source("Sources/Echoelmusic/DSP/SynthPatch.swift")
        XCTAssertTrue(text.contains("filterCutoff: ClosedRange<Float> = EchoelDDSP.cutoffRange"), """
            `SynthPatch.Bounds.filterCutoff` is written as a literal again instead of chaining to \
            `EchoelDDSP.cutoffRange`. Equal today is not the same as single-sourced.
            """)
    }

    // MARK: - Helpers

    /// ⚠️ `SourceText.codeOnly`, not the raw file. This repo answers a removal with a ⛔ block that
    /// QUOTES the token it removed — `// ⛔ this row used to read SynthPatch.Bounds.decay` would
    /// satisfy every needle below over a reverted row. #453 made that one definition two commits
    /// before this slice, and the first version of this file scanned the raw text anyway.
    /// ⭐ AND IT STOPPED BEING PROPHYLACTIC IN THE SAME COMMIT THAT ADDED IT. Correcting the
    /// stale range note beside the Decay row put the literal string `SynthPatch.Bounds.decay`
    /// into a COMMENT in `EchoelStudioView.swift`. Measured: that needle now appears twice in the
    /// raw file and once in the code. Every other needle is 1/1, and all 17 clamp needles plus
    /// the chain needle survive stripping — so the guard is unchanged in verdict today, and one
    /// row away from having been satisfied by prose.
    private func source(_ relative: String) throws -> String {
        let raw = try String(contentsOf: repoRoot().appendingPathComponent(relative), encoding: .utf8)
        return SourceText.codeOnly(raw)
    }

    private func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
            dir = dir.deletingLastPathComponent()
        }
        throw XCTSkip("repo root not found from \(#filePath)")
    }
}
