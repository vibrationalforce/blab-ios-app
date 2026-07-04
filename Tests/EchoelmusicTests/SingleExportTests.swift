#if canImport(AVFoundation)
import XCTest
@testable import Echoelmusic

@MainActor
final class SingleExportTests: XCTestCase {

    var exporter: SingleExport!

    override func setUp() async throws {
        exporter = SingleExport()
    }

    // MARK: - Initial state

    func testInitialState_idle() {
        guard case .idle = exporter.exportState else {
            XCTFail("Expected idle, got \(exporter.exportState)")
            return
        }
    }

    func testInitialState_defaultFormat_aac() {
        XCTAssertEqual(exporter.outputFormat, .aac)
    }

    func testInitialState_defaultTarget_streaming() {
        XCTAssertEqual(exporter.targetLUFS, -14)
    }

    // MARK: - OutputFormat

    func testOutputFormat_allCases_count() {
        XCTAssertEqual(SingleExport.OutputFormat.allCases.count, 2)
    }

    func testOutputFormat_wav_fileExtension() {
        XCTAssertEqual(SingleExport.OutputFormat.wav.fileExtension, "wav")
    }

    func testOutputFormat_aac_fileExtension() {
        XCTAssertEqual(SingleExport.OutputFormat.aac.fileExtension, "m4a")
    }

    func testOutputFormat_wav_avFileType() {
        XCTAssertEqual(SingleExport.OutputFormat.wav.avFileType, .wav)
    }

    func testOutputFormat_aac_avFileType() {
        XCTAssertEqual(SingleExport.OutputFormat.aac.avFileType, .m4a)
    }

    // MARK: - Reset

    func testReset_returnsToIdle() {
        exporter.reset()
        guard case .idle = exporter.exportState else {
            XCTFail("Expected idle after reset")
            return
        }
    }

    func testReset_clearsLoopTrimWindow() {
        // The trim window is per-export state (audit C6/C7) — a stale window from
        // a loop export must never silently truncate the NEXT caller's file.
        exporter.trimLengthSeconds = 8
        exporter.trimFromEndSeconds = 0.4
        exporter.edgeFadeSeconds = 0.004
        exporter.reset()
        XCTAssertNil(exporter.trimLengthSeconds)
        XCTAssertEqual(exporter.trimFromEndSeconds, 0)
        XCTAssertEqual(exporter.edgeFadeSeconds, 0)
    }

    // MARK: - Export with invalid URL

    func testExport_invalidURL_setsError() async {
        let badURL = URL(fileURLWithPath: "/nonexistent/path/file.caf")
        await exporter.export(sourceURL: badURL)
        guard case .error = exporter.exportState else {
            XCTFail("Expected error state for invalid URL, got \(exporter.exportState)")
            return
        }
    }

    // MARK: - ExportState helpers

    func testExportState_isDone_falseForIdle() {
        XCTAssertFalse(SingleExport.ExportState.idle.isDone)
    }

    func testExportState_isDone_trueForDone() {
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        XCTAssertTrue(SingleExport.ExportState.done(url).isDone)
    }

    func testExportState_exportedURL_nilForIdle() {
        XCTAssertNil(SingleExport.ExportState.idle.exportedURL)
    }

    func testExportState_exportedURL_returnsURL() {
        let url = URL(fileURLWithPath: "/tmp/test.m4a")
        XCTAssertEqual(SingleExport.ExportState.done(url).exportedURL, url)
    }
}
#endif
