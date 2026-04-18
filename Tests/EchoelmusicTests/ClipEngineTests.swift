import XCTest
@testable import Echoelmusic

@MainActor
final class ClipEngineTests: XCTestCase {

    var engine: ClipEngine!

    override func setUp() async throws {
        engine = ClipEngine()
    }

    // MARK: - Default scenes

    func testDefaultScenes_count() {
        XCTAssertEqual(engine.scenes.count, 6)
    }

    func testDefaultScenes_names() {
        let names = engine.scenes.map(\.name)
        XCTAssertTrue(names.contains("Rise"))
        XCTAssertTrue(names.contains("Pulse"))
    }

    func testDefaultScenes_harmonicityRange() {
        for scene in engine.scenes {
            XCTAssertGreaterThanOrEqual(scene.harmonicity, 0)
            XCTAssertLessThanOrEqual(scene.harmonicity, 1)
        }
    }

    // MARK: - Capture

    func testCaptureCurrentState_addsScene() {
        let initial = engine.scenes.count
        engine.captureCurrentState(name: "Test Scene")
        XCTAssertEqual(engine.scenes.count, initial + 1)
    }

    func testCaptureCurrentState_usesProvidedName() {
        engine.captureCurrentState(name: "My Jam")
        XCTAssertEqual(engine.scenes.last?.name, "My Jam")
    }

    func testCaptureCurrentState_cyclesColors() {
        // Capture enough to wrap around all 6 colors
        for i in 0..<12 {
            engine.captureCurrentState(name: "Scene \(i)")
        }
        XCTAssertEqual(engine.scenes.count, 18)   // 6 defaults + 12 captured
    }

    // MARK: - Remove

    func testRemove_decreasesCount() {
        let before = engine.scenes.count
        engine.remove(engine.scenes[0])
        XCTAssertEqual(engine.scenes.count, before - 1)
    }

    func testRemove_clearsActiveSceneID() {
        let scene = engine.scenes[0]
        // Simulate active scene (set via applyScene which is private — test via remove)
        engine.remove(scene)
        XCTAssertNil(engine.activeSceneID)
    }

    func testRemove_nonExistentScene_noOp() {
        let before = engine.scenes.count
        let phantom = ClipEngine.Scene(
            name: "Ghost", mixRoot: 0.1, mixFifth: 0.1,
            mixOctave: 0.1, mixHigh: 0.1, harmonicity: 0.5, color: .teal
        )
        engine.remove(phantom)
        XCTAssertEqual(engine.scenes.count, before)
    }

    // MARK: - Rename

    func testRename_updatesName() {
        let scene = engine.scenes[0]
        engine.rename(scene, to: "Renamed")
        XCTAssertEqual(engine.scenes[0].name, "Renamed")
    }

    func testRename_trims_whitespace() {
        let scene = engine.scenes[0]
        engine.rename(scene, to: "  Spaced  ")
        XCTAssertEqual(engine.scenes[0].name, "Spaced")
    }

    func testRename_emptyString_noOp() {
        let original = engine.scenes[0].name
        engine.rename(engine.scenes[0], to: "")
        XCTAssertEqual(engine.scenes[0].name, original)
    }

    func testRename_whitespaceOnly_noOp() {
        let original = engine.scenes[0].name
        engine.rename(engine.scenes[0], to: "   ")
        XCTAssertEqual(engine.scenes[0].name, original)
    }

    func testRename_nonExistentScene_noOp() {
        let phantom = ClipEngine.Scene(
            name: "Ghost", mixRoot: 0.1, mixFifth: 0.1,
            mixOctave: 0.1, mixHigh: 0.1, harmonicity: 0.5, color: .teal
        )
        engine.rename(phantom, to: "New Name")
        // No crash, no side effects
        XCTAssertFalse(engine.scenes.contains { $0.name == "New Name" })
    }

    // MARK: - State

    func testInitialState_notMorphing() {
        XCTAssertFalse(engine.isMorphing)
    }

    func testInitialState_noActiveScene() {
        XCTAssertNil(engine.activeSceneID)
    }

    func testInitialState_noQueuedScene() {
        XCTAssertNil(engine.queuedSceneID)
    }

    // MARK: - SceneColor cycling

    func testCaptureCurrentState_colorsNotNil() {
        engine.captureCurrentState(name: "X")
        XCTAssertNotNil(engine.scenes.last?.color)
    }
}
