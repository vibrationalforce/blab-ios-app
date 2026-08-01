// DisabledReverbIsNotClaimedLiveTests.swift
// Echoel — #335. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// ⭐ THE CLAIM THIS EXISTS FOR: `docs/architecture.html` is the PUBLISHED GitHub Pages page.
// It carried a row tagged **LIVE** reading "Convolution reverb with synthetic impulse response
// inside EchoelDDSP — wet/dry and decay control, HRV-reactive". Every clause of that was
// unreachable: `EchoelDDSP.useConvolutionReverb` is declared `false` and has NO writer anywhere
// in `Sources/`, both consumers are gated on it, and the declaration's own comment gives the
// reason ("heap corruption → EXC_BAD_ACCESS on the first note"). So the stage makes no sound,
// its "wet/dry and decay control" moves nothing, and `applyBioReactive` states in-line that
// reverb DECAY is deliberately not bio-modulated at all.
//
// ⛔ AND THE FIX WAS NOT "DELETE THE ROW", which is the trap a summary of this finding leads
// straight into. There IS a live reverb, just not that one: `EchoelReverb` in `EchoelFXChain`
// — algorithmic, off by default, switched on and dialled by each genre's preset (`GenreFX`
// carries real `reverbEnabled`/`reverbMix`/`reverbRoom`/`reverbDamping` values for many
// genres). Deleting the row would have replaced an overstatement with an understatement and
// hidden a shipping feature. The row now names the reverb that sounds and says the other one
// is off. Correcting a false claim means finding the TRUE claim, not removing the sentence.
//
// THE INVARIANT, deliberately narrow and mechanical: WHILE the convolution reverb is disabled,
// every line of the page that mentions it must also say so. Once someone enables it — a writer
// setting the flag true, or a different default — this guard falls silent on its own, exactly
// like `LoudnessReadoutMeasurementPointTests` does once the measurement point moves. It cannot
// be satisfied by accident: "disabled" has to be written next to the claim.
//
// ⚠️ WHAT THIS FILE DOES NOT COVER, said out loud because the same #335 sweep fixed it and a
// reader will otherwise assume it is pinned: the page's bio-mapping row listed mappings that
// no longer exist (the filter-LFO speed mapping went with #331; `damping` appears zero times
// in `EchoelDDSP`; `breathDepth` and `lfHfRatio` have no producer). That is prose against ~350
// lines of DSP with no single token to key on — a guard for it would be a second copy of the
// mapping list, i.e. the thing most likely to rot while looking like coverage. Same reasoning
// as the four EQ frequencies in `AutoGainClampMatchesTheWebsiteTests`. It is anchored in
// `applyBioReactive`'s own comments instead, which sit on the same screen as the code.

import Foundation
import XCTest

final class DisabledReverbIsNotClaimedLiveTests: XCTestCase {

    private static let ddsp = "Sources/Echoelmusic/DSP/EchoelDDSP.swift"
    private static let page = "docs/architecture.html"
    private static let flag = "useConvolutionReverb"

    func testThePageDoesNotSellAReverbThatCannotSound() throws {
        guard try convolutionReverbIsDisabled() else { return }   // silent once it is enabled

        // ⛔ SPACES NORMALISED FIRST, and the sibling guard is the reason: it hit exactly this
        // and solved it, and the first version of THIS file regressed the fix. The page writes
        // every tight pair as `48&nbsp;kHz`, `±6&nbsp;dB`, `Delta&nbsp;2`; one `&nbsp;` between
        // "convolution" and "reverb" renders identically and would make the phrase invisible
        // here — a green over an unfixed lie, or a red over nothing, depending which line moved.
        let claims = Self.normalisingSpaces(try source(Self.page))
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { $0.lowercased().contains("convolution reverb") }

        XCTAssertFalse(claims.isEmpty, """
            No line of `\(Self.page)` mentions the convolution reverb any more. That is fine if \
            it was removed on purpose — delete this test in the SAME commit. It is NOT fine if \
            the row was replaced by a bare "reverb" claim: the live one is `EchoelReverb` in \
            `EchoelFXChain` and the page should name it, or a reader learns nothing.
            """)

        for claim in claims {
            XCTAssertTrue(claim.lowercased().contains("disabled"), """
                The published page mentions the convolution reverb without saying it is off:
                \(claim.trimmingCharacters(in: .whitespaces))
                `EchoelDDSP.\(Self.flag)` is `false` and nothing in `Sources/` assigns it, so \
                that stage produces no sound, its wet/dry and decay controls move nothing, and \
                `applyBioReactive` says in-line that reverb decay is not bio-modulated.
                Name `EchoelReverb` (the algorithmic one in `EchoelFXChain`, switched on by the \
                genre presets) as the reverb that sounds, and mark this one disabled. Do not \
                simply delete the sentence — that would hide a feature that does work.
                """)
        }
    }

