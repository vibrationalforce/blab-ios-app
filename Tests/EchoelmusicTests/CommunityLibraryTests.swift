// CommunityLibraryTests.swift
// Echoel — verifies the bundled community library loads + merges. This also
// proves the SwiftPM resource bundling of Resources/Community/ (if the subdir
// were flattened, these fail in CI rather than silently no-opping on device).

import XCTest
@testable import Echoelmusic

final class CommunityLibraryTests: XCTestCase {

    func testBundledFXCommunity_loadsSeededExample() {
        XCTAssertTrue(CommunityLibrary.fx.contains { $0.name == "Aurora Drift" },
                      "seeded Resources/Community/fx/aurora-drift.json should bundle + decode")
    }

    func testCuratedCommunity_includesBundledCommunity() {
        XCTAssertTrue(FXPreset.curatedCommunity.contains { $0.name == "Aurora Drift" },
                      "curatedCommunity should append CommunityLibrary.fx")
    }

    func testPatchesCommunity_neverCrashes() {
        // No seeded patches yet — must be a safe empty list, not a crash.
        XCTAssertNotNil(CommunityLibrary.patches)
    }

    /// TEMPORARY DIAGNOSTIC (#78, 2026-07-21) — two project.yml fixes for
    /// testBundledFXCommunity_loadsSeededExample above (a dedicated `type: folder`
    /// resource entry, then excluding Community/Drums/Samples from the generic
    /// `sources: type: group` walk to remove a suspected double-declaration) both
    /// had ZERO effect in CI. Rather than guess a third time, dump ground truth:
    /// is `Bundle.main` really the app bundle here, and where did the seeded JSON
    /// actually land (if anywhere)? Remove this test once the real cause is fixed.
    func testDiagnostic_dumpBundleContents() {
        let bundle = Bundle.main
        var report = "Bundle.main.bundlePath = \(bundle.bundlePath)\n"
        report += "Bundle.main.bundleURL = \(bundle.bundleURL)\n"
        if let resourceURL = bundle.resourceURL {
            report += "resourceURL = \(resourceURL)\n"
            let fm = FileManager.default
            if let enumerator = fm.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
                var lines: [String] = []
                for case let url as URL in enumerator {
                    let rel = url.path.replacingOccurrences(of: resourceURL.path, with: "")
                    if rel.lowercased().contains("community") || rel.lowercased().contains("aurora")
                        || rel.hasSuffix(".json") {
                        lines.append(rel)
                    }
                }
                report += "matching entries under resourceURL (community/aurora/*.json):\n"
                report += lines.sorted().joined(separator: "\n")
                if lines.isEmpty { report += "(none found)" }
            } else {
                report += "could not enumerate resourceURL"
            }
        } else {
            report += "resourceURL = nil"
        }
        XCTFail(report)
    }
}
