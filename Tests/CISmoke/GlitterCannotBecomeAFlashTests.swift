// GlitterCannotBecomeAFlashTests.swift
// Echoel — #578. The founder asked for more; the answer must stay flash-safe and stay bounded.
//
// THE ASK, verbatim (2026-08-13): *"je intensiver das Erlebnis desto besser. Bunter, mehr
// Textur, Glitzer etc., Räumlichkeit."* #578 answers the first three. Räumlichkeit is a
// separate cycle on purpose — it needs the field function, not the colour tail.
//
// ⭐ WHY A GUARD AT ALL FOR A TASTE CHANGE. Three of this slice's edits are NOT taste:
//   1. **Glitter is animated luminance**, and this app has a hard 3 Hz ceiling (W3C/WCAG,
//      epilepsy) written into its brand line and its safety warnings. The block is safe by
//      CONSTRUCTION — every speck draws its own phase AND its own frequency from its position
//      hash, so specks are mutually uncorrelated and the frame's mean luminance does not
//      modulate. **The obvious way to write the same effect — one global `sin(u.time)` term
//      multiplying all specks — is unsafe at ANY rate**, and is one careless edit away. That
//      is what claim 2 forbids.
//   2. **The two new additive lines sit immediately above a SCREEN blend** whose identity
//      `outCol += ripple * (1 - outCol)` only holds while `outCol ≤ 1`. Above 1 the factor
//      goes negative and the touch-ripple starts SUBTRACTING light from the brightest places
//      — the artifact the 2026-07-09 audit already paid for once, in the same expression.
//      The filmic S-curve above used to leave `outCol` clamped and the blend inherited that
//      for free; #578 consumed the bound and had to restore it. Claim 3 pins the restoration.
//      ⚠️ #1059 NOTE, so a reader who follows "above" is not confused: that filmic line no
//      longer contains a per-channel clamp at all — it now shapes LUMINANCE and keeps gamut by
//      dividing by the peak (the clamp rotated hue, which was its own defect). The sentence
//      above stays because it is HISTORY and explains why claim 3 exists; what it describes is
//      simply no longer visible up there. The bound the ripple needs is unaffected either way:
//      peak-normalising also lands `outCol` at ≤ 1, and #578's own clamp — the line claim 3
//      pins — sits between the glitter and the blend regardless.
//   3. **The default that renders is not the one the shader declares.** All three mounted
//      surfaces pass `saturation:` explicitly from `@AppStorage(visualSaturation)`, so the
//      two `var saturation: Float =` defaults in `MetalBioView.swift` are overwritten at
//      every call site. #578's first version moved only those two and transcribed a guard
//      over them: it would have been GREEN while the screen stayed exactly as grey. What
//      caught it was the wider `git grep` for the literal — the §4 step that is meant to run
//      BEFORE touching a surface, not after writing the guard. Claim 1 pins the reachable
//      default; claim 1b pins that all three surfaces still read it.
//
// ⚠️ WHAT IS DELIBERATELY **NOT** PINNED (#364): not one of the tuned numbers. Not 1.05, not
// 0.97, not 0.05, not the spark gain, not the grain gain. Every one of them is a judgement a
// later cycle — or the founder's next look at the device — may legitimately move, and a guard
// that freezes a taste value gets deleted along with the law it carries. What is pinned is
// the SHAPE: relations, floors, a ceiling, and the presence of the two safety mechanisms.
//
// ⚠️ THE LIMIT, PER ASSERTION (§1): claim 1 is END-TO-END over the shipped, `public`,
// Foundation-only `StudioDefaultKeys.visualSaturation` — the value the three surfaces
// actually pass to the GPU. Claims 1b–4 are SOURCE-TEXT SCANS: for the shader because
// `MetalBioView` compiles it from a `String` at runtime so no bundle can render it, and for
// the surfaces because their `@AppStorage` members are `private` on `View`s no bundle can
// instantiate. DEVICE PROBE, open and NOT covered: whether the field now reads colourful
// rather than grey, whether the glitter reads as sparkle rather than noise, and whether it
// stays comfortable over a long session. That is the founder's next clip.
//
// ⚠️ AND ONE THING NO GUARD HERE CAN COVER, said plainly rather than left to be assumed:
// `@AppStorage` prefers a STORED value, so claim 1's default only reaches an install that has
// never had its Saturation field dragged. The shader-side warm-tint change in the same slice
// is unconditional and does reach every install. "The grey is fixed" is therefore not a claim
// this slice may make — only "the two things that made it grey were both changed".
//
// ⚠️ HONEST GRADING (§3), hand-transcribed in Python against the parent (`472f8b3`) and this
// tree — no local toolchain (§0). **14 assertions.** Unlike the last three slices' guards this
// file names NO symbol the commit creates, so it compiles against the parent and every
// assertion genuinely has a verdict there:
//   · **1 REGRESSION.** Claim 1, red on the parent for exactly the reason its name gives:
//     0.82 < 1.0.
//   · **4 red by ANCHOR ABSENCE, reported as ONE finding (#486):** claims 2 and 3 scan for
//     the glitter block, which the parent does not have. Booking four of those as four
//     regressions is the flattering direction of #433. Note what claim 3 does on the parent:
//     it takes the `XCTFail("re-anchor")` path, NOT its ordering message — an honest failure
//     saying the extraction found nothing, which is what §2 asks for over a false ordering.
//   · **9 COUNTERWEIGHTS**, green on both trees (claims 1b, 1c, 4) — and the point of the
//     file. Every positive scan above is satisfied just as well by a shader that deleted the
//     darkness floor, the reduce-motion time gate or the dither, all of which would make the
//     picture "more intense"; and by a surface that stopped reading the shared key.
//   · STRIPPER: **PROPHYLAKTISCH (0 of 14 verdicts flip)** — measured raw vs. stripped on
//     both trees, not assumed. Worth measuring here rather than anywhere: the shader is a
//     Swift multi-line string literal whose lines carry `//` comments, and `SourceText
//     .codeOnly` resets string state per LINE, so it strips those as if they were code. Every
//     needle above therefore had to sit left of a `//`, and that was checked, not hoped.

