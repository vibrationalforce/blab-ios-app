// LockedTempoIsTheNumberYouSetTests.swift
// Echoel — a tempo the player TYPED must reach the clock unchanged. #380.
//
// WHAT THIS GUARDS. `generate()` resolved the locked tempo as
// `min(max(lockedBPM, 40), 240).rounded()` and handed that to `glideTempo`. Two silent
// disagreements with the control that sets the value:
//
//   · PRECISION. `BodyTempoField` stores `lockedBPM` to 1e-4 and prints every digit; tap
//     tempo stores a tenth. The `.rounded()` made the beat run at a whole BPM under a field
//     still reading 71,2345. That is #368's finding one layer down — #368 established that a
//     MEASUREMENT is not a SETTING and narrowed the *measured* readout to one decimal
//     precisely so the *set* half could keep its resolution. The set half then lost it
//     downstream anyway.
//   · RANGE. The field clamps to `Transport.minTempo...maxTempo` (30…300) and
//     `PatternEngine.minTempo/maxTempo` ARE those same constants — so the engine accepts what
//     the field accepts. Only this one line said 40…240, which matched nothing except
//     `TapTempo`'s own defaults. Type 280, watch the take run 240.
//
// ⭐ WHY IT STAYED INVISIBLE FOR SO LONG, which is the part worth remembering: nothing
// triggered a recompose right after a lock edit, so the rounded value only appeared on the
// NEXT re-seed, tens of seconds later and mixed in with new notes. #356 made every tap post
// the recompose hook — and the defect became a one-second-later correction the player can
// watch happen. A fix that makes an old bug observable is not a regression; it is the bug
// finally having a witness.
//
// ⚠️ THE MEASURED BRANCHES KEEP THEIR ROUNDING and that is deliberate, not an oversight.
// The body-driven tempo is an estimate walked in whole-BPM convergence steps
// (`tempoConvergeStep`); rounding is part of that arithmetic. This file pins one of them so
// a later sweep cannot strip all four `.rounded()`s in the name of #380 — the rule is
// "settings keep their digits", not "nothing rounds".
//
// ⚠️ HONEST LIMITS. Source-text scan, no simulator; it proves what the source SAYS, not what
// the clock does. The clock behaviour is a device listen (NEEDS-FOUNDER-VERIFY: lock a
// fractional tempo, confirm the beat and the field agree a second later; and lock 300, where
// `MIDIOutput`'s clock timer wakes 120×/s on the main actor — its own comment flags that as
// compile-verified only and wanting a run with a Picker open. 300 was always reachable
// instantly via the typed field; #380 is what makes it PERSIST through a re-seed).
// ⛔ Against the PRE-fix source two assertions fire, not one. The `.rounded()` one is the
// intended red; the clamp one also fails, and its wording ("no longer clamps to the
// transport's own bounds") reads as a regression from a state that never existed. Left as is
// — rewording it to cover both eras would blunt the message a real regression needs — but
// noted, because "red for the right reason" was claimed for this file and is true of one
// assertion, not of both.
// `Tests/CISmoke` is the blocking bundle. SKIPS rather than passes if the tree is absent.

import Foundation
import XCTest

final class LockedTempoIsTheNumberYouSetTests: XCTestCase {

