import XCTest
@testable import Echoelmusic

/// #1000 — a finger on the picture plays the DAW too.
///
/// WHY IT EXISTS. `TouchInstrumentView` is the app's one playable surface: it is mounted over
/// the immersive visual, at every window size, in a window that opens on launch, and it sounds
/// scale-quantized notes on the take's own synth. It had ZERO references to `MIDIOutput` — so
/// the app published its body-composed melody to a subscribed DAW and dropped every note the
/// player's own hands made. A musician recording a take got the machine's part and not their own.
///
/// THE RISK THAT SHAPES THE FIX IS THE STUCK NOTE. An external instrument that receives a
/// note-on without its matching off holds it until somebody finds a panic button, on stage. So
/// the repair is not "call MIDI in a few places": it introduces ONE owner for "a touch note
/// begins" and one for "it ends", and routes all twelve emission sites through them. Claim 2 is
/// what keeps that true — it fails the moment a thirteenth site sounds a note past the pair.
///
/// ⚠️ HONEST GRADING, and it corrects what I first wrote here. Six claims, transcribed against
/// both trees: ALL SIX are green on the worktree and red on `HEAD`. The first draft of this
/// header called 4, 5 and 6 "counterweights, green on both trees" — that was a guess about the
/// grading rather than the measurement, and the measurement contradicted it, because every
/// mechanism they name (the helpers' signature, the strong capture, the mount argument) is new
/// in this slice and cannot exist one commit back.
///
/// So none of the six is before/after evidence of a defect being repaired. They are pins on a
/// NEW mechanism. What differs between them is which FUTURE change they catch, and that is the
/// distinction worth stating:
///   · 1, 2, 3 and 6 go red if the handoff is removed or bypassed
///   · 4 goes red if the glide branch's deliberate asymmetry is "tidied" into the helper, which
///     would make the ENGINE retrigger where it currently slides — a musical regression wearing
///     a cleanup's clothes — or if a second bare MIDI path grows where claim 2 cannot see it
///   · 5 goes red if the helpers become instance methods, which silently drops the MIDI half in
///     the four scheduled paths that outlive the view — the exact teardown case that strands a
///     note on someone else's instrument
///
/// ⚠️ WHAT THIS DOES NOT CLAIM. Nothing here proves a byte reached a wire — `MIDIOutput` opens
/// every note call with `guard enabled, isReady`, so with the `midi.out` route off this whole
/// path is silent by construction. That is the intended default, and it is why the surface can
/// call it unconditionally. Device verification is a DAW recording the notes a finger makes.
final class TheTouchNotesReachTheDAWTests: XCTestCase {

    private static let surface = "Sources/Echoelmusic/Studio/TouchInstrumentView.swift"
    private static let window  = "Sources/Echoelmusic/Studio/FloatingVisualWindow.swift"

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

    // 1 — LOAD-BEARING: the surface can reach the DAW at all.
    func testTheSurfaceCarriesAMIDIDestination() throws {
        let text = try source(Self.surface)
        XCTAssertTrue(text.contains("var midiOut: MIDIOutput?"), """
            `TouchInstrumentView` declares no MIDI destination. Without it the one playable \
            surface in the app is deaf to the DAW handoff, and every note a hand makes is lost \
            to anything recording Echoel's virtual source.
            """)
        XCTAssertTrue(text.contains("weak var midiOut: MIDIOutput?"), """
            The UIKit view holds no MIDI destination, so the representable's property reaches \
            nothing. `weak` matters: the app owns `MIDIOutput`, this view does not.
            """)
        XCTAssertTrue(text.contains("v.midiOut = midiOut") && text.contains("uiView.midiOut = midiOut"), """
            The destination is not threaded through BOTH `makeUIView` and `updateUIView`. \
            Missing the update half means the surface keeps whatever it was born with and a \
            later route change never arrives.
            """)
    }

    // 2 — LOAD-BEARING, and the one that keeps the repair whole: ONE owner per lifecycle edge.
    func testNoNoteSoundsPastTheOneOwner() throws {
        let text = try source(Self.surface)
        for needle in ["synth?.noteOn(", "synth?.noteOff(", "voice.noteOn(", "voice.noteOff("] {
            let hits = text.components(separatedBy: needle).count - 1
            XCTAssertEqual(hits, 0, """
                \(hits) call(s) to `\(needle)` bypass the note owners in \(Self.surface).

                Every emission site must go through `startNote`/`stopNote`, because those are \
                the only two places that also tell `MIDIOutput`. A site that speaks to the \
                synth directly is a note an external instrument either never hears, or — far \
                worse — hears and can never lose.

                If you are adding a genuinely new kind of note, add it to the helpers; do not \
                add a thirteenth direct call.
                """)
        }
    }