import Foundation
import XCTest
// No platform `#if`. The one type driven end-to-end here — `StudioDefaultKeys` — is
// Foundation-only and unguarded; wrapping the assertion in `canImport(Metal…)` would add a
// condition the shipped code does not have, and a guard that can silently skip is worth less
// than one that cannot (#454).
@testable import Echoelmusic

final class GlitterCannotBecomeAFlashTests: XCTestCase {

    private static let viewPath = "Sources/Echoelmusic/Views/MetalBioView.swift"

    // MARK: - claim 1 (END-TO-END) — the palette that ACTUALLY RENDERS is not pulled to grey

    /// ⛔ THIS ASSERTION FIRST READ `MetalBioView().saturation` AND WOULD HAVE BEEN GREEN ON A
    /// GREY SCREEN. The struct defaults are overwritten at every call site: all three mounted
    /// surfaces pass `saturation:` explicitly from `@AppStorage(visualSaturation)`, so the
    /// literal the GPU receives is THIS one. #578 changed the struct pair first, transcribed a
    /// guard over it, and only caught the fourth copy on the wider `git grep` that §4 says to
    /// run BEFORE touching a surface. Pinning a value nothing reads is exactly the shape §4
    /// calls "green for a reason that no longer exists" — here, for a reason that never was.
    ///
    /// A FLOOR, not the value (#364). Anything below neutral desaturates before the user
    /// touches the VJ control, and this was the last of three stacked desaturators (0.92 ×
    /// ~0.90 × 0.82 ≈ 0.68 net chroma). Above 1.0 is the point; how far above is taste.
    func testTheSaturationDefaultThatRendersDoesNotPullTowardGrey() {
        XCTAssertGreaterThanOrEqual(StudioDefaultKeys.visualSaturation.value, 1.0, """
            The rendering `saturation` default is back below neutral. That is the state #578 \
            was asked to leave — the founder said "Bunter" — and B9 already proved that \
            fixing one of the three stacked desaturators is not enough on its own. Raising it \
            further is fine; going back under 1.0 is a founder call, not a taste call, and \
            the last taste call made here is retracted at the declaration.
            """)
    }

    // MARK: - claim 1b (SOURCE SCAN) — the default still reaches all three surfaces

