// WorkspaceSurfaceTests.swift
// Echoel — locks the WorkspaceSurface persistence contract. The raw values are
// stored via @AppStorage("workspace.surface") and are ALSO written by
// ArrangementView's empty-state navigation ("compose", "clips") — renaming any
// of them silently breaks restored selections and that cross-surface nav.

#if canImport(SwiftUI)
import XCTest
@testable import Echoelmusic

final class WorkspaceSurfaceTests: XCTestCase {

    func testRawValues_areStable() {
        XCTAssertEqual(WorkspaceSurface.arrange.rawValue, "arrange")
        XCTAssertEqual(WorkspaceSurface.clips.rawValue, "clips")
        XCTAssertEqual(WorkspaceSurface.compose.rawValue, "compose")
        XCTAssertEqual(WorkspaceSurface.mix.rawValue, "mix")
    }

    func testUnknownStoredValue_fallsBackNil_soHostDefaultsToCompose() {
        // SurfaceHost/SurfaceSwitcherBar coalesce nil → .compose; an old or
        // foreign stored string must not crash or select a wrong surface.
        XCTAssertNil(WorkspaceSurface(rawValue: "bio"))
        XCTAssertNil(WorkspaceSurface(rawValue: ""))
    }

    func testInitialSurface_isStudio_untilArrangeIsReal() {
        // Plan Stage 2 flips this to .arrange once the timeline is usable —
        // this test documents (and gates) that decision explicitly.
        XCTAssertEqual(WorkspaceSurface.initial, .compose)
    }

    func testAllCases_orderIsTheChipOrder() {
        // The switcher renders allCases in order; Arrange leads (it becomes home).
        XCTAssertEqual(WorkspaceSurface.allCases,
                       [.arrange, .clips, .compose, .mix])
    }
}
#endif