    /// The one line that turns `lockedBPM` into the tempo the clock is glided to.
    func testTheLockedTempoIsNotRoundedOrReClamped() throws {
        let studio = try codeLines("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        // ⛔ THIS MATCHED THE LITERAL `tempo = lockedBPM`, which is the shape only AFTER the
        // fix. Run against the pre-#380 source it found ZERO lines and failed with "the
        // resolution moved" — a red for the right file and the wrong reason, which is how a
        // guard teaches the next reader something untrue. Matching the two tokens separately
        // makes the old line `tempo = min(max(lockedBPM, 40), 240).rounded()` land here, so
        // the rounding assertion below reports the actual defect.
        let resolvers = studio.filter { $0.contains("tempo =") && $0.contains("lockedBPM") }

        XCTAssertEqual(resolvers.count, 1, """
            Expected exactly one line resolving the take's tempo from `lockedBPM`, found \
            \(resolvers.count): \(resolvers.map { $0.trimmingCharacters(in: .whitespaces) }).
            A second one is a second opinion about what a locked tempo is, which is the whole \
            defect #380 closed; none means the resolution moved and this guard now watches \
            nothing — point it at the new place rather than deleting it.
            """)
        guard let line = resolvers.first else { return }

        XCTAssertFalse(line.contains(".rounded()"), """
            The locked tempo is rounded again before it reaches the clock:

                \(line.trimmingCharacters(in: .whitespaces))

            `lockedBPM` is a value the player SET — to 1e-4 through the transport field, to a \
            tenth through tap tempo — and both show every digit they stored. Rounding here \
            makes the beat disagree with the number on screen one second after the edit. If a \
            downstream consumer genuinely needs an integer, round THERE and say which one.
            """)

        XCTAssertTrue(line.contains("clamped(to: Transport.minTempo...Transport.maxTempo)"), """
            The locked tempo no longer clamps to the transport's own bounds:

                \(line.trimmingCharacters(in: .whitespaces))

            Two things ride on that exact expression. (1) RANGE: `BodyTempoField` clamps to \
            these constants and `PatternEngine.minTempo/maxTempo` are these constants, so a \
            third opinion here means the field accepts a tempo the take refuses — it said \
            40…240 against the field's 30…300 until #380. (2) NaN, as CONSISTENCY not as a \
            live fix: `min(max(v, lo), hi)` passes NaN through both bounds, but \
            `PatternEngine.glideTempo` already clamps NaN-safely against the same bounds, so \
            a NaN never reached the clock even before #380. Do not restate this as a silence \
            bug — `glideTempo` carries its own ⛔ about a comment that did exactly that.
            """)
    }

    /// The field this guard measures the take against has to keep clamping the same way, or
    /// the two agree only by coincidence.
    ///
    /// ⛔ THIS TEST'S STATED REASON WAS FALSE AND THE REVIEWER CAUGHT IT. It said "#380
    /// removed the take's own second clamp on the strength of this one" and that the take
    /// "now honours `lockedBPM` verbatim". #380 WIDENED that clamp, it did not remove it —
    /// the sibling assertion above literally requires it to still be there — and
    /// `PatternEngine.glideTempo` clamps a third time. Nothing out of range can reach the
    /// clock even if this field's clamp vanished. The assertion is still worth having as a
    /// consistency pin; the danger of the old wording was that a reader would believe the
    /// take is unguarded and add a FOURTH clamp to "restore safety", re-creating exactly the
    /// disagreement #380 closed. Written in the file whose header lectures about this class.
    func testTheFieldClampsToTheSameBounds() throws {
        let field = try codeLines("Sources/Echoelmusic/Studio/BodyTempoField.swift")
        let clamps = field.filter {
            $0.contains("clamped(to: Transport.minTempo...Transport.maxTempo)")
        }
        XCTAssertGreaterThanOrEqual(clamps.count, 2, """
            `BodyTempoField` clamps to the transport bounds on \(clamps.count) line(s); both \
            the lock (`toggleLock`) and the typed edit (`lockedBinding`) should, so the \
            control that SETS the tempo and the take that PLAYS it agree on what is legal by \
            construction rather than by three independent clamps happening to match. Nothing \
            unsafe reaches the clock if this narrows — the take clamps and `glideTempo` \
            clamps again — but the value the player typed would then be silently altered \
            somewhere other than where they typed it. (Census note: `lockedBPM` has a THIRD \
            writer this guard does not scan, `WorkspaceView.modeBinding`, which seeds it from \
            an already-clamped `transport.tempo` via the NaN-unsafe `min(max(…))`. Harmless \
            today because of its input; not harmless as a pattern.)
            """)
    }

    /// ⚠️ The measured path is NOT covered by #380 and must not be swept along with it.
    func testTheBodyDrivenTempoStillRounds() throws {
        let studio = try codeLines("Sources/Echoelmusic/Studio/EchoelStudioView.swift")
        XCTAssertTrue(studio.contains { $0.contains("tempo = (current + delta).rounded()") }, """
            The body-driven convergence step no longer rounds. That rounding is deliberate: \
            the tempo there is an ESTIMATE walked toward the body in whole-BPM steps \
            (`tempoConvergeStep`), and #380's rule is "a value the player SET keeps its \
            digits" — not "nothing rounds". If the convergence really should carry fractions, \
            that is its own decision with its own listen, and this assertion should be \
            rewritten rather than deleted.
            """)
    }

    // MARK: - Reading the source

    /// Lines of `path` that are neither blank nor whole-line comments.
    ///
    /// ⚠️ Whole-line only, so a trailing `// tempo = lockedBPM …` inside a rationale block
    /// would be counted. The ⛔ block this guard was written beside quotes the OLD expression
    /// (`min(max(lockedBPM, 40), 240)`) on its own comment lines — those are stripped, and
    /// none of the tokens asserted above appear as a trailing comment today.
    private func codeLines(_ path: String) throws -> [String] {
        let url = try repoRoot().appendingPathComponent(path)
        let text = try String(contentsOf: url, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter {
                let trimmed = $0.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !trimmed.hasPrefix("//")
            }
    }

    /// Repo root, derived from this file's compile-time path (`Tests/CISmoke/…`).
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let probe = root.appendingPathComponent("Sources/Echoelmusic/Studio/BodyTempoField.swift")
        guard FileManager.default.fileExists(atPath: probe.path) else {
            throw XCTSkip("""
                source tree not present under \(root.path) — this test inspects source text, \
                so it SKIPS rather than reporting a green it did not earn
                """)
        }
        return root
    }
}
