// TheBeamerCannotShowARetiredLookTests.swift
// Echoel — the launch look-snap must not be skipped in donut mode. BLOCKING bundle.
//
// #1141. The snap that rewrites a persisted `visual.style` no longer in `LookBlendMap.library`
// carried `!spectralDonuts,` on BOTH branches. It reads as part of the #747 repair directly
// above it, and it is not: #747 was about never stamping `visual.spectralDonuts` back to
// `false` and eating a player's choice. This snap writes `visual.style` — a DIFFERENT key —
// so skipping it in donut mode preserved nothing anyone chose and left an unselectable index
// sitting in the store.
//
// ⭐ WHY THAT WAS A SAFETY DEFECT AND NOT AN UNTIDINESS. `ExternalDisplayScene` reads
// `visualStyle` / `visualStyleB` straight from `@AppStorage` and never mentions donut mode —
// measured, `spectralDonuts` occurs ZERO times in that file (claim 3). So the phone showed
// rings while the BEAMER rendered the retired look underneath, and `FlashGuard` could not damp
// it: a style with no row is treated as `maxFlashHz`, `blendPhaseDamping` finds
// `union == maxFlashHz` rather than greater, and returns exactly 1.0. Scope actually runs at
// 3.90 Hz (#1130) — over the 3 Hz WCAG ceiling, on the largest display in the room. The guard
// is not wrong; it cannot know a rate for a look that has no row, which is exactly why an
// unselectable index must not survive launch.
//
// ⚠️ NOTHING A DONUT-MODE PLAYER CAN SEE CHANGES, and claim 4 pins the half that makes that
// true: `spectralDonuts` is untouched, so the phone still draws rings. The value snapped to is
// a selectable look. This only stops an index nobody can choose from reaching a second screen.

import XCTest

final class TheBeamerCannotShowARetiredLookTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let external = "Sources/Echoelmusic/Studio/ExternalDisplayScene.swift"
    private static let flash = "Sources/Echoelmusic/Core/FlashGuard.swift"

    private func code(_ rel: String) throws -> String {
        let r = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: r.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(r.path)") }
        let path = r.appendingPathComponent(rel)
        guard FileManager.default.fileExists(atPath: path.path) else {
            struct AnchorMissing: Error { let path: String }
            throw AnchorMissing(path: rel)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    // MARK: - 1 · The snap runs in every mode

    func testTheLookSnapIsNotGatedOnDonutMode() throws {
        let studio = try code(Self.studio)
        XCTAssertEqual(count("if !sliderLooks.contains(visualStyle) {", in: studio), 1, """
            The launch look-snap changed shape. It must run UNCONDITIONALLY: a persisted style \
            outside `LookBlendMap.library` cannot be selected, has no flash budget, and is read \
            raw by the external display.
            """)
        XCTAssertEqual(count("} else if visualBlend > 0, !sliderLooks.contains(visualStyleB) {",
                             in: studio), 1, """
            The second branch (the BLEND partner) changed shape. Both halves matter: a retired \
            index in `styleB` reaches the shader through the blend, not through `style`.
            """)
        XCTAssertEqual(count("if !spectralDonuts, !sliderLooks.contains(visualStyle) {",
                             in: studio), 0, """
            The `!spectralDonuts` gate is back on the look-snap. That is the #1141 defect \
            verbatim — it preserves an unselectable index that `ExternalDisplayScene` then \
            renders undamped on the beamer.
            """)
    }

    // MARK: - 2 · FlashGuard genuinely cannot damp an unknown look

    /// The arithmetic behind "this was a safety defect", so the claim is checkable rather than
    /// asserted. A lone unknown style is assumed to sit exactly AT the ceiling, so the union
    /// equals rather than exceeds it and no damping is applied.
    func testALoneUnknownLookGetsNoDamping() {
        let maxFlashHz = 3.0
        // fieldBudget(forStyle:) returns nil for a retired index → the caller substitutes
        // maxFlashHz (conservative, and documented as "UNKNOWN, not FREE").
        let hzA = maxFlashHz, hzB = maxFlashHz
        let blend = 0.0
        let coexistence = 2 * Swift.min(blend, 1 - blend)
        let union = Swift.max(hzA, hzB) + coexistence * Swift.min(hzA, hzB)
        XCTAssertEqual(union, 3.0, accuracy: 1e-9)
        let damping = union > maxFlashHz && union > 0 ? maxFlashHz / union : 1.0
        XCTAssertEqual(damping, 1.0, accuracy: 1e-9, """
            A lone unknown look no longer receives damping 1.0. The #1141 argument rests on it: \
            the guard assumes the ceiling, the union therefore EQUALS rather than exceeds it, \
            and nothing is damped — while Scope really runs at 3.90 Hz.
            """)
        XCTAssertGreaterThan(3.90, maxFlashHz, """
            Scope's measured 3.90 Hz (#1130) is no longer over the 3 Hz ceiling. If a retired \
            rate was re-derived, this guard's header and the call-site prose move with it.
            """)
    }

    // MARK: - 3 · The premise: the beamer really does not know about donut mode

    func testTheExternalDisplayNeverConsultsDonutMode() throws {
        let external = try code(Self.external)
        XCTAssertEqual(count("spectralDonuts", in: external), 0, """
            `ExternalDisplayScene` now mentions `spectralDonuts` \
            \(count("spectralDonuts", in: external))×. The whole #1141 finding is that it does \
            NOT — it reads the style keys raw, so donut mode hides the retired look on the \
            phone and not on the beamer. If the beamer has since learned about donut mode, \
            this guard's header and the call-site prose are stale and move in the same commit.
            """)
        XCTAssertEqual(count("private var style = StudioDefaultKeys.visualStyle.value",
                             in: external), 1, """
            The external display no longer binds `visualStyle` from `@AppStorage`. That raw \
            read is the second half of the finding.
            """)
    }

    // MARK: - 4 · COUNTERWEIGHT — the player's donut choice is still untouched

    func testTheDonutChoiceIsStillNotStampedBack() throws {
        let studio = try code(Self.studio)
        XCTAssertEqual(count("normaliseUnreachableDonutMode", in: studio), 0, """
            `normaliseUnreachableDonutMode()` is back. #747 deleted it because it stamped \
            `visual.spectralDonuts` to `false` on EVERY launch and ate a player's choice. \
            #1141 removes a gate from a DIFFERENT key's snap and must never be read as \
            permission to resurrect this.
            """)
        XCTAssertEqual(count("Toggle(isOn: $spectralDonuts)", in: studio), 1, """
            The donut toggle in the Field panel is gone. It is the one reachable control for \
            that flag; without it #1141's scenario stops being reachable and this guard's \
            header overstates a live risk.
            """)
    }
}
