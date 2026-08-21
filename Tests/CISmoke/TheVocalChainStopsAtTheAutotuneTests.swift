// TheVocalChainStopsAtTheAutotuneTests.swift
// Echoel — #700, corrected in full by its reviewer as #701 (twelve findings, all twelve
// re-measured and all twelve upheld). Blocking bundle: the other suite cannot fail a
// merge (#208).
//
// WHAT THIS RECORDS. The founder asked (2026-08-20, verbatim) for "Monitoring und komplette
// Vocal chain mit Autotune (Charakter Einstellungen), Harmonizer, Voice clone!?, Granular
// Effekt". Four named stages. Measured 2026-08-21, TWO of them are on the signal he sings
// into and TWO are not — and the file every session reads FIRST did not say so.
//
// ⛔ THE FIRST VERSION OF THAT SENTENCE SAID "nothing in the repo said so", AND THAT WAS
// FALSE IN FIVE PLACES — every one of them older than this commit, four of them measured:
// `scratchpads/PLAN_VOCAL_CHAIN_2026-08-20.md` ("The complete vocal chain is one connection
// away from the microphone and nobody has made it", written the DAY of the ask),
// `decisions.csv:398`, `Sources/Echoelmusic/Sequencer/VoicePitchCorrector.swift` and
// `Sources/Echoelmusic/DSP/EchoelGranular.swift` (both carry the graph string and the
// zero-count recipe in their own headers), and `PLAN_LIVE_MONITORING_VOICE_2026-08-19.md`.
// So this file is not a DISCOVERY — it is the CLAUDE.md home for something four other
// files already knew, plus a guard. That is still worth a cycle, and claiming more than it
// is the exact shape #697/#698/#699 spent three commits retracting: an over-claim that the
// tree could refute before it was written.
//
//   Monitoring   → HIS VOICE.  `setInputMonitoring`, doored by `AudioInputPickerView`.
//   Autotune     → HIS VOICE.  `voiceTunePitch` + `VoicePitchCorrector` (#599); the
//                              character presets are #681, in the same sheet. (#599b is the
//                              HARMONIZER's "Follow the key" — citing it here would have
//                              used the half that is NOT on his voice as proof that it is.)
//   Harmonizer   → NOT his voice. It lives in `EchoelFXChain`.
//   Granular     → NOT his voice. It lives in `EchoelFXChain` (#684–#692).
//
// The monitor graph is exactly `input → notchEQ → [voiceTunePitch] → monitorMixer →
// masterMixer`: two stages, both `AVAudioUnit` GRAPH nodes, no Swift-DSP insert anywhere.
// `EchoelFXChain` occurs ZERO times in the whole of `Sources/Echoelmusic/Audio/` — not just
// in `AudioEngine.swift`, and neither do `EchoelHarmonizer` and `EchoelGranular`, which is
// what claim 2 scans for since #701. Its four construction sites are two curated-library
// previews plus the two SYNTH voices. So the harmonizer and the granular stage process the
// generated MUSIC, never the singer.
//
// ⭐ WHY THIS IS A REGISTER ENTRY AND NOT A BUG. Every outward-facing text is already
// honest, checked line by line: the store release notes say "harmony voices above the
// MELODY", `ContentPipeline/CLAIMS.md` already separates "nur der Monitor, nie die Musik"
// from the harmonizer line, `EchoelFXView`'s own header says "insert FX chain on the
// bio-reactive synth voice". Nothing over-claims to a user.
// ⚠️ One row sits closer to the line than that sentence suggests, and naming it is cheaper
// than defending it later: `ContentPipeline/CLAIMS.md:63` puts "Follow the key" (the
// harmonizer) in the SAME row, under the heading „Tonart-Werkzeuge für die Stimme", as the
// monitor-only "Tune to key". The qualifier does attach to Tune-to-key alone and §11 of that
// file is explicit, so the claim holds — but that row is the one outward text a reader could
// misread as putting the harmonizer on the singer. The gap is INWARD: a session
// skimming the #684–#692 build reports reads the granular chain as closed and carries that
// over to the whole ask. FOUR of the four are built; TWO of them are routed to him.
//
// ⛔ THE FIRST VERSION QUOTED "Harmonizer shipped" + "Granular shipped" AS SESSION_LOG TEXT.
// Neither string exists anywhere in the repo, and the passage it pointed at says the
// OPPOSITE — `SESSION_LOG.md`'s #692 entry reads "für das INSTRUMENT geschlossen", in caps.
// A fabricated citation inside a block warning about over-claims, in a commit whose message
// boasts of catching that class (#694). It also said "Three are built; ONE of the two",
// contradicting this file's own table two paragraphs up. Both corrected here, in place,
// rather than silently — the invented quotation is the more expensive half, because a
// number invites re-measurement and a quotation invites trust.
// That is the Section-C law of the doctor skill — unreachable is not a defect, unreachable
// AND nowhere written down is.
//
// ⛔ THIS GUARD FORBIDS NOTHING (#364). Putting `EchoelFXChain` on the monitor path is
// **V1b**, and it is gated on V1a and V0 before it. `decisions.csv:398` splits the work:
// V1a = an EMPTY pass-through `AUAudioUnit` proven in the monitor chain, V1b = the chain
// riding it — and the same row records that the mechanism question (AUAudioUnit subclass
// vs. `AVAudioSourceNode` ring) was already decided by Council on measured latency (#669),
// so this is not an open architectural question. (⛔ The first version of this block, and
// of the CLAUDE.md line beside it, called the chain-on-the-path "V1a" and appended
// "⇒ Council" — two spellings of one slice label, the new one in the ALWAYS-LOADED file,
// which is #416 on the exact identifier a later session greps for.) On the day someone
// wires it, claim 2 goes red BY DESIGN and its message names the prose to pull along in
// the SAME commit (#456). A red here is the good news.
//
// ⚠️ WHAT THIS CANNOT SEE. It reads the GRAPH, so it proves which nodes are connected, never
// what a listener hears. It also cannot tell an insert that is wired-but-bypassed from one
// that is absent — it only asserts absence, which is the weaker and currently true claim.
// "Voice clone" is not asserted anywhere here: it is an open founder question, not a state.
//
// ⛔ TWO COMPILE DEFECTS WERE CAUGHT BY READING, NOT BY A COMPILER — there is none here, and
// the auto-merge waits for no gate (#683), so a non-building test bundle would reach `main`.
// (1) Both filters over the file map were written `.map(\.key)`. `git grep 'map(\.key)'` over
// `Sources` and `Tests` returns nothing, so there was no precedent to lean on; now an
// explicit `{ $0.key }`, chosen to avoid a question no local compiler can settle.
// ⛔ The first version justified that swap with "Swift key paths cannot address a tuple
// member" — a FALSE LAW, and this directory had already retracted it: `Tests/CISmoke/CLAUDE.md`
// §5 #689 records exactly that sentence nearly entering the always-loaded file, and
// `OneSpellingOfTheDemoSubjectTests.swift` runs `.map(\.2)` over a tuple array in THIS bundle
// on every green build. The ACTION was right and stays; only its reason was invented.
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
        // ⛔ The first version anchored ONLY on `connect(input, to: notchEQ`, and `input` is a
        // LOCAL (`let input = masterEngine.inputNode`), not a member. `Tests/CISmoke/CLAUDE.md`
        // §3 names that class outright: renaming that local to `inputNode` — an ordinary clarity
        // edit that moves no cable — would turn this red on a fully correct tree, and §5 says a
        // genuine red is indistinguishable from #396. Every other node in the chain IS a member,
        // so the load-bearing anchor is now the member-to-member hop; the local-named one is
        // kept only as the weaker second reading.
        XCTAssertTrue(src.contains("connect(notchEQ, to: monitorMixer"), """
            The `notchEQ → monitorMixer` hop is gone. Both nodes are members, so this is the \
            anchor that a rename of a local cannot break — if it is missing, the monitor graph \
            really was restructured. Re-measure which stages reach the singer before trusting \
            anything below.
            """)
        XCTAssertTrue(src.contains("connect(voiceTunePitch, to: monitorMixer"), """
            The optional tune stage no longer feeds the monitor mixer. Claim 3 below says that \
            stage is the founder's autotune ON his voice — if this hop is gone, that claim is \
            what needs re-measuring first.
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
        // ⛔ The first version scanned for the TYPE `EchoelFXChain` only, and that is fail-open
        // against a live option: the founder named two STAGES, and `decisions.csv:398` rejects an
        // Apple-node route precisely because it "kann Harmonizer und Granular nicht liefern". A
        // wiring that inserts `EchoelHarmonizer` directly would leave this green while CLAUDE.md's
        // "Harmonizer und Granular NICHT" went silently false. All three names are scanned now.
        let audioDir = try directory("Sources/Echoelmusic/Audio")
        let hosts = ["EchoelFXChain", "EchoelHarmonizer", "EchoelGranular"]
        let leaked = audioDir
            .filter { file in hosts.contains(where: { file.value.contains($0) }) }
            .map { $0.key }.sorted()
        XCTAssertTrue(leaked.isEmpty, """
            \(leaked) in the audio layer now name one of \(hosts). The scan covers the WHOLE \
            directory and all three names so neither a second host node nor a single stage can \
            slip in. If this is V1b, SIX prose homes go stale in the same commit (#456): this \
            file's header table · CLAUDE.md's vocal-chain line · \
            Sources/Echoelmusic/Sequencer/VoicePitchCorrector.swift · \
            Sources/Echoelmusic/DSP/EchoelGranular.swift · \
            scratchpads/PLAN_VOCAL_CHAIN_2026-08-20.md · decisions.csv:398. The two source \
            headers are the dangerous ones — they are `///` docs a session reads WHILE editing \
            the files V1b touches.
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
        // ⛔ The first version only asserted `!builders.isEmpty` while its NAME and CLAUDE.md
        // both assert WHICH files — #367: a claim must fail for the reason it gives. A fifth site
        // on a third bus would have left it green and the register line stale. Keys are relative
        // SUBPATHS (`FileManager.enumerator(atPath:)` yields those, not bare names), and
        // `FXCuratedLibrary` contributes ONE key for its two construction sites.
        let sources = try directory("Sources/Echoelmusic")
        let builders = sources.filter { $0.value.contains("EchoelFXChain(") }.map { $0.key }.sorted()
        XCTAssertEqual(builders, ["Studio/FXCuratedLibrary.swift",
                                  "Tools/BioReactiveSynthVoice.swift",
                                  "Tools/PolySynthVoice.swift"], """
            The set of files constructing an `EchoelFXChain` changed. If it SHRANK to empty the \
            stages make no sound on ANY path and this file's "built, just routed elsewhere" \
            framing is wrong. If it GREW, CLAUDE.md's "vier Konstruktionsstellen: zwei \
            Vorschauen in FXCuratedLibrary plus die zwei SYNTH-Stimmen" is stale — move it in \
            this commit (#456). Note a site under `Audio/` would ALSO make claim 2 red; that \
            is the V1b case and its message lists the prose.
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

    /// Every `.swift` under `relativePath`, stripped of comments, keyed by its path RELATIVE
    /// to that directory — `FileManager.enumerator(atPath:)` yields subpaths, not bare names,
    /// so a key reads `Tools/PolySynthVoice.swift`. Claim 4's expected set depends on that.
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
