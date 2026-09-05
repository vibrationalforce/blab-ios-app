import XCTest
@testable import Echoelmusic

/// #1007 — the colour default says one number in every place that carries it.
///
/// WHY IT EXISTS, and it is really about audit item 25 rather than about colour. The founder
/// asked for "Bunter" on 2026-08-13; #578 raised the saturation default from 0.82 to 1.05 in
/// the three places that carry it, and left `StudioDefaultKeysTests` pinning 0.82. That test
/// then failed for three weeks and NOBODY SAW A RED — `full-tests.yml` carries
/// `continue-on-error` on its build step, so the suite reported success with failures inside
/// it. The stale assertion was invisible by construction.
///
/// So the repair is not "fix the number", which one edit does. It is to move the invariant
/// into the BLOCKING bundle, where a red is a red.
///
/// ⭐ IT PINS NO LITERAL, DELIBERATELY (#364). The number is a founder decision about how the
/// picture looks and may change again tomorrow. What must hold is AGREEMENT: the keystore
/// default, both `MetalBioView` struct defaults, and the assertion in the non-blocking suite
/// all state the SAME value. A founder who changes it changes it in four places and this stays
/// green; a session that changes it in one goes red immediately.
///
/// ⚠️ WHY THE STRUCT DEFAULTS MATTER AT ALL, since every production call site passes the value
/// explicitly: #578's own note records that the first version of that change moved two struct
/// defaults, transcribed a guard over them, and only a wider grep found the copy the GPU
/// actually reads. A guard over the struct defaults alone would have been green while the
/// picture stayed exactly as grey as before. Agreement across all of them is the property that
/// cannot be satisfied by editing the wrong one.
///
/// ⚠️ HONEST GRADING, written after transcribing rather than guessed. Three claims. 1 and 2
/// are green on the worktree AND on `HEAD` — the SOURCE has agreed with itself since #578; it
/// was only the test that lagged, which is exactly why nothing blocking ever noticed. Claim 3
/// is the load-bearing one: red on `HEAD`, where `StudioDefaultKeysTests` still says 0.82.
///
/// A fourth claim was drafted and deleted before committing; the ⛔ block below it says why,
/// and it is worth reading before adding one back.
final class TheSaturationDefaultAgreesEverywhereTests: XCTestCase {

    private static let keystore = "Sources/Echoelmusic/Core/StudioDefaultKeys.swift"
    private static let metal = "Sources/Echoelmusic/Views/MetalBioView.swift"
    private static let suite = "Tests/EchoelmusicTests/StudioDefaultKeysTests.swift"

    private func source(_ relative: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { break }
            dir = dir.deletingLastPathComponent()
        }
        let url = dir.appendingPathComponent(relative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(relative) could not be read — a missing anchor is a "
                    + "finding, not a pass.")
            return ""
        }
        return text
    }

    /// Every number that follows `needle` on its own line, as written.
    private func numbers(after needle: String, in text: String) -> [String] {
        text.components(separatedBy: "\n")
            .filter { $0.contains(needle) && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
                      && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///") }
            .compactMap { line in
                guard let eq = line.range(of: needle) else { return nil }
                let tail = line[eq.upperBound...]
                let digits = tail.prefix { $0.isNumber || $0 == "." }
                return digits.isEmpty ? nil : String(digits)
            }
    }

    // 1 — the keystore states exactly one value.
    func testTheKeystoreStatesOneSaturationDefault() throws {
        let found = numbers(after: "visualSaturation = StudioDefault(key: \"visual.saturation\", value: ",
                            in: try source(Self.keystore))
        XCTAssertEqual(found.count, 1, """
            Expected exactly one keystore declaration of the saturation default, found \
            \(found.count): \(found). The keystore exists so this number has ONE home; two \
            declarations mean the H15-KEYSTORE rule has already been broken here.
            """)
    }

    // 2 — LOAD-BEARING for the invariant: the GPU-side struct defaults agree with it.
    func testTheRendererDefaultsAgreeWithTheKeystore() throws {
        let key = numbers(after: "visualSaturation = StudioDefault(key: \"visual.saturation\", value: ",
                          in: try source(Self.keystore)).first
        let metal = numbers(after: "var saturation: Float = ", in: try source(Self.metal))
        guard let key else { return XCTFail("could not read the keystore default — re-anchor.") }
        XCTAssertFalse(metal.isEmpty, """
            No `var saturation: Float = …` remains in \(Self.metal). If the struct defaults \
            were removed that may be fine, but this claim is then measuring nothing — re-anchor \
            it rather than letting it pass on an empty set (#454).
            """)
        for value in metal {
            XCTAssertEqual(value, key, """
                A renderer default says \(value) while the keystore says \(key). #578 recorded \
                exactly this trap: its first version moved two struct defaults, guarded them, \
                and only a wider grep found the copy the GPU reads — a guard over the wrong \
                copy is green while the picture never changes.
                """)
        }
    }

    // ⛔ A THIRD CLAIM STOOD HERE AND WAS DELETED BEFORE COMMITTING, because it could not be
    // written correctly. Its job was to stop THIS file from growing a literal pin on the
    // saturation value, by scanning itself for `XCTAssertEqual(StudioDefaultKeys.visual…`.
    // That needle appears in this file by necessity — claim 3 below passes it to
    // `numbers(after:)` to do its work — so the claim failed on a correct file. Splitting the
    // literal did not save it either, for the same reason: the string still has to exist
    // somewhere in here.
    //
    // This is the #491 shape a SECOND time in one session (the first was #1001's roster
    // guard, which survived only by allowing the struck phrase on a line marked STRUCK): a
    // negative scan whose own subject
    // matter contains the thing it forbids. The rule survives in the header instead, where it
    // is read by whoever edits this file — which is the only audience it ever had. A rule that
    // cannot be made executable is still a rule; a guard that is red on a correct tree is not.

    // 3 — LOAD-BEARING: the silent suite's assertion agrees too.
    func testTheNonBlockingSuiteAgreesWithTheShippedValue() throws {
        let key = numbers(after: "visualSaturation = StudioDefault(key: \"visual.saturation\", value: ",
                          in: try source(Self.keystore)).first
        let asserted = numbers(after: "XCTAssertEqual(StudioDefaultKeys.visualSaturation.value, ",
                               in: try source(Self.suite))
        guard let key else { return XCTFail("could not read the keystore default — re-anchor.") }
        XCTAssertEqual(asserted.count, 1, """
            Expected exactly one saturation assertion in \(Self.suite), found \(asserted.count).
            """)
        XCTAssertEqual(asserted.first, key, """
            \(Self.suite) asserts \(asserted.first ?? "nothing") while the shipped default is \
            \(key). That suite runs behind `continue-on-error`, so this disagreement produces \
            NO visible red — it stayed that way for three weeks after #578.

            This claim exists to give that failure a gate that blocks. Fix the assertion to the \
            shipped value; do not fix the shipped value to the assertion, because the value is \
            a founder decision and a stale test is not a reason to undo one.
            """)
    }
}
