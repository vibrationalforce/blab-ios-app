// FXSpreadRowTests.swift
// Echoel — #251: a parameter that every preset carries but no user can reach is not a parameter,
// it is a side effect. BLOCKING bundle, because the other suite cannot fail a merge (#208).
//
// WHAT WENT WRONG. #246 made `delaySpread` round-trip through `FXPreset` — capture, decode,
// apply, morph — and `GenreFXPreset.apply` has been writing it since long before that. So the
// stereo image of the delay changed under the user on every genre change, every character stamp,
// every preset load and every drag of the macro-morph fader. `EchoelFXView` had rows for the
// other seven delay fields and none for this one. That is worse than a missing feature: the
// value moves, the sound moves with it, and nothing on screen accounts for the difference.
//
// ⚠️ WHAT THIS FILE CAN AND CANNOT SEE — and the first draft got this wrong in the direction
// that mattered. It admitted the ROW "cannot be reached from a test" and asserted only the
// MIRROR. But the mirror and the row are INDEPENDENTLY deletable, and every mirror assertion
// below survives deleting `field("Spread", $vm.delaySpread, 0...1)` — the row was precisely the
// half nothing guarded. The technique was already in this bundle: `HarmonyIntervalTests` reads
// `EchoelFXView.swift` as source text and asserts the contents of an `effectSection` block. So
// the last test here does the same. What still cannot be proven from here is that the row
// RENDERS, that VoiceOver reaches it, or that dragging it feels right — the device check is that
// "Spread" appears under Tone and visibly widens the echo.

#if canImport(SwiftUI)
import Foundation
import XCTest
@testable import Echoelmusic

@MainActor
final class FXSpreadRowTests: XCTestCase {

    private func makeVM() -> (FXViewModel, EchoelFXChain) {
        let chain = EchoelFXChain()
        let vm = FXViewModel(chain: chain, bpm: 120,
                             masterEnabled: { false },
                             setMasterEnabled: { _ in })
        return (vm, chain)
    }

    /// ⛔ THE ASSERTION THE SLICE EXISTS FOR: moving the row moves the audio. Before this, the
    /// view model had no `delaySpread` at all, so there was nothing a row could have been bound
    /// to — the missing piece was never just the row.
    func testTheRowWritesThroughToTheDelayStage() {
        let (vm, chain) = makeVM()
        vm.delaySpread = 0.7
        XCTAssertEqual(chain.delay.spread, 0.7, accuracy: 1e-6,
                       "the mirror did not reach the stage — the row would be inert, which is "
                       + "the defect class this slice removes, not the one it introduces")
    }

    /// And the row must SHOW what the chain already holds, or it lies in the other direction:
    /// a genre stamp sets 0.55 and the row would read 0 until touched.
    func testTheRowSeedsFromWhateverTheChainAlreadyHolds() {
        let chain = EchoelFXChain()
        chain.delay.spread = 0.45
        let vm = FXViewModel(chain: chain, bpm: 120,
                             masterEnabled: { false }, setMasterEnabled: { _ in })
        XCTAssertEqual(vm.delaySpread, 0.45, accuracy: 1e-6,
                       "the row opened at a value the chain was not playing")
    }

    /// ⭐ THE PATH THAT MADE THIS VISIBLE IN THE FIRST PLACE. A character stamp, a preset load
    /// and the morph fader all end in `reseed()`, which re-reads every mirror from the chain.
    /// If `delaySpread` is missing from that list, the row freezes at its old value while the
    /// sound moves — the same "control that does not match what is playing" this slice is
    /// closing, just relocated.
    func testAStampedCharacterMovesTheRowWithIt() {
        let (vm, chain) = makeVM()
        vm.delaySpread = 0.0
        // Write the chain behind the view model's back, exactly as a stamp or preset apply does.
        chain.delay.spread = 0.62
        vm.reseed()
        XCTAssertEqual(vm.delaySpread, 0.62, accuracy: 1e-6,
                       "reseed() did not refresh the spread — the row would keep showing 0 "
                       + "while the delay played a 15 ms wide image")
    }

