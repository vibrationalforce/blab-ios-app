import XCTest
@testable import Echoelmusic

/// #1066 — the floating window's size key is written once, not six times.
///
/// WHY IT EXISTS. `"visual.floating.size"` was a raw string at SIX sites: `WorkspaceView`,
/// `FloatingVisualWindow`, and four in `EchoelStudioView`'s take-recording path — where the
/// comment directly above two of them already claimed the opposite, that these programmatic
/// reads go "via the namespace (H15-KEYSTORE)". The sibling key on the very next line does; this
/// one did not, because it had no constant to go through.
///
/// It stopped being survivable because S3b of PLAN_ONE_VISUAL_SURFACE_2026-09-07 adds a SEVENTH
/// SITE: the Field panel's "Full screen" button, which after that slice writes the window size
/// instead of raising the fullscreen cover. (Sites, not readers — three FILES read the value; the
/// six literals were spread across them.) A rename would have moved some of seven and left the
/// rest, which is the failure mode `TheDonutLookSurvivesTheCoverTests` was written to prevent one
/// slice earlier.
///
/// ⚠️ THE DEFAULT IS DELIBERATELY NOT PROMOTED WITH THE KEY. Every other entry in
/// `StudioDefaultKeys` carries both; this one carries only the key, because the honest default is
/// `FloatingVisualWindow.WindowSize.small.rawValue` and that enum sits behind a platform guard
/// `Core/` cannot follow. A bare `0` in `Core/` would decouple the default from the enum —
/// precisely what `WorkspaceView`'s own doc argues against. Claim 2 pins that asymmetry so a
/// later tidy-up does not "finish the job" and reintroduce the drift.
final class TheWindowSizeKeyHasOneHomeTests: XCTestCase {

    private func swiftFiles() throws -> [(path: String, text: String)] {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let root = dir.appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(atPath: root.path) else {
            XCTFail("ANCHOR MISSING: Sources/ could not be walked — a missing anchor is a "
                    + "finding, not a pass.")
            return []
        }
        var out: [(String, String)] = []
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            let url = root.appendingPathComponent(rel)
            if let text = try? String(contentsOf: url, encoding: .utf8) { out.append((rel, text)) }
        }
        XCTAssertFalse(out.isEmpty, "No Swift files found under Sources/ — re-anchor this case.")
        return out
    }

    // 1 — the literal appears exactly once in the whole of Sources/, at its declaration.
    // Counted through `codeOnly` so a comment quoting the key (this repo writes many) is not
    // mistaken for a second site — the #1050 lesson, applied before it could bite again.
    func testTheKeyStringAppearsOnlyAtItsDeclaration() throws {
        var sites: [String] = []
        for (path, text) in try swiftFiles() {
            let code = SourceText.codeOnly(text)
            let hits = code.components(separatedBy: "\"visual.floating.size\"").count - 1
            if hits > 0 { sites.append("\(path) ×\(hits)") }
        }
        XCTAssertEqual(sites, ["Echoelmusic/Core/StudioDefaultKeys.swift ×1"], """
            The window-size key is spelled as a raw string somewhere other than its one \
            declaration: \(sites.isEmpty ? "nowhere at all" : sites.joined(separator: " · ")).

            MORE sites is the drift this slice removed — six literals under a comment that \
            claimed one namespace. Route the reader through \
            `StudioDefaultKeys.floatingVisualSizeKey` instead.

            NO sites at all means the declaration itself moved or was renamed; re-anchor this \
            case in the same commit rather than deleting it.
            """)
    }

    // 2 — the key has a constant AND its readers use it. Without this half, claim 1 would pass
    // over a tree where every reader was deleted along with the feature.
    func testEveryReaderGoesThroughTheConstant() throws {
        var readers: [String] = []
        for (path, text) in try swiftFiles() where path != "Echoelmusic/Core/StudioDefaultKeys.swift" {
            if SourceText.codeOnly(text).contains("StudioDefaultKeys.floatingVisualSizeKey") {
                readers.append(path)
            }
        }
        XCTAssertGreaterThanOrEqual(readers.count, 3, """
            Only \(readers.count) file(s) read the window-size key through the constant: \
            \(readers.isEmpty ? "none" : readers.joined(separator: " · ")). Three surfaces own \
            this value — the workspace seed, the window itself, and the studio's take path — so \
            fewer means a reader was dropped rather than migrated.
            """)

        // COUNTERWEIGHT (#367): the asymmetry is intended. If someone promotes a DEFAULT into
        // `Core/` for this key, this goes red and the header above says why that is wrong.
        let keys = try swiftFiles().first { $0.path == "Echoelmusic/Core/StudioDefaultKeys.swift" }
        XCTAssertNotNil(keys, "StudioDefaultKeys.swift is gone — re-anchor this case.")
        let keysCode = SourceText.codeOnly(keys?.text ?? "")
        XCTAssertTrue(keysCode.contains("floatingVisualSizeKey = \"visual.floating.size\""), """
            The key is no longer a bare `String` constant. If it became a `StudioDefault` with a \
            value, that value cannot be `WindowSize.small.rawValue` (the enum is behind a \
            platform guard `Core/` cannot import), so it would be a literal `0` that drifts the \
            moment the enum is reordered — the exact coupling `WorkspaceView`'s doc protects.
            """)
    }
}