    /// TRUE while the flag is declared `false` and no file turns it on. Both halves matter: a
    /// `false` default with a writer somewhere would make the page's LIVE claim legitimate,
    /// and this guard must not fire on a correct page.
    private func convolutionReverbIsDisabled() throws -> Bool {
        guard try source(Self.ddsp).contains("\(Self.flag) = false") else { return false }
        for file in try swiftFilesUnderSources() {
            let code = Self.codeOnly(try String(contentsOf: file, encoding: .utf8))
            if code.contains("\(Self.flag) = true") { return false }
        }
        return true
    }

    // MARK: - helpers

    /// Comments dropped before scanning for a writer — WHOLE-LINE, TRAILING **and** `/* … */`.
    ///
    /// ⛔ THE FIRST VERSION STRIPPED ONLY WHOLE-LINE `//`, and the commit message claimed
    /// "comments are stripped" without that qualifier. Review showed the gap is a FALSE-GREEN,
    /// which is the worst outcome this file can have: a trailing `// was useConvolutionReverb
    /// = true` or any block comment containing that string makes `convolutionReverbIsDisabled`
    /// return false, the test `return`s early, and the gate reports success while the page
    /// keeps selling a stage that does not sound. A silent guard is indistinguishable from a
    /// passing one — which is the exact defect the `doctor` skill exists for.
    ///
    /// Still not a Swift parser: `//` inside a string literal is stripped too. That direction
    /// only ever ARMS the guard (a claimed writer disappears), so it fails safe.
    private static func codeOnly(_ text: String) -> String {
        var out = ""
        var rest = Substring(text)
        while let open = rest.range(of: "/*") {
            out += rest[..<open.lowerBound]
            if let close = rest.range(of: "*/", range: open.upperBound..<rest.endIndex) {
                rest = rest[close.upperBound...]
            } else {
                rest = rest[rest.endIndex...]      // unterminated: drop the tail
            }
        }
        out += rest
        return out.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let slashes = line.range(of: "//") else { return String(line) }
                return String(line[..<slashes.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// HTML space entities → a plain space. Same helper, same reason, as the sibling guard
    /// `AutoGainClampMatchesTheWebsiteTests`: the page encodes tight pairs as `&nbsp;`, and a
    /// comparison that depends on which encoding was used is a guard about formatting, not
    /// about the claim.
    private static func normalisingSpaces(_ text: String) -> String {
        text.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("""
                Source tree not reachable from the test bundle — skipping rather than reporting \
                a green this file did not earn.
                """)
        }
        return root
    }

    private func source(_ path: String) throws -> String {
        try String(contentsOf: repoRoot().appendingPathComponent(path), encoding: .utf8)
    }

    private func swiftFilesUnderSources() throws -> [URL] {
        let dir = try repoRoot().appendingPathComponent("Sources/Echoelmusic")
        guard let walk = FileManager.default.enumerator(at: dir,
                                                        includingPropertiesForKeys: nil) else {
            throw XCTSkip("could not enumerate Sources/Echoelmusic")
        }
        return walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
