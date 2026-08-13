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
// ⚠️ IT DOES NOT FORBID BINDING THE ANCHORS (#364) — that is the next slice, and the failure
// message says so. What it forbids is binding a CONTESTED LIVE PARAMETER, which is the edit that
// looks identical in a diff and behaves nothing like it.
//
// ⚠️ HONEST GRADING — transcribed in Python against the parent (`50c5fd7`) and this tree. ALL
// FOUR are COUNTERWEIGHTS: green on both, because this slice adds no binding and changes no
// engine code. The source change it does make is prose (the exclusion's size). Booking any of
// them as a regression would be the flattering-direction defect (#433); the file earns its place
// under #343 — it converts an advisory comment into an executable rule, and every premise it
// pins is one edit away from silently ceasing to hold. STRIPPER: PROPHYLAKTISCH, 0 of 8 verdicts
// flip — every needle is an assignment or a declaration in code, and the brace extraction runs on
// stripped text so a `bioBase*` mention inside a comment cannot be read as a write.

import XCTest
@testable import Echoelmusic

final class TheAutomatableSetHasOneWriterTests: XCTestCase {

    private static let ddsp = "Sources/Echoelmusic/DSP/EchoelDDSP.swift"
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
        for base in PolySynthVoice.automatableBases {
            guard let property = Self.property(ofBase: base) else {
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
    func testNoContestedParameterIsOfferedAsAutomatable() {
        for base in PolySynthVoice.automatableBases {
            guard let property = Self.property(ofBase: base) else { continue }
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

    /// Which engine property a registry base writes. Deliberately explicit rather than derived
    /// from the keyPath's last component: `ddsp.amp.level` targets `patchOutputLevel`, not
    /// `level`, and that mismatch is the whole reason the mapping is written out (the doc above
    /// `automatableBases` records why it is NOT `amplitude`).
    private static func property(ofBase base: String) -> String? {
        switch base {
        case "ddsp.warmth.drive":     return "warmthDrive"
        case "ddsp.env.attack":       return "attack"
        case "ddsp.env.decay":        return "decay"
        case "ddsp.env.sustain":      return "sustain"
        case "ddsp.env.release":      return "release"
        case "ddsp.amp.level":        return "patchOutputLevel"
        case "ddsp.osc.brightness":   return "brightness"
        case "ddsp.filter.cutoff":    return "filterCutoff"
        case "ddsp.osc.harmonicity":  return "harmonicity"
        case "ddsp.osc.noiseLevel":   return "noiseLevel"
        case "ddsp.mod.vibratoDepth": return "vibratoDepth"
        case "ddsp.mod.vibratoRate":  return "vibratoRate"
        default: return nil
        }
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
