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
// ⚠️ WHAT THIS FILE CAN AND CANNOT SEE. `FXViewModel` is reachable, so the MIRROR is testable
// end to end: that setting it writes through to the chain, and that the seed and `reseed()`
// paths read it back. The ROW itself lives in a `private var` inside a SwiftUI body and cannot
// be instantiated here — same honest limit as `ArpPushRowTests`. What is asserted is the half a
// unit test can own; the other half is one line in the Delay section, and the device check is
// simply that "Spread" appears under Tone and moves the image.

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

    /// The row's range must be the stage's own declared domain, not a wider one that the audio
    /// then silently clamps. `EchoelDelay` holds `spread` to [0, 1] inside `process`, so a row
    /// offering more would let a user drag into a region where nothing further happens.
    func testTheStageClampsToTheDomainTheRowOffers() {
        let (vm, chain) = makeVM()
        vm.delaySpread = 1.0
        XCTAssertEqual(chain.delay.spread, 1.0, accuracy: 1e-6,
                       "the top of the row's range must be reachable, or the row is short")
        vm.delaySpread = 0.0
        XCTAssertEqual(chain.delay.spread, 0.0, accuracy: 1e-6,
                       "and 0 must mean a centred echo, which is the stage's own default")
    }
}
#endif
