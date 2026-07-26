// AppGroupStoreTests.swift
// Echoel — locks the load() contract that A4 (decode-failure telemetry) touched:
// an ABSENT file is a silent nil, a valid file round-trips, and a present-but-
// undecodable file returns nil (the catch path that now also logs) WITHOUT crashing.
// The log itself is a side-effect we don't assert; the behavioral contract is what
// must hold so a schema change can't turn a decode failure into a crash.

import XCTest
@testable import Echoelmusic

final class AppGroupStoreTests: XCTestCase {

    // Unique subdirectory per test run so cases don't collide on the shared container.
    private func store() -> AppGroupStore {
        AppGroupStore(subdirectory: "AppGroupStoreTests-\(UUID().uuidString)")
    }

    func testLoad_absentFile_returnsNilSilently() {
        let s = store()
        XCTAssertNil(s.load([Int].self, name: "never-saved"))
    }

    func testSaveLoad_validRoundTrip() {
        let s = store()
        let value = ["kick", "snare", "hat"]
        XCTAssertTrue(s.save(value, name: "pattern"))
        XCTAssertEqual(s.load([String].self, name: "pattern"), value)
        s.delete(name: "pattern")
    }

    func testLoad_presentButUndecodable_returnsNilNotCrash() {
        // Write one shape, read as an incompatible shape → decode throws → the catch
        // path logs (side-effect) and returns nil. This is the data-loss signal path.
        let s = store()
        XCTAssertTrue(s.save(["a", "b"], name: "mismatch"))     // a JSON array of strings
        XCTAssertNil(s.load(Int.self, name: "mismatch"))        // decoded as Int → fails → nil
        // The file is still there and still round-trips at its real type (we didn't nuke it).
        XCTAssertEqual(s.load([String].self, name: "mismatch"), ["a", "b"])
        s.delete(name: "mismatch")
    }

    // MARK: - loadLossyArray (the library-wipe fix)

    /// A small stand-in for a persisted library element: strict enough that a wrong-typed
    /// element really does fail to decode, which is what every arm below depends on.
    private struct Item: Codable, Equatable { let id: Int; let name: String }

    /// THE REGRESSION TEST. One corrupt element used to fail the WHOLE array decode, so
    /// `load` returned nil, the store fell back to empty, and the next save wrote that empty
    /// array back over the file — the user's entire library, gone for good.
    ///
    /// NOTE ON THE ASSERTION STYLE, because the first version of this file got it wrong: the
    /// result is `[Item?]?`, so an optional-chained `lossy?[1]` has type `Item??` and a real
    /// hole reads as `.some(.none)` — which `XCTAssertNil` FAILS, since it only sees the outer
    /// `.some`. Three assertions here could therefore never pass, and the two tests carrying
    /// the whole argument for this fix would have reported it broken. `XCTUnwrap` the array
    /// ONCE and index the plain `[Item?]`; then `nil` means what it reads as.
    func testLoadLossyArray_oneCorruptElement_keepsTheRest() throws {
        let s = store()
        // Hand-written JSON: three elements, the middle one missing a required field.
        let json = """
        [{"id":1,"name":"one"},{"id":2},{"id":3,"name":"three"}]
        """.data(using: .utf8)!
        XCTAssertTrue(s.saveRawForTests(json, name: "library"))

        // The old path: all-or-nothing. This assertion is what makes THIS test falsifiable —
        // if `loadLossyArray` were just an alias for `load`, the next one would return nil.
        XCTAssertNil(s.load([Item].self, name: "library"),
                     "precondition: the strict decode must fail on this file")

        let lossy = try XCTUnwrap(s.loadLossyArray(Item.self, name: "library"))
        XCTAssertEqual(lossy.count, 3, "every slot must be accounted for, holes included")
        XCTAssertEqual(lossy.compactMap { $0 },
                       [Item(id: 1, name: "one"), Item(id: 3, name: "three")],
                       "the two good elements must survive the one bad one")
        XCTAssertNil(lossy[1], "the corrupt element must be the hole, in its own position")
        s.delete(name: "library")
    }

