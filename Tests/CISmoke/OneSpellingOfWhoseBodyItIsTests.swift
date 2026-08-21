// OneSpellingOfWhoseBodyItIsTests.swift
// Echoel — "is this a real body or the demo generator?" is ONE decision, so it gets ONE
// spelling. #677 finished the migration #639 started.
//
// WHY THIS EXISTS. `BioSource.isSynthetic` is literally `self == .fallback`, so every hand-
// written `source == .fallback` was BEHAVIOURALLY IDENTICAL and nothing was broken. That is
// exactly what made it dangerous: measured 2026-08-21, the comparison was spelled by hand at
// ELEVEN sites across EIGHT files, and among them were the OSC wire flag's sibling
// (`BioFeedbackPublisher`), the peer payload sent to other people's devices
// (`ColabPayload`), the "Simulated demo," prefix in the metric guide, the header monitors and
// the FX bio-modulation gate. The day `isSynthetic` gains a second case — a replay source, a
// second simulator, a demo strap — every one of those keeps quietly answering "real body"
// while the property that defines the question says otherwise. A false "real" is the exact
// claim #639 existed to stop the app making.
//
// ⚠️ HONEST LIMITS. 3 test methods, 5 `XCTAssert*` — re-derive both, do not re-type:
//   grep -c "^    func test" <this file>
//   grep -n "XCTAssert" <this file> | grep -vc ':[[:space:]]*//'
// Claim 1 is a repo-wide SOURCE-TEXT scan; claims 2–3 are EXECUTED BEHAVIOUR on the enum.
// What NO test here can prove: that every CALLER wanted "synthetic" rather than ".fallback
// specifically". Today the two are the same set, so no caller can tell. Claim 1's message
// carries the instruction for the first caller that genuinely needs the narrower question.

import XCTest
@testable import Echoelmusic

final class OneSpellingOfWhoseBodyItIsTests: XCTestCase {

    /// The ONE LINE allowed to compare against the case: the body of the predicate itself.
    ///
    /// ⛔ #678 (review): the first version exempted the whole FILE, all 784 lines of
    /// `EngineBus.swift` — so any future `frame.source == .fallback` written anywhere in it was
    /// invisible. Worse, the exemption was a raw PATH: moving `BioSource` or splitting the file
    /// would make claim 1 fire on the definition of `isSynthetic` itself, telling the author to
    /// "ask `BioSource.isSynthetic`" inside the body of `BioSource.isSynthetic`. A line is both
    /// narrower and portable.
    private static let definitionLine = "public var isSynthetic: Bool { self == .fallback }"

    /// Every spelling of the same comparison, not just the one that happened to be in the tree.
    ///
    /// ⛔ #678 (review): the first version matched `== .fallback` and `!= .fallback` only —
    /// one space, short form, our operand order. `== BioSource.fallback` (the natural
    /// disambiguating form the day a second synthetic case exists), `==.fallback` and the
    /// reversed `.fallback == frame.source` all sailed past a guard whose whole purpose is that
    /// day. Zero occurrences of any of them today, so this closes a latent hole, not a live one.
    /// ⚠️ Still NOT matched, deliberately: `switch` / `if case`, the documented escape for a
    /// caller that needs the narrow question; and a comparison split across a continuation line,
    /// which this line-local scan cannot see. Both are stated rather than pretended away.
    private static let spellings = ["== .fallback", "!= .fallback", "==.fallback", "!=.fallback",
                                    "== BioSource.fallback", "!= BioSource.fallback",
                                    ".fallback ==", ".fallback !="]

    // MARK: - 1. The comparison is written once, where the predicate lives

