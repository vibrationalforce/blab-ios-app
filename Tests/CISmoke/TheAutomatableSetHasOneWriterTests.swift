// TheAutomatableSetHasOneWriterTests.swift
// Echoel — #556. Automation may own a parameter only where it is the ONLY writer.
//
// THE RULE, and it is the reason the automatable list has six entries rather than fifteen:
// `EchoelDDSP.applyBioReactive` recomputes six engine parameters from a `bioBase*` anchor on the
// RENDER thread, every block. Binding automation directly to one of those six produces a control
// that moves the value and has it overwritten within one render block — a placebo with a WORSE
// signature than the dead-stage kind (#546), because it works for a few milliseconds and so
// survives a debugger check. Automation must own the ANCHOR there, never the live parameter.
//
// ⛔ THE RULE WAS ALREADY WRITTEN ABOVE THE LIST; WHAT WAS WRONG IS ITS SIZE. It read
// "Bio-contested params (filter/brightness) are intentionally excluded". Measured — brace-extract
// `applyBioReactive`, look for assignments — the contested set is SIX: `brightness`,
// `filterCutoff`, `harmonicity`, `noiseLevel`, `vibratoDepth`, `vibratoRate`. A parenthetical
// naming two of six reads as the complete list, which is the same shape as the enum that read as
// a complete inventory one slice ago (#555) and the plan that read off it (#554). Three cycles,
// three enumerations that looked finished.
//
// ⭐ AND THE POSITIVE HALF HAD NEVER BEEN STATED AT ALL, which is why the six entries read as an
// arbitrary hand-picked list: they are EXACTLY the parameters `applyBioReactive` does not assign
// — zero hits each, measured. That is claim 1, and it is what turns "these felt safe" into a
// rule a stranger can apply.
//
// ⚠️ THE LIMIT. Claims 1 and 3 are SOURCE-TEXT SCANS over `EchoelDDSP` — the writes live inside a
// render-path method this bundle cannot call. Claim 2 is END-TO-END (the list is `public
// nonisolated`). DEVICE PROBE, open: whether an automated parameter is audibly steady rather than
// fighting the body. Nothing here plays anything.
//
// ⚠️ IT DOES NOT FORBID BINDING THE ANCHORS (#364) — the failure message names the anchor to
// bind. What it forbids is binding a CONTESTED LIVE PARAMETER, which is the edit that looks
// identical in a diff and behaves nothing like it.
//
// ⛔ #557 REWROTE THIS FILE, AND THE REASON IS THE BEST THING THAT HAPPENED TO IT: the guard went
// red on the CORRECT edit. #557 binds `ddsp.osc.harmonicity` to `bioBaseHarmonicity` — the anchor,
// exactly as the rule prescribes — and claims 1 and 2 called it a violation, because a HAND-
// WRITTEN table mapped that base to the live `harmonicity` from the keyPath's shape. The tempting
// repair was to edit the table, which would have left a session free to bind the LIVE property and
// quietly relabel it here. The mapping is now READ OUT OF `automatableSetter`'s own source, so the
// question "what does this setter write" has one answer instead of two (#416). Per §3, every
// assertion was re-driven after the rewrite, not just the changed ones.
//
// ⛔ AND THE RULE HAD AN EXCEPTION IT DID NOT COVER — claim 5, added by the same slice. "Bind the
// anchor" is not uniformly safe: three anchors are read behind a sentinel comparison, and for
// `bioBaseBrightness` the sentinel (`> 0`) sits INSIDE its descriptor's range (min 0). A lane
// passing through zero would flip `applyBioReactive` out of its anchored branch into the legacy
// one for the rest of the take — a mode change disguised as a parameter value. The other two
// sentinels are unreachable by arithmetic (cutoff starts at 20 Hz; the vibrato pair's sentinel is
// −1). One rule, one exception, both executable.
//
// ⚠️ HONEST GRADING — transcribed in Python against the parent (`4d93c72`) and this tree, ALL FIVE
// assertions driven on both:
//   · TWO REGRESSIONS, and they are the point of the slice: claims 1 and 2 are red on the parent
//     ONLY under the old hand-written mapping — under the source-derived mapping the parent is
//     green too, because the parent binds no anchor. Reported as what they are: the rewrite
//     REMOVED two false-positive verdicts rather than adding two findings. Booking them as
//     regressions caught by this file would be the flattering direction (#433).
//   · THREE COUNTERWEIGHTS green on both: claim 3 (the bio path still owns all six), claim 4 (the
//     patch still writes the anchors off the render thread — the precedent an anchor setter
//     follows) and claim 5 (brightness is out of the list on both trees).
//   · STRIPPER: PROPHYLAKTISCH, 0 of 10 verdicts flip. The brace extraction and the setter-source
//     read both run on stripped text, so a `bioBase*` mention inside a comment cannot be read as
//     a write and a `case "…"` quoted in prose cannot be read as a binding.

