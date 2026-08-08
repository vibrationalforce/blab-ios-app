// AFailedSaveLeavesATraceTests.swift
// Echoel — #514. A failed WRITE used to be completely silent, while a failed READ has been
// logged since `AppGroupStore` existed.
//
// THE DEFECT IS A CONTRACT WITH ONE SIDE BUILT. The store's header stated the design —
// *"write failures surface as false so callers decide how loud to be"* — and MEASURED across
// `Sources/` there are **12** `store.save(…)` call sites and **ZERO** look at the `Bool`
// (ten rely on `@discardableResult`, two write `_ =` explicitly). The delegation was to
// nobody, and the sentence made an unchosen silence read as a decision somebody had made.
//
// ⭐ WHY IT IS WORSE THAN THE READ CASE rather than merely symmetrical. A failed read falls
// back to an empty document, which the user SEES immediately. A failed write leaves the
// PREVIOUS file on disk and the in-memory list already updated: the library looks correct
// for the rest of the session, and the loss appears on the next launch with nothing left to
// connect it to the save. `testAFailedSaveLeavesTheOldFileStanding` is that fact, driven.
//
// ⭐ AND IT IS THE REGISTERED `Project` HALF OF #512, arriving as telemetry rather than as
// coercion. `JSONEncoder`'s default `nonConformingFloatEncodingStrategy` is `.throw`;
// `Project.init` does NOT clamp `bpm`, so `Project(bpm: .nan, …)` is representable today and
// its save silently does nothing. #512 coerced the ONE payload that crosses the network,
// where `0` is the receiver's own documented "not available". A saved song has no such
// convention — writing `0` into someone's tempo would invent a number (#424/#426/#433), so
// what this slice buys is that the failure is no longer invisible. Deciding what the UI says
// is a founder-surface question and is registered, not smuggled in (#515).
//
// ⚠️ EHRLICHE BENOTUNG (#433), transcribed against the parent tree rather than asserted
// (Python rebuild of `SourceText.codeOnly` plus the brace matcher, run against
// `git show 43513e8:` and the worktree, every needle driven separately). This file DOES
// compile against the parent — it names no symbol this commit adds — so every assertion has
// a real verdict, unlike the #464 situation.
//
// **TWO test methods are red on the parent** (three needles, TWO findings: the encode
// branch's `try?` present AND its log absent are two sides of ONE edit, counted once — #486;
// plus the write branch's missing log). **SIX are green on both trees, and that is the
// honest headline of this slice: it changes NO BEHAVIOUR AT ALL.** `try?` and do/catch both
// returned `false`, so every behavioural case above passes on the parent too. What the slice
// adds is telemetry — and saying so is the #433 rule, because booking the four behavioural
// cases as regressions would flatter it into a bug fix it is not (#489's shape).
//
// The six green ones are still the point rather than filler: the parity anchor on the read
// log (delete it and the symmetry argument this whole file rests on dies quietly), the
// honest `Bool`, and four behavioural cases that keep a scan-only guard from staying green
// on a store that lost its write path entirely (#343).
//
// ⚠️ `SourceText.codeOnly` is PROPHYLACTIC here and that is MEASURED, not assumed — the
// over-claim #484/#485 each had to retract once and #486 twice, and my first draft of this
// paragraph made it a third time. Raw versus stripped differ on **0 of 8** needle verdicts,
// across both trees. The reason is worth writing down because it is a hair's breadth and
// will stop holding: the ⭐ block this slice writes quotes `try? encoder.encode(value)`
// VERBATIM, but it sits ABOVE the declaration line the scan anchors on, so `declarationBody`
// never sees it. Move that retraction INSIDE the body — or add any comment in there naming
// the removed form — and the negative needle goes RED ON CORRECT CODE. The #486/#491
// collision, one edit away rather than already here.
//
// ⚠️ AND THE LIMIT FIRST. Nothing here proves a log line is EMITTED, let alone that anyone
// reads it: `log` is `#if canImport(os)`-guarded and a test cannot observe the unified log.
// The behavioural half drives the shipped `AppGroupStore` end to end (it is `public`, pure
// Foundation, and falls back to Application Support outside a container); the telemetry half
// is a SOURCE SCAN that the branches call the logger at all. Whether a failed save should
// also reach the SCREEN is untested and deliberately undecided.

