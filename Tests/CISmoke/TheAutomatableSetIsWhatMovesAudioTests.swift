// TheAutomatableSetIsWhatMovesAudioTests.swift
// Echoel — #555, slice 1 of `scratchpads/PLAN_AUTOMATION_IN_DER_SPUR.md`.
//
// WHAT THIS IS ABOUT. Automation addresses a parameter by its registry keyPath, and
// `ParameterApplyRouter.applyNormalized` returns nil — a deliberate, crash-free NO-OP — when no
// setter is bound for it. That safety has a cost nobody was measuring: a lane on an unbound
// keyPath is a curve the player draws and never hears, and nothing in the repo would go red.
// Measured today: the registry declares 15 keyPaths, `PolySynthVoice.automatableBases` binds 6.
//
// ⛔ AND THIS SLICE EXISTS BECAUSE I GOT THE SAME FACT WRONG ONE CYCLE AGO, in the plan I handed
// the founder. #554 wrote "der Ziel-Vorrat ist bis heute drei", read off the three-case
// `AutomationTarget` enum — and twelve lines under that enum `applyStep` has a SECOND loop that
// dispatches arbitrary registry keyPaths through the router, plus one each for the clip and
// timeline layers. The bottleneck was never the enum; it is the SETTER BINDING one level down.
// An enum looks like a complete enumeration — that is its whole shape — which is exactly why a
// reader stops there. Same family as #546 (a write is only live if it reaches an UNGATED read)
// and #552 (a half-true claim reads as correct to whoever checks the true half). The retraction
// is in the plan; this file is the part that cannot go stale.
//
// ⚠️ THE LIMIT, PER ASSERTION — this file mixes two kinds and says which is which:
//   · claims 1, 3b and 4 are END-TO-END BEHAVIOUR. `EchoelParameterRegistry`,
//     `ParameterApplyRouter` and `PolySynthVoice.automatableBases` are public and
//     constructible, so these drive the shipped decision rather than describing it.
//   · claims 2 and 3a are SOURCE-TEXT SCANS: the setter `switch` is `private`, and
//     `EchoelDDSP.useConvolutionReverb` is a DSP flag this bundle should not reach into.
//   · DEVICE PROBE, open and untouched by any of it: whether an automated parameter SOUNDS like
//     it is moving. Nothing here plays a note.
//
// ⚠️ IT DOES NOT PIN THE COUNTS (#364). "15 and 6" is the finding, not the law — binding the
// other nine is the GOAL of the next slice, and a guard that reds on the fix is a guard that
// gets deleted along with its law. What is pinned is the RELATIONSHIP: everything bound must be
// real, the two lists that decide binding cannot drift apart, and one specific keyPath stays out
// while its DSP stage cannot sound.
//
// ⚠️ HONEST GRADING. Every assertion here is a COUNTERWEIGHT: all five are green on the parent
// (`2436f0a`) and on this tree, because this slice adds no source change at all — it converts a
// measured, unprotected fact into a checked one. Booking any of them as a regression would be
// the flattering-direction defect (#433). The file earns its place under #343: the facts it
// pins are the premises the next three slices build on, and each of them is one edit away from
// silently ceasing to hold. Transcribed in Python against both trees: registry 15 / bases 6 on
// each, all five green on each. STRIPPER: **PROPHYLAKTISCH, 0 of 10 verdicts flip** — the two
// source needles (`case "<base>":` and `useConvolutionReverb = false`) are positive `contains`
// on lines that exist as CODE in both files, so raw and stripped agree everywhere. It stays
// because #453 made one definition of "code, not prose" for the whole bundle, and it stops
// being prophylactic the day someone writes a retraction here quoting a form this file scans for.

import XCTest
@testable import Echoelmusic

@MainActor
final class TheAutomatableSetIsWhatMovesAudioTests: XCTestCase {

    private static let voice = "Sources/Echoelmusic/Tools/PolySynthVoice.swift"
    private static let ddsp = "Sources/Echoelmusic/DSP/EchoelDDSP.swift"

    // MARK: - claim 1 (END-TO-END) — nothing is bound to a keyPath the registry does not know

    /// A typo in a `bind` call compiles, binds into the void, and stays silent forever:
    /// `applyNormalized` needs BOTH a descriptor and a setter, so a misspelled base fails the
    /// descriptor lookup and returns nil like any honestly-unbound parameter. There is no
    /// runtime signal at all — which is why this is claim 1.
    func testEveryAutomatableBaseIsARealRegistryKeyPath() {
        let registry = EchoelParameterRegistry()
        let known = Set(registry.all().map(\.keyPath))
        let unknown = PolySynthVoice.automatableBases.filter { !known.contains($0) }
        XCTAssertTrue(unknown.isEmpty, """
            \(unknown.count) automatable base(s) are not registry keyPaths: \
            \(unknown.joined(separator: ", ")). `applyNormalized` requires a descriptor AND a \
            setter, so a base that the registry does not know can never move anything — and it \
            fails exactly like a parameter that was honestly left unbound, with no log, no crash \
            and no red test. Fix the spelling, or add the descriptor.
            """)
    }

    // MARK: - claim 2 (SOURCE SCAN) — the list and the switch cannot drift apart

    /// Two places decide whether a base is bound: `automatableBases` (what `bindAutomatable`
    /// iterates) and the `switch` in `automatableSetter`, whose `default: return nil` turns a
    /// missing `case` into a SILENT non-binding. #416: one decision, two spellings.
    func testTheBaseListAndTheSetterSwitchAgree() throws {
        let code = try codeText(Self.voice)
        for base in PolySynthVoice.automatableBases {
            XCTAssertTrue(code.contains("case \"\(base)\":"), """
                `\(base)` is listed in `automatableBases` but has no `case` in \
                `automatableSetter`. The switch ends in `default: return nil`, so \
                `bindAutomatable` skips it in silence — the parameter reads as automatable \
                everywhere it is listed and moves nothing. Add the case or drop it from the list.
                """)
        }
    }

