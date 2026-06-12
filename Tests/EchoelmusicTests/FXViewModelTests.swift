// FXViewModelTests.swift
// Echoel — the FX tool's write-through view-model. Verifies the new Filter
// mirrors and the one-tap production-character stamp (Underwater, …) drive the
// live chain and resynchronise the UI mirrors.

#if canImport(SwiftUI)
import XCTest
@testable import Echoelmusic

@MainActor
final class FXViewModelTests: XCTestCase {

    private func makeVM() -> FXViewModel {
        FXViewModel(voice: BioReactiveSynthVoice(), bpm: 120)
    }

    func testStampingUnderwaterDrivesChainAndMirrors() {
        let vm = makeVM()
        vm.applyCharacter(.underwater)

        // Master + mirrors reflect the stamp.
        XCTAssertTrue(vm.fxEnabled, "stamping a character turns the insert on")
        XCTAssertTrue(vm.filterEnabled)
        XCTAssertEqual(vm.filterMode, .lowpass)
        XCTAssertLessThanOrEqual(vm.filterCutoff, 1000, "underwater is muffled")
        XCTAssertTrue(vm.delayEnabled)
        XCTAssertEqual(vm.delayMode, .tape)
    }

    func testFilterMirrorWritesThroughToChain() {
        let vm = makeVM()
        vm.filterCutoff = 1200            // default is 20000
        vm.filterResonance = 0.5
        vm.filterMode = .bandpass
        // reseed re-reads from the live chain; the values survive only if the
        // mirror's didSet actually wrote them through.
        vm.reseed()
        XCTAssertEqual(vm.filterCutoff, 1200)
        XCTAssertEqual(vm.filterResonance, 0.5)
        XCTAssertEqual(vm.filterMode, .bandpass)
    }

    func testReStampingClearsAStaleFilter() {
        let vm = makeVM()
        vm.applyCharacter(.underwater)
        XCTAssertTrue(vm.filterEnabled)
        // Dream has no filter — the stale flag must clear after a re-stamp.
        vm.applyCharacter(.dream)
        XCTAssertFalse(vm.filterEnabled, "apply is a full state write")
        XCTAssertTrue(vm.delayEnabled, "dream still has its wide delay")
    }
}
#endif