import XCTest
@testable import Echoelmusic

private struct SaveAnchorMissing: Error, CustomStringConvertible {
    let reason: String
    var description: String { reason }
}

/// A minimal `Codable` whose one field can be made unwritable. Deliberately NOT `Project`
/// for the mechanism cases: the store's contract is generic, and pinning it through a
/// 20-field document would make a later `Project` change look like a store regression.
/// `Project` appears once, on its own, to show the mechanism is reachable from a real
/// user document rather than only from a fixture.
private struct Tiny: Codable, Equatable {
    var label: String
    var value: Double
}

final class AFailedSaveLeavesATraceTests: XCTestCase {

    private var writtenSubdirectories: [String] = []

    /// One throwaway container per test. The pattern (and the reason for the UUID) is
    /// `AutosaveSlotTests`': a simulator container is REUSED between local runs, so a
    /// stable tag alone lets one run read what the previous left behind.
    private func isolatedStore(_ tag: String = #function) -> AppGroupStore {
        let subdirectory = "EchoelTests-save-\(tag)-\(UUID().uuidString)"
        writtenSubdirectories.append(subdirectory)
        return AppGroupStore(subdirectory: subdirectory)
    }

    override func tearDown() async throws {
        for subdirectory in writtenSubdirectories {
            AppGroupStore(subdirectory: subdirectory).delete(name: fileName)
        }
        writtenSubdirectories = []
    }

    private let fileName = "unwritable-probe"

    // MARK: - Behaviour (drives the shipped store end to end)

    /// COUNTERWEIGHT (#343). Without this, every scan below stays green on a store whose
    /// write path was deleted outright — the failure mode a negative-only guard cannot see.
    func testAnOrdinaryValueStillSavesAndComesBack() {
        let store = isolatedStore()
        let written = Tiny(label: "ordinary", value: 42.5)

        XCTAssertTrue(store.save(written, name: fileName),
                      "an ordinary value must still report a successful write")
        XCTAssertEqual(store.load(Tiny.self, name: fileName), written,
                       "and must come back byte-identical")
    }

    /// The mechanism, driven: JSON cannot carry a non-finite Double, so the encode throws
    /// and `save` must say so rather than reporting success it did not achieve.
    func testAValueJSONCannotWriteReportsFailure() {
        let store = isolatedStore()
        for bad in [Double.nan, .infinity, -.infinity] {
            XCTAssertFalse(store.save(Tiny(label: "bad", value: bad), name: fileName),
                           "\(bad) cannot be written as JSON — save must return false")
        }
    }

    /// THE REASON THE SILENCE WAS DANGEROUS, stated as behaviour rather than as prose: the
    /// previous file survives, so on the next read everything looks correct. In the app the
    /// in-memory list has ALREADY been updated by then, which is why the loss only appears
    /// on the following launch.
    func testAFailedSaveLeavesTheOldFileStanding() {
        let store = isolatedStore()
        let good = Tiny(label: "keep me", value: 1)
        XCTAssertTrue(store.save(good, name: fileName))

        XCTAssertFalse(store.save(Tiny(label: "lost", value: .nan), name: fileName))
        XCTAssertEqual(store.load(Tiny.self, name: fileName), good, """
            the failed write must not have replaced or truncated the file — and THAT is why \
            a silent false is worse than a failed read: nothing on screen changes.
            """)
    }

    /// Reachability from a real user document, not only from a fixture. `Project.init`
    /// applies no clamp to `bpm`, so this is representable today; it is the registered
    /// `Project` half of #512. If a later slice DOES coerce persisted floats, this assertion
    /// is the one to revisit deliberately — do not relax it as incidental.
    func testARealProjectWithANonFiniteTempoIsNotWritableEither() {
        let store = isolatedStore()
        let broken = Project(
            name: "broken tempo",
            styleRaw: MusicStyle.offered.first?.rawValue ?? "ambient",
            keyRoot: 0, scaleRaw: Scale.major.rawValue, bpm: .nan,
            modeRaw: ComposerMode.flowFree.rawValue,
            fxCharacterRaw: FXCharacter.clean.rawValue,
            loopBars: 8, a4Hz: 440, toneSystemID: "edo12", artist: "",
            patch: SynthPatch(name: "Test"), notes: [], rawTake: nil,
            drumSteps: [], drumAccents: []
        )
        XCTAssertFalse(store.save([broken], name: fileName), """
            a Project carrying a non-finite tempo cannot be encoded, so the whole library \
            write fails — which is exactly the class #512 closed for the peer stream.
            """)
    }