    /// Both ends of the range the row offers must actually arrive at the stage — a mirror that
    /// wrote through only in the middle would leave the fader's extremes inert.
    ///
    /// ⚠️ RENAMED, because the first name (`testTheStageClampsToTheDomainTheRowOffers`) promised
    /// something these lines cannot see: `spread` is a plain stored property and clamps nowhere
    /// on this path — the clamp is a local inside `processStereo`, so only audio can observe it.
    /// That IS asserted, through the audio, in
    /// `FXPresetDelaySpreadTests.testAnAbsurdSpreadCannotPushTheRightTapOutOfItsDeclaredRange`.
    func testBothEndsOfTheRowsRangeReachTheStage() {
        let (vm, chain) = makeVM()
        vm.delaySpread = 1.0
        XCTAssertEqual(chain.delay.spread, 1.0, accuracy: 1e-6,
                       "the top of the row's range must be reachable, or the row is short")
        vm.delaySpread = 0.0
        XCTAssertEqual(chain.delay.spread, 0.0, accuracy: 1e-6,
                       "and 0 must mean a centred echo, which is the stage's own default")
    }

    // MARK: - The row itself

    /// ⛔ THE HALF NOTHING ELSE GUARDS. Every assertion above passes with the row deleted: they
    /// test the mirror, and the mirror is what the row is bound TO, not the row. Source text
    /// because the Delay section is a `@ViewBuilder` block inside a `private` SwiftUI `View` with
    /// no seam to call and no local toolchain to host it — the same reason `HarmonyIntervalTests`
    /// and `CleanIsDryTests` read source. It proves the binding is present in the Delay section,
    /// not that it renders.
    func testTheDelaySectionActuallyCarriesTheSpreadRow() throws {
        let block = try blockBody(after: "effectSection(\"Delay\"",
                                  in: "Sources/Echoelmusic/Studio/EchoelFXView.swift")
        XCTAssertTrue(block.contains("field(\"Spread\", $vm.delaySpread"),
                      "the Delay section has no Spread row — every other test in this file still "
                      + "passes in that state, which is exactly why this one exists:\n\(block)")
    }

    // MARK: - Reading the source

    /// The lines from the one containing `marker` to its matching closing brace, whole-line
    /// comments dropped BEFORE the brace arithmetic so a comment quoting an unbalanced brace
    /// cannot desync the depth. Throws rather than returning empty on a miss: an empty block
    /// would make the assertion above pass vacuously. (Same helper as `HarmonyIntervalTests`;
    /// duplicated rather than shared because both are `private` in a bundle with no test-support
    /// target, and a two-file copy is cheaper than inventing one for it.)
    private func blockBody(after marker: String, in relativePath: String) throws -> String {
        let url = try repoRoot().appendingPathComponent(relativePath)
        let text = try String(contentsOf: url, encoding: .utf8)
        let lines = text.components(separatedBy: .newlines)
        let matches = lines.indices.filter { lines[$0].contains(marker) }
        guard let start = matches.first else {
            XCTFail("Marker not found: \(marker) in \(relativePath) — it was renamed or moved. "
                    + "Re-point this test rather than deleting it.")
            throw CocoaError(.fileNoSuchFile)
        }
        XCTAssertEqual(matches.count, 1,
                       "Marker `\(marker)` appears \(matches.count) times; this scan reads only "
                       + "the first, so the guard may be pointing at the wrong one.")
        var depth = 0
        var collected: [String] = []
        for line in lines[start...] {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            collected.append(line)
            depth += line.filter { $0 == "{" }.count
            depth -= line.filter { $0 == "}" }.count
            if depth == 0 && collected.count > 1 { break }
        }
        return collected.joined(separator: "\n")
    }

    /// `#filePath` is inside `Tests/CISmoke/`, so the repo root is three directories up. A
    /// source-reading test that cannot find the source must SKIP, not pass.
    private func repoRoot() throws -> URL {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CISmoke
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo
        guard FileManager.default.fileExists(atPath:
                root.appendingPathComponent("Sources/Echoelmusic").path) else {
            throw XCTSkip("source tree not present — this test inspects source text, so it "
                          + "SKIPS rather than reporting a green it did not earn")
        }
        return root
    }
}
#endif
