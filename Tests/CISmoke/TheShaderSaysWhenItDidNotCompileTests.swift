// TheShaderSaysWhenItDidNotCompileTests.swift
// Echoel — #1055. Blocking bundle. SOURCE-TEXT SCAN (`Tests/CISmoke/CLAUDE.md` §1): it proves
// the rungs EXIST on every exit, never that one was written at run time.
//
// ⭐ WHY THIS FILE EXISTS, AND IT IS A GAP NO CI GATE CAN COVER. The field shader is Metal
// Shading Language living inside a Swift string literal, compiled by `makeLibrary(source:)`
// at run time. `Xcode Compile Check` builds `Sources/` — to that build the shader is DATA, so
// a syntax error in it is invisible to both gates. The only report was `pipeline` staying nil
// and the draw loop falling back to a calm clear-colour pulse, with an EMPTY `echoel_diag.log`
// next to it. On a founder's phone that is indistinguishable from "the visual is calm today".
//
// #1054 changed that shader text. This is the rung that makes the next such change legible.
//
// ⭐ THE LAW IT IMPLEMENTS is CLAUDE.md's lifecycle ladder: a rung stands BEFORE its step, so
// that a step which dies leaves the ladder short rather than silent — and silence between two
// rungs is a finding. Here there were no rungs at all, so silence meant nothing. There are now
// four: one before the compile, one on each of the two `return` paths, and one after the
// pipeline state that says which way it went.
//
// ⚠️ WHY NOT A NUMBERED LADDER (`1/4`, `2/4`, …). The numbered form is for a SEQUENCE that a
// reader walks to find where it stopped. This is a fork: exactly one of the three outcomes
// happens, and each names itself. Numbering it would invite `diag-ladder.py` to treat a
// healthy early return as a death at step 2 — the #882 misreading, built in on purpose.
//
// ⚠️ AND `EchoelCrashLog.breadcrumb`, NOT `os_log` (#859): the founder's pastable device log
// IS the breadcrumb stream. This same file learned that once already, at its draw-loop
// diagnostic — a line that only reached `os_log` was invisible in every "bitte Log mit offenem
// Visual" round.
//
// ⚠️ HONEST GRADING. No local Swift toolchain (§0). **Six assertions across three claims**
// (3 · 2 · 1), driven against both trees. Against the pre-slice tree, claims 1 and 2 are
// **RED on all five of their assertions** — none of the four rungs existed and the `guard`
// swallowed the compile error with `try?`. Claim 3 is green on both. So **5 REGRESSION
// CATCHES, 1 COUNTERWEIGHT**. Counted from the driven run, not from the outline (#1054).

import Foundation
import XCTest
@testable import Echoelmusic

final class TheShaderSaysWhenItDidNotCompileTests: XCTestCase {

    private static let viewFile = "Sources/Echoelmusic/Views/MetalBioView.swift"

    private func source() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent(Self.viewFile)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(Self.viewFile) could not be read — a missing anchor is "
                    + "a finding, not a pass (#454).")
            return ""
        }
        return text
    }

    /// claim 1 — every way out of `configure` leaves a rung. A silent fallback is the defect;
    /// three exits, three sentences.
    func testEveryExitFromShaderSetupLeavesARung() throws {
        let src = try source()
        for (needle, what) in [
            ("visual: SHADER COMPILE FAILED", "the MSL failed to compile"),
            ("an entry point is missing", "the library built but a function name is wrong"),
            ("visual: pipeline state FAILED", "the pipeline-state object could not be made")
        ] {
            XCTAssertTrue(src.contains(needle), """
                `MetalBioView.configure` no longer reports the case where \(what). That exit \
                leaves `pipeline` nil, the draw loop falls back to a flat pulse, and NO CI \
                gate can see it — the shader is a string, so both gates compile past it. \
                Without this line the founder's log is empty next to a picture that looks \
                merely calm. If the wording changed, move this needle in the same commit.
                """)
        }
    }

    /// claim 2 — and the compile error's own text is carried, because it is the one that names
    /// the offending MSL line. A rung saying only "it failed" costs a second device round.
    func testTheCompileFailureCarriesMetalsOwnMessage() throws {
        let src = try source()
        XCTAssertTrue(src.contains("error.localizedDescription"), """
            The compile rung no longer carries Metal's own message. `makeLibrary` is the exit \
            that fires on an edit to the shader TEXT, and its description names the MSL line \
            and column. Dropping it turns a one-log diagnosis into a bisect.
            """)
        XCTAssertFalse(src.contains("guard let library = try? device.makeLibrary("), """
            The `try?` swallow is back. `try?` on `makeLibrary` discards the only description \
            of what is wrong with the shader — that is what made this failure mode silent for \
            as long as it existed.
            """)
    }

    /// claim 3 — the counterweight (#367). The FALLBACK itself must survive: this slice adds
    /// reporting, it does not turn a degraded picture into a crash. Nothing here may become a
    /// force-unwrap or a fatalError on the way to "better diagnostics".
    func testTheDegradedPathStillReturnsInsteadOfCrashing() throws {
        let src = try source()
        XCTAssertTrue(src.contains("pipeline = try? device.makeRenderPipelineState("), """
            The pipeline-state creation stopped being optional. A shader that cannot be built \
            must leave `pipeline` nil and let the draw loop show its calm clear-colour pulse — \
            never a crash. Reporting a failure and surviving it are the two halves of this \
            slice; do not trade the second for the first.
            """)
    }
}

// NEEDS-FOUNDER-VERIFY: Vollbild-Visual öffnen, dann Diagnostics exportieren — steht dort
// „visual: shader ready"? Wenn das Bild jemals nur noch ruhig pulsiert statt Struktur zu
// zeigen, muss im selben Log GENAU EINE der drei Fehler-Zeilen stehen; ein flaches Bild OHNE
// eine solche Zeile hieße, dass die Leiter an einer vierten Stelle bricht.