    // MARK: - Telemetry (source scans — a log cannot be observed from here)

    /// REGRESSION. The encode branch must not swallow the error. `try?` threw it away, so
    /// even a caller who DID check the `Bool` could not tell "the disk is full" from "a NaN
    /// got into your song" — and the error's `codingPath` names the field.
    func testTheEncodeErrorIsCaughtRatherThanDiscarded() throws {
        let body = try declarationBody(
            of: "public func save<T: Encodable>(_ value: T, name: String) -> Bool {",
            in: "Sources/Echoelmusic/Core/AppGroupStore.swift")

        XCTAssertFalse(body.contains("try? encoder.encode("), """
            `try?` discards the encode error. Use do/catch so the failure can name the \
            field that could not be written (#514).
            """)
        XCTAssertTrue(body.contains("failed to ENCODE"), """
            the encode branch must log — it is the only place the reason for a lost save \
            exists at all.
            """)
    }

    /// REGRESSION. The write branch already used do/catch; it simply said nothing.
    func testTheWriteFailureIsLogged() throws {
        let body = try declarationBody(
            of: "public func save<T: Encodable>(_ value: T, name: String) -> Bool {",
            in: "Sources/Echoelmusic/Core/AppGroupStore.swift")

        XCTAssertTrue(body.contains("failed to WRITE"), """
            an atomic write that throws (full disk, protected container while locked) must \
            leave a trace; it is indistinguishable from success to every caller.
            """)
    }

    /// COUNTERWEIGHT, and the one this file rests on. The whole argument for logging a write
    /// is SYMMETRY with the read. Delete the read's log and the argument evaporates while
    /// every other assertion here stays green — so pin it from this side too.
    func testTheReadPathStillLogsItsOwnDataLossSignal() throws {
        let body = try declarationBody(
            of: "public func load<T: Decodable>(_ type: T.Type, name: String) -> T? {",
            in: "Sources/Echoelmusic/Core/AppGroupStore.swift")

        XCTAssertTrue(body.contains("present but failed to decode"), """
            #514's reasoning is 'the write should be as loud as the read'. If the read stops \
            logging, decide that deliberately — do not let it lapse.
            """)
    }

    /// COUNTERWEIGHT. The obvious later 'simplification' is to stop returning a `Bool` at
    /// all, now that the store logs. That would remove the only signal a caller could ever
    /// escalate from, and #515 is exactly about building that caller side.
    func testSaveStillReportsSuccessHonestly() {
        let store = isolatedStore()
        XCTAssertTrue(store.save(Tiny(label: "ok", value: 0), name: fileName))
        XCTAssertFalse(store.save(Tiny(label: "no", value: .nan), name: fileName))
    }

    // MARK: - Source access (house template)

    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw SaveAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or \
                moved. Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The brace-matched body following `key`, which must end in its opening brace.
    /// Anchoring on the declaration keeps a doc comment from satisfying a needle, and the
    /// ABSENCE of the anchor throws rather than returning "" — the #425 lesson: a scan that
    /// silently measures an empty string passes for the wrong reason.
    private func declarationBody(of key: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        guard let start = text.range(of: key) else {
            throw SaveAnchorMissing(reason: """
                \(relativePath) no longer declares `\(key)`. This scan is anchored on it; \
                re-anchor rather than deleting the assertion.
                """)
        }
        var depth = 0
        var body = ""
        for ch in text[text.index(before: start.upperBound)...] {
            if ch == "{" { depth += 1 }
            if depth > 0 { body.append(ch) }
            if ch == "}" {
                depth -= 1
                if depth == 0 { break }
            }
        }
        return body
    }
}