    /// The premise claim 1 needs and cannot check by itself: on a tree where a surface stopped
    /// reading the shared key, claim 1 stays green while that surface renders whatever its own
    /// literal says. That is the drift the shared `StudioDefault` exists to prevent — and the
    /// reason the `EchoelStudioView` doc comment that RESTATED "0.82" was #416, not a typo.
    func testEveryMountedSurfaceTakesItsSaturationFromTheSharedDefault() throws {
        for path in ["Sources/Echoelmusic/Studio/EchoelStudioView.swift",
                     "Sources/Echoelmusic/Studio/FloatingVisualWindow.swift",
                     "Sources/Echoelmusic/Studio/ExternalDisplayScene.swift"] {
            let src = try source(path)
            XCTAssertTrue(src.contains("StudioDefaultKeys.visualSaturation.key"), """
                \(path) no longer binds the shared `visual.saturation` key. Whatever it \
                renders is then independent of the default claim 1 pins, and the three \
                surfaces can show three different palettes in the same session.
                """)
        }
    }

    // MARK: - claim 1c (SOURCE SCAN) — and the two FALLBACK copies cannot drift apart

    /// Labelled weaker than it looks, on purpose: these are fallbacks, reachable only by a
    /// caller that omits `saturation:` — which today does not exist. Kept because the day such
    /// a caller appears, a silent mismatch makes the look depend on which path built the
    /// uniforms, and that is a bug nobody would think to look for.
    func testBothFallbackSaturationDefaultsAreTheSameNumber() throws {
        let src = try source(Self.viewPath)
        let decls = src.components(separatedBy: "var saturation: Float = ").dropFirst()
        XCTAssertEqual(decls.count, 2, """
            `var saturation: Float = ` is declared a number of times other than two. There are \
            deliberately exactly two — the private `BioUniforms` default and the \
            `MetalBioView` mirror — and this scan cannot compare them if the count changes. \
            Re-anchor rather than deleting (#454).
            """)
        let values = decls.map { chunk -> String in
            String(chunk.prefix { "0123456789.".contains($0) })
        }
        XCTAssertEqual(values.first, values.last, """
            The two fallback `saturation` defaults have drifted apart \
            (\(values.joined(separator: " vs "))). The look would then depend on which \
            construction path built the uniforms. Move both or neither.
            """)
    }

    // MARK: - claim 2 (SOURCE SCAN) — the twinkle is per-speck, never one global term

    /// THE SAFETY CLAIM OF THE WHOLE SLICE. Not a rate check — a STRUCTURE check, because at
    /// this layer structure is what makes the rate unmeasurable. Both halves are needed and
    /// they fail differently: without the per-speck PHASE every speck peaks on the same frame;
    /// without the per-speck FREQUENCY they drift apart at first and then beat back into
    /// alignment, which is worse than obvious.
    ///
    /// AMPLITUDE FACTORS ARE OUTSIDE THIS ARGUMENT, deliberately (#853): the user Glitter
    /// dial (`u.glitterAmt`) multiplies the OUTPUT line only. Correlation lives in phase and
    /// frequency, which stay per-speck at any gain — so a gain dial at any value in its
    /// clamp cannot re-correlate the specks, and `TheFinishDialsReachTheShaderTests` may
    /// point here for exactly that sentence.
    func testTheGlitterPhaseAndFrequencyAreBothPerSpeck() throws {
        let src = try source(Self.viewPath)
        let twinkle = "float tw = 0.5 + 0.5 * sin(u.time * (3.4 + gSeed * 2.2) + gSeed * 6.2831853);"
        XCTAssertTrue(src.contains(twinkle), """
            The glitter twinkle is no longer the per-speck form. Both terms of that line are \
            flash-safety, not style: `gSeed` inside the FREQUENCY makes neighbouring specks \
            run at different rates, and `gSeed` in the PHASE offset makes them start apart. \
            Reduce it to a shared `sin(u.time * k)` and every speck on screen peaks on the \
            same frame — a coherent full-area luminance flash at k/2π Hz, which is precisely \
            what the 3 Hz WCAG ceiling in this app's safety warnings is about. If the tuning \
            numbers moved on purpose, keep BOTH `gSeed` terms and update this needle.
            """)
        XCTAssertTrue(src.contains("float gSeed  = echoelHash(gcell + 17.0);"), """
            The per-speck seed is gone, so nothing can decorrelate the specks even if the \
            twinkle line still looks per-speck. The offset (`+ 17.0`) is load-bearing too: \
            without it `gSeed` equals the hash that decides WHICH cells spark, so the sparse \
            surviving cells would all share a narrow seed range — correlated again, by a \
            subtler route than a shared term.
            """)
        XCTAssertTrue(src.contains("* energy;") && src.contains("float spark = gAlive"), """
            The glitter is no longer gated on `energy`. Two consequences, one aesthetic and \
            one not: sparkle on black reads as sensor dirt rather than water, and an ungated \
            twinkle keeps modulating while the field itself is dark and still — the only \
            state in which a viewer's eye has nothing else to track.
            """)
    }