    func testNothingSpellsTheSyntheticTestByHand() throws {
        var offenders: [String] = []
        var sawDefinition = false
        for (path, code) in try Self.allSourceText() {
            for (number, line) in code.split(separator: Character("\n"),
                                             omittingEmptySubsequences: false).enumerated() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == Self.definitionLine { sawDefinition = true; continue }
                guard Self.spellings.contains(where: { trimmed.contains($0) }) else { continue }
                offenders.append("\(path):\(number + 1): \(trimmed)")
            }
        }
        // ⚠️ #454: without this the negative is vacuous the moment the predicate is renamed or
        // reformatted — the exemption stops matching, nothing is exempt, and a repo with ZERO
        // offenders still reports zero. The guard would then be measuring an empty question.
        XCTAssertTrue(sawDefinition, """
            The exempted definition line was not found in `Sources/`. Expected exactly:
              \(Self.definitionLine)
            Either `isSynthetic` was renamed, reformatted or moved — in which case update this \
            line and re-run — or it is gone, in which case every honesty surface in the app and \
            the `/echoelmusic/bio/synthetic` wire flag have lost the property they all read.
            """)
        XCTAssertEqual(offenders, [], """
            "Is this a real body?" is spelled by hand at \(offenders.count) site(s) instead of \
            asking `BioSource.isSynthetic`:
            \(offenders.joined(separator: "\n"))
            These are behaviourally identical TODAY — `isSynthetic` is `self == .fallback` — \
            which is what makes them dangerous rather than harmless. The day a second \
            synthetic case exists, each one keeps answering "real body" while the predicate \
            that defines the question does not. Among the eleven this guard was written to \
            close were the peer payload sent to other people's devices, the "Simulated demo," \
            prefix in the metric guide and the FX bio-modulation gate.
            ⚠️ IF YOU GENUINELY NEED `.fallback` SPECIFICALLY — the narrower question, not \
            "any synthetic source" — that is legitimate and this guard is not here to forbid \
            it (#364). Use a `switch` or `if case`, which this scan does not match, and say in \
            a comment at the site why the narrow question is the right one.
            """)
    }

    // MARK: - 2. The predicate still names the demo generator

    func testTheDemoGeneratorIsSynthetic() {
        XCTAssertTrue(BioSource.fallback.isSynthetic, """
            `.fallback` — the deterministic demo generator — no longer reports as synthetic. \
            Every honesty surface in the app and the `/echoelmusic/bio/synthetic` wire flag \
            read this one property, so this single `false` would make the app claim a real \
            body across every screen at once.
            """)
    }

    // MARK: - 3. The predicate discriminates

    func testARealSensorIsNotSynthetic() {
        // ⚠️ Two cases, not all of them. Asserting that EVERY non-fallback case is real would
        // forbid ever adding a second synthetic source — a guard that blocks correct future
        // work (#364). These two are sensors on a body by definition and can never become
        // synthetic, so pinning them costs no future freedom.
        XCTAssertFalse(BioSource.cameraPPG.isSynthetic, """
            The camera rPPG source reports as synthetic. It is a finger on a real lens; \
            calling it a demo would put "Simulated demo," on the app's most-used bio path.
            """)
        XCTAssertFalse(BioSource.ble.isSynthetic, """
            The BLE chest strap reports as synthetic. It is an electrode on a real chest.
            """)
        // ⛔ #678 (review): a third assertion stood here — `XCTAssertNotEqual(fallback,
        // cameraPPG)` — and it is strictly implied by the `true` above and the `false` beside
        // it. It cannot fail unless one of them already has, so it carried no information and
        // still cost a line in the header count. Removed rather than kept for symmetry.
    }

    // MARK: - Helpers

    /// Every `.swift` file under `Sources/`, comment-stripped, keyed by repo-relative path.
    ///
    /// ⚠️ Comment-stripped MATTERS here more than usual: this repo's ⛔ blocks deliberately
    /// QUOTE the retracted spelling — `EngineBus.swift` and `EchoelFXView.swift` both explain
    /// in prose why `== .fallback` was equal to the predicate. A raw scan would flag its own
    /// documentation (#491).
    private static func allSourceText() throws -> [(String, String)] {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            dir.deleteLastPathComponent()
            let sources = dir.appendingPathComponent("Sources")
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: sources.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            guard let walk = FileManager.default.enumerator(at: sources,
                                                            includingPropertiesForKeys: nil) else {
                break
            }
            var out: [(String, String)] = []
            let prefix = dir.path.hasSuffix("/") ? dir.path : dir.path + "/"
            for case let url as URL in walk where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                let relative = url.path.hasPrefix(prefix)
                    ? String(url.path.dropFirst(prefix.count)) : url.path
                out.append((relative, SourceText.codeOnly(text)))
            }
            guard !out.isEmpty else { break }
            return out
        }
        throw NSError(domain: "OneSpellingOfWhoseBodyItIsTests", code: 1, userInfo:
                        [NSLocalizedDescriptionKey:
                          "cannot walk Sources/ from #filePath — re-anchor (#454)."])
    }
}