import XCTest
@testable import Echoelmusic

final class TheAutomatableSetHasOneWriterTests: XCTestCase {

    private static let ddsp = "Sources/Echoelmusic/DSP/EchoelDDSP.swift"
    private static let voice = "Sources/Echoelmusic/Tools/PolySynthVoice.swift"
    private static let patch = "Sources/Echoelmusic/DSP/SynthPatch.swift"

    /// The six live parameters the always-on bio path recomputes each render block. Named here
    /// as the SUBJECT of claim 1 rather than as an allowlist: claim 3 re-derives the same set
    /// from the source, so a seventh contested parameter cannot slip past by not being listed.
    private static let contested = [
        "brightness", "filterCutoff", "harmonicity", "noiseLevel", "vibratoDepth", "vibratoRate",
    ]

    // MARK: - claim 1 — every automatable base is unwritten by the bio path

    func testNoAutomatableBaseIsAlsoWrittenByTheBioPath() throws {
        let body = try bioBody()
        let setterSource = try codeText(Self.voice)
        for base in PolySynthVoice.automatableBases {
            guard let property = Self.property(ofBase: base, inSetterSource: setterSource) else {
                return XCTFail("""
                    `\(base)` has no property mapping in this test. A new automatable base was \
                    added without deciding whether the bio path writes it — which is the exact \
                    question this file exists to force. Add the mapping, then let claim 1 answer it.
                    """)
            }
            XCTAssertFalse(Self.assigns(property, in: body), """
                `\(base)` is bound as automatable, but `applyBioReactive` assigns `\(property)` \
                on the render thread every block. Automation would win for a few milliseconds and \
                then lose to the body — a control that moves in a debugger and cannot be heard. \
                Bind its `bioBase\(property.prefix(1).uppercased() + property.dropFirst())` anchor \
                instead, the way `SynthPatch.apply(to:)` already writes it, and leave the live \
                parameter to the render path.
                """)
        }
    }

    // MARK: - claim 2 (END-TO-END) — no contested parameter is on the list

    /// The mirror of claim 1, and the one that goes red on the tempting edit: adding
    /// `ddsp.osc.harmonicity` because "harmonicity is obviously automatable".
    func testNoContestedParameterIsOfferedAsAutomatable() throws {
        let setterSource = try codeText(Self.voice)
        for base in PolySynthVoice.automatableBases {
            guard let property = Self.property(ofBase: base, inSetterSource: setterSource) else { continue }
            XCTAssertFalse(Self.contested.contains(property), """
                `\(base)` maps to `\(property)`, which the bio path owns. See claim 1 — the fix \
                is the anchor, not the parameter. (If the bio path genuinely stopped writing it, \
                claim 3 goes red first and tells you to retire this rule rather than work around it.)
                """)
        }
    }

    // MARK: - claim 3 (COUNTERWEIGHT) — the contested set is still contested

