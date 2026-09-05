import XCTest
@testable import Echoelmusic

/// #1015 — the two doc comments a session reads first must not deny a data path that exists.
///
/// WHY IT EXISTS. `EngineBus.latestBio` is a SINGLE slot. `stopBioSource()` said "Stop EVERY bio
/// publisher … so no source keeps feeding the bus", and `selectBioSource` said "Only ONE source
/// feeds the bus at a time". Both were false for any Health-authorised user:
/// `HealthKitBioPublisher` is constructed and started at APP level and appears nowhere in
/// `Studio/` outside a doc comment, so its wrist samples keep overwriting the camera or strap
/// frame the performer chose.
///
/// ⭐ THE COST IS MEASURED IN CYCLES, NOT IN MILLISECONDS. Three separate slices have each had
/// to rediscover this interleave from scratch, because the first two sentences anyone reads
/// about bus ownership both said it could not happen. A doc comment that denies a real path does
/// not merely fail to help — it spends a cycle each time it is believed.
///
/// ⚠️ THIS GUARD DOES NOT FORBID THE FIX (#364). The interleave is deliberate and documented
/// elsewhere; the audit's remedy is a HOLD at the two timbre consumers, and that half is
/// founder-gated because it changes the sound. If a later commit legitimately brings HealthKit
/// under the picker, claim 1 goes red and names the prose that must move in the same commit —
/// which is the whole point of pinning it.
///
/// ⚠️ WHY NO CLAIM SCANS FOR THE OLD SENTENCES. The ⛔ blocks that RETRACT them quote both
/// verbatim, so a negative scan would match its own retraction (#491) — the same trap
/// `TheStalledPillSaysWhySilentTests` had to repair one commit earlier. The claims below assert
/// the corrected qualifier is PRESENT instead, which cannot be satisfied by a quotation.
///
/// GRADING (written after transcription, and the transcription corrected my guess). Only
/// claim 4 is RED on `HEAD` — it is the one that names wording this commit introduces. Claims
/// 1, 2 and 3 are GREEN on BOTH, and that is the finding, not an accident: **the CODE was
/// already right on `HEAD`; only the prose about it was wrong.** I had expected claim 1 to be
/// red because its subject is the function this slice repairs — but this slice repairs the
/// function's DOC, and the receiver set it pins never moved. A claim's colour follows its
/// needle, never the commit's subject.
final class ThePickerDoesNotOwnEverySourceTests: XCTestCase {

    private static let studio = "Sources/Echoelmusic/Studio/EchoelStudioView.swift"
    private static let app = "Sources/Echoelmusic/EchoelmusicApp.swift"
    private static let studioDir = "Sources/Echoelmusic/Studio"

    private func root() -> URL {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        return dir
    }

    private func source(_ relative: String) throws -> String {
        let url = root().appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read — a missing anchor is a "
                    + "finding, not a pass.")
            return ""
        }
        return text
    }

    /// Lines of a `{ … }` member starting at the line that opens it, brace-counted.
    private func memberBody(from marker: String, in text: String) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let start = lines.firstIndex(where: { $0.contains(marker) }) else { return nil }
        var depth = 0
        var out: [String] = []
        for line in lines[start...] {
            out.append(line)
            depth += line.filter { $0 == "{" }.count
            depth -= line.filter { $0 == "}" }.count
            if depth <= 0 && out.count > 1 { break }
        }
        return out.joined(separator: "\n")
    }

    // 1 — the body stops exactly the three the picker owns. A fourth receiver appearing here is
    //     allowed and may well be right; it just cannot arrive while the prose says otherwise.
    func testTheStopBodyStopsExactlyThePickersOwnThree() throws {
        let text = try source(Self.studio)
        guard let body = memberBody(from: "private func stopBioSource() {", in: text) else {
            return XCTFail("ANCHOR MISSING: `private func stopBioSource() {` — re-derive this guard.")
        }
        var receivers: Set<String> = []
        for line in body.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("//"), !trimmed.hasPrefix("///") else { continue }
            guard let dot = trimmed.range(of: ".stop()") else { continue }
            receivers.insert(String(trimmed[trimmed.startIndex..<dot.lowerBound]))
        }
        XCTAssertEqual(receivers, ["cameraRPPG", "polarH10", "demoSource"], """
            `stopBioSource()` now stops \(receivers.sorted().joined(separator: ", ")).

            That change is ALLOWED (#364) — bringing HealthKit under the picker may be the right \
            call. What is not allowed is doing it silently: this function's ⛔ block and \
            `selectBioSource`'s both state that the picker owns three sources and that the \
            app-level HealthKit publisher is outside its reach. Correct both in the SAME commit, \
            and update this expected set with them.
            """)
    }

    // 2 — MEASUREMENT behind the claim: HealthKit is not in the Studio layer at all, except as
    //     prose. This is what makes "the picker does not own it" a fact rather than an opinion.
    func testHealthKitAppearsInTheStudioLayerOnlyAsProse() throws {
        let dir = root().appendingPathComponent(Self.studioDir)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertFalse(names.isEmpty, "ANCHOR MISSING: \(Self.studioDir) listed no files.")
        var offenders: [String] = []
        for name in names where name.hasSuffix(".swift") {
            guard let text = try? String(contentsOf: dir.appendingPathComponent(name),
                                         encoding: .utf8) else { continue }
            for (index, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard line.contains("HealthKitBioPublisher") else { continue }
                if line.hasPrefix("//") || line.hasPrefix("///") || line.hasPrefix("*") { continue }
                offenders.append("\(name):\(index + 1)")
            }
        }
        XCTAssertTrue(offenders.isEmpty, """
            `HealthKitBioPublisher` is now referenced as CODE in the Studio layer at \
            \(offenders.joined(separator: ", ")). The ⛔ blocks on `stopBioSource` and \
            `selectBioSource` argue from its absence there — move the prose with the code.
            """)
    }

    // 3 — COUNTERWEIGHT. It is still started at APP level, which is the other half of "outside
    //     the picker's reach". If this moves, both doc blocks describe a layout that is gone.
    func testHealthKitIsStillStartedAtAppLevel() throws {
        let text = try source(Self.app)
        XCTAssertTrue(text.contains("healthBio.startIfAlreadyAuthorized(publishing: bus)"), """
            The app-level HealthKit start is gone from `EchoelmusicApp`. Both corrected doc \
            blocks name it as an APP-level publisher the picker does not own; if it moved, they \
            are wrong again in a new way.
            """)
    }

    // 4 — the corrected qualifier is present at BOTH doors. Stated positively on purpose: a
    //     negative scan for the old sentences would match the ⛔ blocks that retract them (#491).
    func testBothDoorsSayThePickerOwnsOnlyItsOwnSources() throws {
        let text = try source(Self.studio)
        for phrase in ["Stop every bio publisher THIS PICKER OWNS",
                       "Only one of the THREE SOURCES THIS PICKER OWNS"] {
            XCTAssertTrue(text.contains(phrase), """
                The doc summary "\(phrase)" is gone. Both doors previously claimed the bus had a \
                single writer, and three slices each paid a cycle rediscovering that it does not. \
                If the wording changes, keep the qualifier — or bring HealthKit under the picker \
                and make the old sentence true.
                """)
        }
    }
}