    // MARK: - claim 3 (COUNTERWEIGHT) — the placebo that must stay unbound

    /// #546 measured that `reverbMix` is written by `applyBioReactive` and READ only inside
    /// `if Self.useConvolutionReverb, …`, a flag that is `false` with no writer anywhere in
    /// `Sources/`. Binding it would make the first new automation control a placebo: a curve
    /// that draws, replays, reports success, and cannot reach a sounding stage.
    func testTheDisabledReverbStageIsNotOfferedForAutomation() throws {
        // 3a — SOURCE SCAN: the premise. If someone enables the stage, this goes red first and
        // says so, rather than leaving 3b guarding a rule whose reason expired.
        let dsp = try codeText(Self.ddsp)
        XCTAssertTrue(dsp.contains("useConvolutionReverb = false"), """
            `EchoelDDSP.useConvolutionReverb` is no longer declared `false`. If the convolution \
            stage can now sound, the reason for keeping `ddsp.fx.reverbMix` out of \
            `automatableBases` is gone — bind it, and retire the assertion below together with \
            the ⚠️ note in `AlwaysOnBioChannel` and the `DisabledReverbIsNotClaimedLiveTests` \
            gate that share this premise (#546).
            """)
        // 3b — END-TO-END: the rule itself.
        XCTAssertFalse(PolySynthVoice.automatableBases.contains("ddsp.fx.reverbMix"), """
            `ddsp.fx.reverbMix` is bound as automatable while its only reader sits behind a flag \
            that is off with no writer. An automation lane on it would draw, save, replay and \
            change nothing audible — the exact shape #496 had to take back off a bio panel, \
            arriving here as a parameter a player could spend a take on.
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHT) — an unbound keyPath really is a silent no-op

    /// The fact the whole slice rests on, driven rather than asserted in prose: a registry
    /// keyPath with no setter returns nil. This is CORRECT behaviour (never a crash mid-take)
    /// and simultaneously the reason the automatable set has to be a checked fact — the failure
    /// mode is indistinguishable, from inside the app, from a lane the user has not drawn yet.
    func testAnUnboundRegistryKeyPathAppliesNothing() {
        let registry = EchoelParameterRegistry()
        let router = ParameterApplyRouter(registry: registry)
        let unbound = registry.all().map(\.keyPath)
            .first { !PolySynthVoice.automatableBases.contains($0) }
        guard let unbound else {
            // Not a failure: it means the next slice succeeded and every descriptor is bound.
            // The assertion has nothing left to prove, and saying so beats a vacuous green.
            return XCTFail("""
                Every registry keyPath is in `automatableBases`, so this test has no unbound \
                subject left. That is the GOAL of the slice after this one — delete this case \
                and update the plan's "6 von 15" rather than weakening it.
                """)
        }
        XCTAssertNil(router.applyNormalized(unbound, 0.75), """
            `\(unbound)` is unbound in this fixture yet `applyNormalized` reported an applied \
            value. The nil return is what makes an unbound lane safe instead of a crash; if it \
            starts returning a value without a bound setter, an automation lane can claim to \
            have moved a parameter that no setter received.
            """)
        XCTAssertFalse(router.isBound(unbound), """
            `isBound` disagrees with the empty setter table. `automatableDescriptors()` filters \
            on exactly this predicate, so a wrong answer here puts a dead parameter into every \
            picker built from it.
            """)
    }

    // MARK: - claim 5 (COUNTERWEIGHT) — the honest set is the intersection, and it is non-empty

    func testTheAutomatableDescriptorsAreExactlyTheBoundOnes() {
        let registry = EchoelParameterRegistry()
        let router = ParameterApplyRouter(registry: registry)
        XCTAssertTrue(router.automatableDescriptors().isEmpty, """
            `automatableDescriptors()` returned parameters on a router with nothing bound. It is \
            defined as registry ∩ bound, and a UI builds its automation picker from it — a \
            non-empty answer here means a picker can offer a parameter with no live setter.
            """)
        var seen: [Float] = []
        router.bind("ddsp.env.attack") { seen.append($0) }
        let offered = router.automatableDescriptors().map(\.keyPath)
        XCTAssertEqual(offered, ["ddsp.env.attack"], """
            After binding exactly one keyPath the honest set is \(offered) rather than just \
            that one. Registry insertion order is preserved on purpose so a picker stays stable; \
            a different answer means either the filter or that ordering moved.
            """)
        XCTAssertNotNil(router.applyNormalized("ddsp.env.attack", 0.5), """
            A keyPath that IS bound reported no applied value. Claims 1 and 4 only mean \
            something if the bound path actually fires — without this, "unbound is a no-op" \
            would be green on a router where NOTHING fires.
            """)
        XCTAssertEqual(seen.count, 1, "the bound setter must be called exactly once per apply")
    }

    // MARK: - source access

    private struct AutomatableAnchorMissing: Error { let reason: String }

    /// Reads a repo source file as CODE, never prose (#453).
    private func codeText(_ relative: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path),
            "Sources/ not present in this checkout")
        let url = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AutomatableAnchorMissing(reason: """
                \(relative) is missing while the tree is present — renamed or moved. Re-anchor \
                this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: url, encoding: .utf8))
    }
}