    /// #343. Claims 1 and 2 both stay green on a tree where the bio path stopped writing
    /// ANYTHING — at which point the whole rule is obsolete and the six exclusions become an
    /// unexplained restriction. This is the premise, re-derived from source rather than assumed.
    func testTheBioPathStillOwnsAllSixContestedParameters() throws {
        let body = try bioBody()
        for property in Self.contested {
            XCTAssertTrue(Self.assigns(property, in: body), """
                `applyBioReactive` no longer assigns `\(property)`. If the always-on path stopped \
                owning it, the parameter is free and belongs in `automatableBases` directly — but \
                the exclusion note above that list, this file's `contested` list and the plan's \
                slice description all still say the body owns it. Move all four together.
                """)
        }
    }

    // MARK: - claim 5 — the one anchor whose sentinel is inside its own range stays out

    /// #557. "Bind the anchor" is not uniformly safe, and this is the exception the rule did not
    /// cover. `applyBioReactive` reads three anchors behind a sentinel comparison, and for
    /// `bioBaseBrightness` the sentinel is `> 0` while `ddsp.osc.brightness` has **min 0** — so a
    /// lane touching exactly zero would not merely darken the sound, it would flip the bio path
    /// out of its anchored branch into the legacy one, mid-take, with no signal. The other two
    /// are safe by arithmetic: `bioBaseFilterCutoff`'s `> 0` is unreachable from a range starting
    /// at 20 Hz, and the vibrato pair's `>= 0` is unreachable from a −1 sentinel.
    ///
    /// It does NOT forbid fixing this (#364). Removing the sentinel, or starting the descriptor
    /// above zero, makes the premise assertion below go red FIRST and say so — at which point
    /// binding brightness is correct and this case retires with it.
    /// `@MainActor` on the method rather than the class: only this case touches the registry,
    /// which is main-actor isolated. Claims 1–4 are file reads and stay unisolated.
    @MainActor
    func testBrightnessStaysOutWhileItsSentinelIsReachable() throws {
        let dsp = try codeText(Self.ddsp)
        let registry = EchoelParameterRegistry()
        guard let brightness = registry.descriptor(for: "ddsp.osc.brightness") else {
            return XCTFail("`ddsp.osc.brightness` left the registry — re-anchor this case (#454).")
        }
        // The premise, in two halves. Either one changing means the hazard is gone.
        let sentinelReachable = dsp.contains("bioBaseBrightness > 0") && brightness.min <= 0
        guard sentinelReachable else {
            return XCTFail("""
                The brightness hazard is gone — either `applyBioReactive` no longer gates on \
                `bioBaseBrightness > 0`, or the descriptor's minimum (\(brightness.min)) no longer \
                reaches it. Binding `ddsp.osc.brightness` to `bioBaseBrightness` is now correct: \
                add it, delete this case, and drop the brightness bullet from the ⛔ note above \
                `automatableBases`. This failure is the GO-AHEAD, not a defect.
                """)
        }
        XCTAssertFalse(PolySynthVoice.automatableBases.contains("ddsp.osc.brightness"), """
            `ddsp.osc.brightness` is automatable while its anchor is read behind `> 0` and its \
            descriptor still starts at \(brightness.min). A lane passing through zero silently \
            switches `applyBioReactive` from its anchored branch to the legacy one for the rest \
            of the take — a mode change disguised as a parameter value, and the one failure in \
            this family that a listener would blame on the patch rather than the automation.
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHT) — the anchors are still the patch-level value

    /// The other half of the premise: the rule says "automate the anchor" only because the anchor
    /// is what a patch already writes, off the render thread, as a plain `Float`. If that stopped
    /// being true, binding an anchor would need a NEW cross-thread mechanism and the ⚠️ note above
    /// `automatableBases` — which tells the next session to follow this precedent — would be
    /// pointing at nothing.
    func testThePatchStillWritesTheAnchorsOffTheRenderThread() throws {
        let code = try codeText(Self.patch)
        for anchor in ["bioBaseHarmonicity", "bioBaseNoiseLevel", "bioBaseBrightness",
                       "bioBaseFilterCutoff", "bioBaseVibratoDepth"] {
            XCTAssertTrue(code.contains("synth.\(anchor) ="), """
                `SynthPatch.apply(to:)` no longer writes `\(anchor)`. That write is the precedent \
                an automation anchor setter is told to follow (plain `Float`, atomic width, off \
                the render thread). Without it there is no established safe write, and binding \
                the anchor becomes a concurrency decision rather than a one-line setter.
                """)
        }
    }

    // MARK: - helpers

    private struct AutomatableAnchorMissing: Error { let reason: String }

    /// Which engine property a base's setter ACTUALLY writes, read out of `automatableSetter`'s
    /// own source.
    ///
    /// ⛔ THIS WAS A HAND-WRITTEN TABLE UNTIL #557, AND THE TABLE WAS THE LOOPHOLE. It mapped
    /// `ddsp.osc.harmonicity` → `harmonicity` from the keyPath's shape, which is right for a
    /// direct binding and WRONG for an anchor binding — #557 binds that base to
    /// `bioBaseHarmonicity`, the centre the bio path modulates around, which is exactly what
    /// the rule prescribes. With the table in place this guard would have gone red on the
    /// correct edit (#364), and the tempting repair would have been to edit the table — at
    /// which point a session could bind the LIVE property and quietly relabel it here. A second
    /// spelling of "what does this setter write" is the defect (#416); the setter is the only
    /// honest answer, so it is the one read.
    ///
    /// Returns nil when a base has no `case` — claim 1 turns that into a failure rather than a
    /// skip, because a missing case means `bindAutomatable` silently never binds it.
    private static func property(ofBase base: String, inSetterSource source: String) -> String? {
        guard let start = source.range(of: "case \"\(base)\":") else { return nil }
        let rest = source[start.upperBound...]
        // The case's own text: up to the next `case "` or the `default:` that closes the switch.
        let end = rest.range(of: "case \"")?.lowerBound
            ?? rest.range(of: "default:")?.lowerBound ?? rest.endIndex
        let body = rest[..<end]
        // `$0.<name> =` is the shape every setter uses. Anchored on `$0.` so a `v` on the
        // right-hand side or a property READ cannot be mistaken for the written one.
        guard let dollar = body.range(of: "$0.") else { return nil }
        let after = body[dollar.upperBound...]
        let name = after.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return name.isEmpty ? nil : String(name)
    }

    /// An ASSIGNMENT to `property` at the start of a line — not a mention. `bioBaseNoiseLevel` is
    /// read on the right-hand side of the `noiseLevel` write, so a plain `contains` would report
    /// every anchor as a contested parameter and every parameter as contested.
    private static func assigns(_ property: String, in body: String) -> Bool {
        body.split(separator: "\n").contains { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix(property) else { return false }
            let rest = t.dropFirst(property.count).drop { $0 == " " }
            return rest.first == "=" && rest.dropFirst().first != "="
        }
    }

    /// `applyBioReactive`'s body, brace-matched (#408). A line window is unsound here — the
    /// method is over five hundred lines and carries long comment blocks that
    /// `SourceText.codeOnly` preserves the height of.
    private func bioBody() throws -> String {
        let code = try codeText(Self.ddsp)
        guard let anchor = code.range(of: "func applyBioReactive"),
              let open = code.range(of: "{", range: anchor.upperBound..<code.endIndex) else {
            throw AutomatableAnchorMissing(reason: """
                `func applyBioReactive` was not found in \(Self.ddsp). Re-anchor this scan; a \
                silent skip here would report "nothing is contested" and green-light binding \
                every parameter the body owns (#454).
                """)
        }
        var depth = 0
        var i = open.lowerBound
        while i < code.endIndex {
            if code[i] == "{" { depth += 1 }
            if code[i] == "}" {
                depth -= 1
                if depth == 0 { return String(code[open.lowerBound...i]) }
            }
            i = code.index(after: i)
        }
        throw AutomatableAnchorMissing(reason: "unbalanced braces after `func applyBioReactive`")
    }

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