    // 3 — LOAD-BEARING: each owner really writes BOTH destinations.
    func testEachOwnerWritesBothDestinations() throws {
        let text = try source(Self.surface)
        guard let startRange = text.range(of: "private static func startNote("),
              let stopRange  = text.range(of: "private static func stopNote(") else {
            return XCTFail("""
                One or both note owners are missing from \(Self.surface). Claim 2 would then \
                pass vacuously against a file that emits nothing at all.
                """)
        }
        let start = String(text[startRange.lowerBound..<stopRange.lowerBound])
        let stopTail = String(text[stopRange.lowerBound...])
        let stop = String(stopTail.prefix(600))

        XCTAssertTrue(start.contains("voice?.noteOn(") && start.contains("midi?.noteOn("), """
            `startNote` does not write both destinations. An owner that forwards to only one \
            of them is worse than no owner: claim 2 then certifies that every site goes \
            through a helper which drops half the notes.
            """)
        XCTAssertTrue(stop.contains("voice?.noteOff(") && stop.contains("midi?.noteOff("), """
            `stopNote` does not write both destinations. The missing half here is the stuck \
            note — the failure this whole slice is shaped around.
            """)
    }

    // 4 — COUNTERWEIGHT: the glide's asymmetry is deliberate and must stay explained.
    func testTheGlideMirrorStaysAsymmetricAndSaysWhy() throws {
        let text = try source(Self.surface)
        let bareOn  = text.components(separatedBy: "midiOut?.noteOn(").count - 1
        let bareOff = text.components(separatedBy: "midiOut?.noteOff(").count - 1
        XCTAssertEqual(bareOn, 1, """
            Expected exactly ONE bare `midiOut?.noteOn(` — the glide branch, which retriggers \
            externally where the engine slides internally. Found \(bareOn).

            More than one means a second emission path grew outside the owners (claim 2 cannot \
            see it, because it only watches the synth side). Zero means somebody folded the \
            glide into `startNote` — which would make the ENGINE retrigger a legato slide, \
            turning a singing portamento into a chopped one.
            """)
        XCTAssertEqual(bareOff, 1, "Expected exactly ONE bare `midiOut?.noteOff(`, found \(bareOff).")
        XCTAssertTrue(text.contains("RETRIGGERS where the engine slides"), """
            The glide branch's asymmetry has lost its explanation. Undocumented, it reads as an \
            oversight and the next reader "fixes" it in one of the two wrong directions above. \
            The reason it cannot be faithful is structural: plain MIDI has no channel-wide \
            legato, and per-note bend needs an MPE zone this build does not negotiate (#548).
            """)
    }

    // 5 — COUNTERWEIGHT: static, so the four scheduled paths still mirror after teardown.
    func testTheOwnersDoNotDependOnALivingView() throws {
        let text = try source(Self.surface)
        XCTAssertTrue(text.contains("private static func startNote(_ voice: PolySynthVoice?, _ midi: MIDIOutput?,"), """
            `startNote` no longer takes its destinations as arguments. Four call sites run \
            inside a `Task` that deliberately OUTLIVES the view — they capture `voice` strongly \
            precisely because the note-off is the only thing that can end those voices. An \
            instance method reading `self` would drop the MIDI half in exactly that case, which \
            is the teardown that strands a note on someone else's instrument.
            """)
        XCTAssertTrue(text.contains("private static func stopNote(_ voice: PolySynthVoice?, _ midi: MIDIOutput?, pitch: Int)"),
                      "`stopNote` no longer takes its destinations as arguments — same reason.")
        XCTAssertTrue(text.contains("[weak self, voice, midi]"), """
            No scheduled path captures a strong MIDI destination. The echo and the self-release \
            both fire after the surface may be gone; without the capture their note-offs reach \
            the synth and nothing else.
            """)
    }

    // 6 — COUNTERWEIGHT: the mount actually hands it over.
    func testTheMountPassesTheDestination() throws {
        let window = try source(Self.window)
        XCTAssertTrue(window.contains("@Environment(MIDIOutput.self) private var midiOut"), """
            \(Self.window) does not take `MIDIOutput` from the environment, so it has nothing \
            to hand the surface. Note this is a REFERENCE read: no property of it is touched in \
            that body, so the window does not become an observer (freeze law, 10.76.50).
            """)
        XCTAssertTrue(window.contains("midiOut: midiOut"), """
            The one `TouchInstrumentView(` construction in Sources does not pass `midiOut:`. \
            The property is optional and defaults to nil, so this fails SILENTLY — the surface \
            compiles, plays, and quietly sends nothing, while every comment around it promises \
            the handoff.
            """)
    }
}
