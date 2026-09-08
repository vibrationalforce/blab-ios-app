// TheBreathFieldCarriesTwoQuantitiesTests.swift
// Echoel — `BioSampleFrame.breathPhase` is read as a LEVEL by some consumers and as a
// POSITION by others, and only one of those groups is correct today. BLOCKING bundle.
//
// #1146. Task #30 stood as "the camera writes a sine where the contract promises a sawtooth,
// so honour the contract". Measuring the CONSUMERS instead of the contract turned that around:
// converting the stored value would repair three readers and silently invert five, including
// the picture #1135 had just made correct and that the founder is being asked to confirm.
//
// ⛔ THIS GUARD FORBIDS NOTHING (#364). It does not require the sawtooth to stay unbuilt, and
// it does not require the detector to stay broken. It pins the MEASUREMENTS the decision rests
// on, so the day someone changes one of them the change is deliberate and the prose moves with
// it. Every claim message names the prose home: the `breathPhase` contract block in
// `Core/EngineBus.swift`.
//
// ⚠️ `Bio/BioEventGraph.swift` IS IN THE PROTECTED RAUSCH TRIAD — read-only without an explicit
// founder ask. This test READS it. Nothing here may be taken as licence to edit it.
//
// ⭐ THE MEASUREMENT THAT DECIDES IT, because it is arithmetic and not taste: the detector's
// exhale rule needs `previous > 0.8` and `phase < 0.2` in ONE sample. The camera's value is a
// normalised sine — it comes back down smoothly, ~0.2 per sample at ~1 Hz publishing on a 10 s
// breath — so that rule cannot fire. The inhale rule does fire, once per breath, at MID-inhale
// rather than at the onset its name promises.

import XCTest

final class TheBreathFieldCarriesTwoQuantitiesTests: XCTestCase {

    private static let graph = "Sources/Echoelmusic/Bio/BioEventGraph.swift"
    private static let bus = "Sources/Echoelmusic/Core/EngineBus.swift"
    private static let metal = "Sources/Echoelmusic/Views/MetalBioView.swift"
    private static let adm = "Sources/Echoelmusic/Sync/ADMOSCSender.swift"

    private func root() throws -> URL {
        let r = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: r.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(r.path)") }
        return r
    }

    private func raw(_ relativePath: String) throws -> String {
        let path = try root().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            XCTFail("ANCHOR MISSING: \(relativePath) could not be read — a missing anchor is a "
                    + "finding, not a pass.")
            return ""
        }
        return try String(contentsOf: path, encoding: .utf8)
    }

    /// 1 — the two detector rules are exactly the ones the finding was measured against.
    /// If either moves, the arithmetic in the contract block stops describing the code.
    func testTheBreathEventRulesAreTheOnesTheFindingMeasured() throws {
        let code = SourceText.codeOnly(try raw(Self.graph))
        XCTAssertTrue(code.contains("previous > 0.8, phase < 0.2"),
                      "The exhale rule moved. The 'can essentially never fire' arithmetic in "
                      + "the breathPhase contract block of Core/EngineBus.swift is derived from "
                      + "THIS threshold pair — re-derive it in the same commit.")
        XCTAssertTrue(code.contains("previous < 0.5, phase >= 0.5"),
                      "The inhale rule moved. The 'fires at MID-inhale, not at the onset its "
                      + "name promises' sentence in Core/EngineBus.swift is derived from THIS "
                      + "crossing — re-derive it in the same commit.")
    }

    /// 2 — the LEVEL side of the split is real and still reads the value as a level. The
    /// picture is the one that must not be inverted by a contract change.
    func testThePictureStillReadsItAsALevel() throws {
        let code = SourceText.codeOnly(try raw(Self.metal))
        XCTAssertTrue(code.contains("breath: bio.map { $0.breathPhaseForSound }"),
                      "The picture's breath read moved. It is the LEVEL reader named in the "
                      + "breathPhase contract block of Core/EngineBus.swift as the one a "
                      + "sawtooth conversion would invert — move that prose with it.")
    }

    /// 3 — the POSITION side is real too. Without a second reader group there is no split and
    /// the contract block is arguing with itself.
    func testTheSpatialSenderStillReadsItAsAPosition() throws {
        let code = SourceText.codeOnly(try raw(Self.adm))
        XCTAssertTrue(code.contains("(f.breathPhase * 2 - 1) * 180"),
                      "The ADM-OSC azimuth mapping moved. It is the POSITION reader named in "
                      + "the breathPhase contract block of Core/EngineBus.swift — if it no "
                      + "longer treats the field as a cycle position, the split may be gone "
                      + "and that block must say so.")
    }

    /// 4 — the finding lives where a session reads it BEFORE deciding to convert. A note only
    /// in a session log is a note nobody reads at the moment it matters (#456).
    func testTheContractNamesTheSplitAndTheRSADependency() throws {
        let text = try raw(Self.bus)
        XCTAssertTrue(text.contains("ONE FIELD, TWO PHYSICAL QUANTITIES"),
                      "The split note left the breathPhase contract. It is the only home a "
                      + "session reads before attempting the sawtooth conversion.")
        XCTAssertTrue(text.contains("BLOCKS RSA"),
                      "The RSA dependency left the breathPhase contract. DEAD-END #1132 names "
                      + "a smoothing constant; this field sits upstream of it, and without "
                      + "that sentence task #29 reads as merely deferred.")
    }
}
