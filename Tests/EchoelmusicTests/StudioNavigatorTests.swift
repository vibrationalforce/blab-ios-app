// StudioNavigatorTests.swift
// Echoel — shared Studio tab selection (code-driven navigation).

#if canImport(Observation)
import XCTest
@testable import Echoelmusic

@MainActor
final class StudioNavigatorTests: XCTestCase {

    func testDefaultsToTools() {
        XCTAssertEqual(StudioNavigator().selected, .tools)
    }

    func testEditInToolsReturnsFromAnyTab() {
        let nav = StudioNavigator()
        nav.selected = .clips
        nav.editInTools()
        XCTAssertEqual(nav.selected, .tools, "Edit clip lands the user in the Tools editor")
    }

    func testSelectionIsSettable() {
        let nav = StudioNavigator()
        nav.selected = .well
        XCTAssertEqual(nav.selected, .well)
    }
}
#endif