    // MARK: - claim 3 (SOURCE SCAN) — the additive lines restore the bound the blend needs

    func testTheAdditiveTailIsClampedBeforeTheScreenBlend() throws {
        let src = try source(Self.viewPath)
        guard let sparkAt = src.range(of: "float spark = gAlive")?.lowerBound,
              let clampAt = src.range(of: "outCol = clamp(outCol, 0.0, 1.0);")?.lowerBound,
              let rippleAt = src.range(of: "outCol += rippleLight(uv, u)")?.lowerBound else {
            XCTFail("""
                one of the three anchors (spark / clamp / rippleLight) is gone — re-anchor \
                this ordering scan rather than letting it skip (#454).
                """)
            return
        }
        XCTAssertTrue(sparkAt < clampAt && clampAt < rippleAt, """
            The clamp is not between the additive glitter/grain tail and the touch-ripple \
            SCREEN blend. That blend is `outCol += ripple * (1 - outCol)`, and it only adds \
            light while `outCol <= 1`. Once the glitter pushes a lit pixel above 1 the factor \
            turns NEGATIVE and a touch SUBTRACTS light — dark holes punched in the brightest, \
            most glittered places. This is the same expression the 2026-07-09 artifact audit \
            already fixed once (raw add clipping to white patches); it inherited its safety \
            from the filmic S-curve's clamp until #578 inserted two additive lines below it. \
            An additive term above a screen blend must restore the bound it consumed.
            """)
    }

    // MARK: - claim 4 (COUNTERWEIGHT) — intensity was not bought by removing a safeguard

    /// Green on both trees, and the point of the file. Every assertion above is satisfied just
    /// as well by a shader that deleted the darkness floor, the reduce-motion time gate or the
    /// dither — each of which would make the picture "more intense" and each of which is a
    /// safety or quality mechanism this repo paid for separately.
    func testTheSurroundingSafeguardsAreUntouched() throws {
        let src = try source(Self.viewPath)
        for (needle, why) in [
            "uniforms.time = reduceMotion ? 0 : Float(nowT - startTime)":
                """
                the reduce-motion time gate is gone. It is what makes the glitter degrade \
                correctly for free: at `time == 0` every speck collapses to its own static \
                phase and the twinkle becomes a still specular field. Without it, an \
                accessibility setting that must stop motion would leave the newest moving \
                element on screen running
                """,
            "col *= (lum < 0.35) ? (0.35 / max(lum, 0.04)) : 1.0;":
                """
                the hue-preserving darkness floor is gone. Raising saturation makes deep \
                red/violet tones MORE dependent on it, not less — those are the colours the \
                eye reads as nearly black through the CMF
                """,
            "outCol += (echoelHash(in.uv * 1000.0) - 0.5) / 255.0;":
                """
                the anti-banding dither is gone. It shares `echoelHash` with the new grain \
                and is easy to mistake for a duplicate of it — it is not: the dither is \
                sub-quantisation-step and unconditional, the grain is visible and gated on \
                `energy`
                """,
            "clamp(u.saturation, 0.0, 2.0)":
                """
                the saturation clamp is gone. The default now sits above 1.0, so the VJ \
                control's headroom above neutral is doing real work and an unbounded value \
                would drive the colour matrix past the point where it stays a colour
                """
        ] {
            XCTAssertTrue(src.contains(needle), """
                \(why) — `\(needle)` is absent. #578 was allowed to make the picture richer, \
                not to remove what keeps it safe and legible.
                """)
        }
    }

    // MARK: - source access (§0/§2 — one stripper, skip on no tree, FAIL on a moved anchor)

    private struct GlitterAnchorMissing: Error { let reason: String }

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw GlitterAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or moved. \
                Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }
}
