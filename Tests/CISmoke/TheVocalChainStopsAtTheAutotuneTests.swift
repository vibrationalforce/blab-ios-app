// TheVocalChainStopsAtTheAutotuneTests.swift
// Echoel — #700. Blocking bundle, because the other suite cannot fail a merge (#208).
//
// WHAT THIS RECORDS. The founder asked (2026-08-20, verbatim) for "Monitoring und komplette
// Vocal chain mit Autotune (Charakter Einstellungen), Harmonizer, Voice clone!?, Granular
// Effekt". Four named stages. Measured 2026-08-21, TWO of them are on the signal he sings
// into and TWO are not — and nothing in the repo said so.
//
//   Monitoring   → HIS VOICE.  `setInputMonitoring`, doored by `AudioInputPickerView`.
//   Autotune     → HIS VOICE.  `voiceTunePitch` + `VoicePitchCorrector` (#599/#599b),
//                              character presets in the same sheet.
//   Harmonizer   → NOT his voice. It lives in `EchoelFXChain`.
//   Granular     → NOT his voice. It lives in `EchoelFXChain` (#684–#692).
//
// The monitor graph is exactly `input → notchEQ → [voiceTunePitch] → monitorMixer →
// masterMixer`: two stages, both `AVAudioUnit` GRAPH nodes, no Swift-DSP insert anywhere.
// `EchoelFXChain` occurs ZERO times in the whole of `Sources/Echoelmusic/Audio/` — not just
// in `AudioEngine.swift` — and its four construction sites are two curated-library previews
// plus the two SYNTH voices. So the harmonizer and the granular stage process the generated
// MUSIC, never the singer.
//
// ⭐ WHY THIS IS A REGISTER ENTRY AND NOT A BUG. Every outward-facing text is already
// honest, checked line by line: the store release notes say "harmony voices above the
// MELODY", `ContentPipeline/CLAIMS.md` already separates "nur der Monitor, nie die Musik"
// from the harmonizer line, `EchoelFXView`'s own header says "insert FX chain on the
// bio-reactive synth voice". Nothing over-claims to a user. The gap is INWARD: a session
// reading SESSION_LOG sees "Harmonizer shipped" and "Granular shipped" and concludes three
// of the founder's four names are done. Three are built; ONE of the two is routed to him.
// That is the Section-C law of the doctor skill — unreachable is not a defect, unreachable
// AND nowhere written down is.
//
// ⛔ THIS GUARD FORBIDS NOTHING (#364). Putting `EchoelFXChain` on the monitor path is the
// intended next slice (V1a) and it is a real audio-thread move — the first Swift-DSP insert
// on that path, hence Council, hence gated on the founder's pending device probe of the
// monitoring toggle itself. On the day someone wires it, claim 2 goes red BY DESIGN and its
// message names the prose to pull along in the SAME commit (#456). A red here is the good
// news.
//
// ⚠️ WHAT THIS CANNOT SEE. It reads the GRAPH, so it proves which nodes are connected, never
// what a listener hears. It also cannot tell an insert that is wired-but-bypassed from one
// that is absent — it only asserts absence, which is the weaker and currently true claim.
// "Voice clone" is not asserted anywhere here: it is an open founder question, not a state.
//
// ⛔ TWO COMPILE DEFECTS WERE CAUGHT BY READING, NOT BY A COMPILER — there is none here, and
// the auto-merge waits for no gate (#683), so a non-building test bundle would reach `main`.
// (1) Both filters over the file map were written `.map(\.key)`. `Dictionary.filter` returns a
// Dictionary whose Element is the TUPLE `(key:value:)`, and Swift key paths cannot address a
// tuple member — `git grep 'map(\.key)'` over `Sources` and `Tests` returns nothing, so there
// was no precedent to lean on either. Now an explicit `{ $0.key }`, which is unambiguous.
// (2) The root helper had `let root` inside `func root()`. Rewritten as `repoRoot()`/`base`.
// Neither would have failed a review of the LOGIC; both would have failed the build.
//
// ⚠️ HONEST LIMITS. 5 tests, 9 assertion statements (2+2+2+1+2; counted in Python over lines
// whose first token is XCTAssert).
//
// ⭐ GRADING (§3). Every needle was transcribed in Python against the real tree before this
// file was written. Claims 1–4 are COUNTERWEIGHTS: green at the parent too, and that is the
// point — they record a standing state, they do not create it. Claim 5 is FORWARD: the
// CLAUDE.md line it reads is created by this same commit and could never have been red
// before it. ZERO regressions, and booking any of these as one would be the flattering
// direction (#464).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheVocalChainStopsAtTheAutotuneTests: XCTestCase {

    private static let engine = "Sources/Echoelmusic/Audio/AudioEngine.swift"

    // MARK: - 1: the anchor — the monitor chain exists and starts where we say

    /// Without this every negative below is vacuous (#454): a renamed monitor graph would
    /// make "the FX chain is not on it" trivially true.
    func testTheMonitorChainExistsAndStartsAtTheNotch() throws {
        let src = try source(Self.engine)
        XCTAssertTrue(src.contains("connect(input, to: notchEQ"), """
            The monitor chain no longer starts `input → notchEQ`. Everything below is a \
            statement about that graph — re-anchor it rather than letting the negatives \
            pass empty.
            """)
        XCTAssertTrue(src.contains("monitorMixer"), """
            `monitorMixer` is gone from the engine. If the monitor path was restructured, \
            re-measure which stages reach the singer before trusting this file.
            """)
    }

    // MARK: - 2: THE FINDING — no Swift-DSP insert reaches the sung voice

    /// ⭐ Two of the founder's four named stages live in `EchoelFXChain`, and that type is
    /// absent from the entire audio layer.
    func testTheFXChainIsAbsentFromTheWholeAudioLayer() throws {
        let src = try source(Self.engine)
        XCTAssertFalse(src.contains("EchoelFXChain"), """
            `EchoelFXChain` APPEARED IN AudioEngine. If that is the V1a wiring, this claim \
            has done its job — delete it, and in the SAME commit (#456) correct: this \
            file's header table, and CLAUDE.md's vocal-chain line, which currently states \
            that the harmonizer and the granular stage do NOT reach the sung voice.
            """)
        let audioDir = try directory("Sources/Echoelmusic/Audio")
        let leaked = audioDir.filter { $0.value.contains("EchoelFXChain") }.map { $0.key }.sorted()
        XCTAssertTrue(leaked.isEmpty, """
            \(leaked) in the audio layer now name `EchoelFXChain`. The finding was measured \
            across the WHOLE directory, not just the engine, precisely so a second host \
            node could not slip in beside it — see the message above for the prose to move.
            """)
    }

    // MARK: - 3: the counterweight that keeps this proportionate — autotune IS on his voice

    /// ⚠️ WITHOUT THIS the file reads as "the vocal chain is unbuilt", which is false and
    /// would invite rebuilding what #599 already shipped.
    func testTheAutotuneStageIsOnTheMonitorPath() throws {
        let src = try source(Self.engine)
        XCTAssertTrue(src.contains("voiceTunePitch"), """
            The in-key correction stage is gone from the monitor chain. That is the ONE of \
            the founder's four named stages that reaches the signal he sings into — if it \
            was removed, this whole file's framing changes and the header table is wrong.
            """)
        XCTAssertTrue(src.contains("VoicePitchCorrector"), """
            The corrector that gives the autotune its CHARACTER (strength + retune speed — \
            the founder's "Charakter Einstellungen") is gone. Same repair as above.
            """)
    }

    // MARK: - 4: the other counterweight — this is a ROUTING gap, not a missing capability

    /// The harmonizer and the granular stage are BUILT and reachable; they are simply
    /// pointed at the synth bus. Deleting either because "the vocal chain is unbuilt"
    /// would be the exact wrong reading.
    func testTheFXChainIsBuiltAndLivesOnTheSynthVoices() throws {
        let sources = try directory("Sources/Echoelmusic")
        let builders = sources.filter { $0.value.contains("EchoelFXChain(") }.map { $0.key }.sorted()
        XCTAssertFalse(builders.isEmpty, """
            Nothing constructs an `EchoelFXChain` any more. Then the harmonizer and the \
            granular stage make no sound at all, on ANY path, and this file's "built, just \
            routed elsewhere" framing is wrong — correct it before trusting claim 2.
            """)
    }

    // MARK: - 5: the register names the split

    /// The reason this file exists. The founder will repeat the ask; the file a session
    /// reads first has to say which half of it is already pointed at him.
    func testTheRegisterRecordsWhichStagesReachTheSungVoice() throws {
        let claude = try rawFile("CLAUDE.md")
        XCTAssertTrue(claude.contains("Monitoring + Autotune sitzen auf dem Monitorpfad"), """
            CLAUDE.md no longer records which of the founder's four named vocal stages \
            reach the signal he sings into. That omission is what this whole file was \
            written for — a session that cannot read it will re-derive "three of four are \
            done" from SESSION_LOG, which is true of BUILT and false of ROUTED.
            """)
        XCTAssertTrue(claude.contains("Harmonizer und Granular NICHT"), """
            The half of the register line that names the two stages which do NOT reach his \
            voice is gone. If V1a landed, claim 2 above is red too and that is the correct \
            order of repair; if claim 2 is green, the prose drifted and the prose is wrong.
            """)
    }

    // MARK: - file access

    private struct DiagAnchorMissing: Error { let reason: String }

    /// ⚠️ The local is `base`, not `root`: a `let root` inside `func root()` shadows the
    /// method with a `URL`, and every later `root.appendingPathComponent` would then need
    /// the compiler to prefer the local over `() throws -> URL`. It does — but this file
    /// has no local compiler to confirm it, and an ambiguity that only Xcode sees is the
    /// #679 shape. Renamed so the question cannot arise.
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let base = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: base.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(base.path)") }
        return base
    }

    private func source(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DiagAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or \
                moved. Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// Every `.swift` under `relativePath`, stripped of comments, keyed by file name.
    /// ⚠️ Comments are stripped on purpose, and it is NOT load-bearing today: measured
    /// 2026-08-21, `Sources/Echoelmusic/Audio/` names `EchoelFXChain` zero times in code
    /// AND zero times in prose. It becomes load-bearing the first time someone writes
    /// `// EchoelFXChain is deliberately not here` — a raw scan would then read the
    /// warning ABOUT the absence as the presence, which is the #491 collision in the
    /// direction that goes GREEN-to-RED on a correct tree.
    private func directory(_ relativePath: String) throws -> [String: String] {
        let dir = try repoRoot().appendingPathComponent(relativePath)
        guard let walker = FileManager.default.enumerator(atPath: dir.path) else {
            throw DiagAnchorMissing(reason: "\(relativePath) cannot be walked — re-anchor (#454).")
        }
        var out: [String: String] = [:]
        for case let name as String in walker where name.hasSuffix(".swift") {
            let url = dir.appendingPathComponent(name)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            out[name] = SourceText.codeOnly(text)
        }
        guard !out.isEmpty else {
            throw DiagAnchorMissing(reason: """
                \(relativePath) holds no Swift files — the extraction found nothing, so \
                every filter over it would pass empty (#454).
                """)
        }
        return out
    }

    private func rawFile(_ relativePath: String) throws -> String {
        let path = try repoRoot().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw DiagAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — re-anchor (#454).
                """)
        }
        return try String(contentsOf: path, encoding: .utf8)
    }
}