    func testLoadLossyArray_wellFormedFile_isUnchangedAndOrdered() throws {
        // The common case must be untouched: same elements, same order, NO holes. Compare the
        // whole `[Item?]` rather than `.compactMap { $0 }` — compacting first would erase
        // exactly the no-holes property this test's name claims, and would pass against an
        // implementation that returned [nil, a, nil, b, nil, c].
        let s = store()
        let items = [Item(id: 1, name: "a"), Item(id: 2, name: "b"), Item(id: 3, name: "c")]
        XCTAssertTrue(s.save(items, name: "clean"))
        let loaded = try XCTUnwrap(s.loadLossyArray(Item.self, name: "clean"))
        XCTAssertEqual(loaded, items.map { Optional($0) },
                       "a well-formed file must come back element-for-element, no holes")
        s.delete(name: "clean")
    }

    func testLoadLossyArray_absentOrNotAnArray_returnsNil() {
        // nil must still mean "nothing usable is saved" — otherwise a caller cannot tell an
        // empty library from an unreadable one, and `?? []` would mask a real failure.
        let s = store()
        XCTAssertNil(s.loadLossyArray(Item.self, name: "never-saved"))
        XCTAssertTrue(s.save(Item(id: 1, name: "not-an-array"), name: "object"))
        XCTAssertNil(s.loadLossyArray(Item.self, name: "object"),
                     "a JSON object is not a partly-corrupt array — it is unreadable")
        s.delete(name: "object")
    }

    func testLoadLossyArray_everyElementCorrupt_isEmptyNotNil() throws {
        // The boundary between the two meanings: the file IS an array, so it is readable —
        // it just has nothing left in it. A caller must be able to tell this from "no file".
        let s = store()
        let json = "[{\"id\":1},{\"id\":2}]".data(using: .utf8)!
        XCTAssertTrue(s.saveRawForTests(json, name: "all-bad"))
        let lossy = try XCTUnwrap(s.loadLossyArray(Item.self, name: "all-bad"))
        XCTAssertEqual(lossy.count, 2)
        XCTAssertTrue(lossy.compactMap { $0 }.isEmpty)
        s.delete(name: "all-bad")
    }

    /// `ClipStore` is the one caller that must NOT compact its holes — the index is the slot.
    /// This pins that an optional element type survives the wrapper with its positions intact,
    /// which is what makes "one corrupt clip empties its own cell" true instead of "one
    /// corrupt clip shifts the grid and fails the count check, losing all eight".
    func testLoadLossyArray_optionalElements_keepPositions() throws {
        let s = store()
        let json = """
        [{"id":1,"name":"one"},null,{"id":9},{"id":4,"name":"four"}]
        """.data(using: .utf8)!
        XCTAssertTrue(s.saveRawForTests(json, name: "grid"))

        let slots = try XCTUnwrap(s.loadLossyArray(Item?.self, name: "grid")).map { $0 ?? nil }
        // Check the length BEFORE indexing: a compacting implementation returns 3 elements and
        // the `slots[3]` below would trap, taking the whole test bundle down instead of failing
        // this one test.
        guard slots.count == 4 else {
            return XCTFail("the grid lost its length (\(slots.count) ≠ 4) — positions shifted")
        }
        XCTAssertEqual(slots[0], Item(id: 1, name: "one"))
        XCTAssertNil(slots[1], "an explicit null stays an empty cell")
        XCTAssertNil(slots[2], "a corrupt element empties ITS cell")
        XCTAssertEqual(slots[3], Item(id: 4, name: "four"),
                       "the element AFTER the corrupt one must not shift into its place")
        s.delete(name: "grid")
    }

    func testDelete_removesFile() {
        let s = store()
        XCTAssertTrue(s.save(42, name: "answer"))
        XCTAssertEqual(s.load(Int.self, name: "answer"), 42)
        s.delete(name: "answer")
        XCTAssertNil(s.load(Int.self, name: "answer"))
    }
}
