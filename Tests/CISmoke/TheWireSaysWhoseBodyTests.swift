// TheWireSaysWhoseBodyTests.swift
// Echoel — #639: the demo generator's numbers left the device unlabelled.
//
// WHAT THIS GUARDS. `BioEgressPolicy` deliberately lets `.fallback` — the demo generator —
// stream out: it is Echoel's own synthesis, not Health-store data, so 5.1.3 does not touch it
// and blocking it would break the demo mode the founder actually uses. The consequence nobody
// had closed: a lighting desk, an immersive renderer or a fellow performer received
// `/echoelmusic/bio/heart/bpm 74` from a simulator with no way at all to tell. Every IN-APP
// surface has said "Demo" since #627…#637; THIS wire said nothing — and it is the half aimed
// at integrators who cannot see the screen. CLAUDE.md positions Echoel as "the bio-reactive
// object source for accessible immersive multidimensional media art (open standards)"; an
// integrator who cannot distinguish a body from a simulator is exactly the trust this
// positioning cannot afford.
//
// ⛔ "THE WIRE SAID NOTHING" WAS TOO FLAT IN THE FIRST DRAFT, and the counter-example is one
// slice old: #629 put provenance on a real network wire (`ColabPayload.BioPeek.synthetic`, the
// peer rows of a Live-Colabo session). The distinction is the CONTRACT, not the medium. That
// one is our own encoding between two copies of this app, so it could be widened at will and is
// deliberately TRI-STATE (`Bool?`, where "an older peer" is a third answer). OSC is a PUBLISHED
// contract with receivers nobody here controls, and an OSC float has no "unknown" — so this one
// is binary, and "a build older than #639" is expressed as the ABSENCE of the address.
//
// THE SHAPE, and it is the part worth reviewing rather than the address name. Three options
// were on the table and two are wrong:
//   · Append an argument to the existing addresses — BREAKS every integrator on the old
//     contract. A receiver expecting one float gets two. Rejected outright: honesty that
//     breaks the people it is for is not honesty.
//   · Send the flag unconditionally — breaks #245, the law this very function enforces: a
//     frame with NOTHING measured must be SILENT so a receiver reads absence as absence. The
//     first cut of this slice did exactly that and reddened
//     `OSCAbsenceTests.testAFrameWithNothingMeasuredSendsNothingAtAll`.
//   · **Additive address, gated on THE BATCH** — ships only alongside data it describes.
//     Silent frames stay silent, no receiver ever gets a bare flag, and every value that does
//     arrive is accompanied by its origin. That is what shipped.
//
// ⭐ A THIRD KIND OF GATE, named so the next reader does not mis-file it. #245 gates each
// address on ITS OWN measurement. #215 drops an address that has no producer at all. This one
// is gated on the BATCH. Claims 3 and 8 are what make that distinction executable rather than a
// comment: the flag never travels alone (so nothing measured ⇒ nothing at all, today), and
// breath alone — no pulse anywhere — still carries it.
//
// ⚠️ 0 IS A FACT HERE, not a missing measurement — it means "a real body" — which is why the
// no-structural-zeros rule (#245) does not reach this line, and why claim 2 asserts the
// address is PRESENT with 0 rather than absent. Absence would mean two different things at
// once ("measured" and "old build"), which is precisely the ambiguity this slice removes.
//
// ⚠️ IT IS ALSO A DISCLOSURE, and saying so is part of shipping it. The flag reveals no sensor
// and opens no HealthKit path (claim 7 pins 5.1.3 untouched). What it does remove is plausible
// deniability: a receiver on the LAN can now tell that a real body is in the room rather than a
// simulator. That is the intent — an integrator must be able to trust the number — but it is a
// new fact on the network, and it belongs written down rather than in the gap between two
// honest sentences.
//
// KIND (§1): **END-TO-END BEHAVIOUR**, all fifteen claims. `OSCSender.bioMessages(for:)` and
// `OSCSender.eventMessages(for:lastAnnounced:)` are both `nonisolated static`, and
// `BioSampleFrame` / `BioEvent` / `BioSource` / `BioEgressPolicy` are public Foundation-only
// value types, so this bundle drives the shipped producers and reads their real output.
// ⛔ "No source-text scanning and no needles anywhere in this file" STOOD HERE AND CLAIM 16
// MAKES IT FALSE (#788). Claims 1-15 are still pure behaviour; claim 16 walks `docs/` and reads
// text, because what it guards is a DOC, and no behavioural path can reach one. Corrected here
// rather than left standing: a header that describes a method the file no longer uses is #374,
// and a claim contradicted by its own file is #425 - this file paid for that once already, two
// commits ago, on claim 14. What stays a DEVICE
// PROBE: that a real receiver (TouchOSC, a desk, an ADM renderer) actually latches the flag.
//
// GRADING (#433 / §3), driven against the parent (096d519) and this tree — the gates modelled
// in Python from `bioMessages`' own conditions and every claim run through them:
//   · **4 REGRESSIONS** — claims 1, 2, 4 and 8. The address does not exist on the parent at
//     all, so this is ONE finding (#486), not four, and certainly not the eight an assertion
//     count would suggest (claim 2 loops over three sources).
//   · **4 COUNTERWEIGHTS** — claim 3 ("never alone", which reduces to #245's silence today;
//     green on both trees and the reason the shape is what it is), claim 5 (the old contract untouched), claim 6 (the demo may still
//     egress — the WRONG fix for this defect is to start blocking it, which would break demo
//     mode while looking like a privacy win) and claim 7 (5.1.3 untouched). Claim 8 carries an
//     embedded one: the two breath addresses it checks are green on both trees, and they are
//     what make its flag half mean "the batch gate is not the pulse gate".
//   ⛔ THE FIRST DRAFT OF THIS BLOCK BOOKED CLAIM 5 AS A REGRESSION and it is not: `/heart/bpm`
//     carries exactly one float on the parent too, because the parent simply had no provenance
//     at all. It is a COUNTERWEIGHT, and a load-bearing one — it is the executable form of the
//     rejected "append an argument" design, so it must be green on both trees or it is not
//     guarding a decision. Booking a counterweight as a regression is §3's flattering
//     direction, found by driving the model rather than by re-reading the prose. ⛔ And the
//     doc comment on the method itself still said `REGRESSION (first assertion)` after this
//     block retracted it — a claim and its own refutation in one file (#425), corrected here.
//   · No stripper: this file reads no source text, so §2's raw-vs-stripped measurement does
//     not apply. Stated rather than omitted, because every sibling in this family reports one.
//
// GRADING for #785's claims 9–15, driven against 94d396c and this tree:
//   · **5 REGRESSIONS** — claims 9, 10, 11, 12, 13. `eventMessages` does not EXIST on the
//     parent, so per #486 this is ONE finding, not five: the parent's `drainAndSendEvents`
//     sent each event inline with no provenance at all. The five split the finding by the
//     property each pins (present · both cases · once per burst · re-announce in place · across
//     drains), because a single "the flag is there" assertion would have been satisfied by the
//     per-event shape the latch exists to avoid.
//   · **1 COUNTERWEIGHT + 1 SPLIT** — claim 15 (the two-float contract) is a pure counterweight:
//     the parent sent exactly those two floats, so it guards the rejected "append an argument"
//     design and not the defect. ⛔ CLAIM 14 WAS BOOKED AS THE SECOND COUNTERWEIGHT AND IS NOT
//     ONE. Driving the model showed it splits: its MESSAGE half (an empty drain emits nothing)
//     is green on the parent — the parent's inline loop sent nothing when the queue was empty —
//     but its LATCH half (`announced` survives an empty drain) is RED there, because the parent
//     has no such concept at all. So claim 14 is one counterweight assertion and one regression
//     assertion in one method. Kept together on purpose: they describe one behaviour ("an empty
//     drain changes nothing"), and separating them would leave the silence assertion able to
//     pass while the latch was quietly reset. Recorded because booking a regression half as a
//     counterweight is §3's flattering direction — the same error the block above retracted for
//     claim 5, found the same way, by driving the model rather than re-reading the prose.
//     Neither can literally RUN on the parent, since the symbol is new; both were modelled in
//     Python against the parent's inline loop.
//   · MUTATION EVIDENCE (§3: a claim that no mutation can redden is not a guard). Seven
//     deliberate mutations of the builder, each reddening exactly the claims that name it:
//     unconditional flag → 11, 13 · flag placed AFTER its event → 9, 10, 12 · origin hardcoded
//     synthetic → 10, 12 · incoming latch ignored → 13, 14-latch · provenance as a third float
//     → 15 · flag on an empty drain → 14-messages · `announced` never returned → 9, 10, 12, 13,
//     14-latch. Every claim is covered and the unmutated control stays green.
//   ⛔ NOT BOOKED AS A FINDING: `send(event:)` lost its last caller in this slice and was
//     deleted. That is housekeeping inside the change, not a defect the guard caught.
//
// ⚠️ #364: a DIFFERENT provenance shape is not forbidden. A richer per-source address, a
// bundle, or a return channel would all satisfy the law and turn claims 1/2/4/8 red — and, on
// the event path, 9/10/12; a different CADENCE (per event, or once per drain regardless of
// change) would turn 11/13 red without being wrong. That is the moment to rewrite this file. What is forbidden silently is a `.fallback` frame's values
// reaching the wire with nothing that says so.
//
// ⚠️ STILL OPEN and deliberately NOT solved here, because each needs its own decision:
//   · **ADM-OSC** (`/adm/obj/{n}/*`) is a PUBLISHED STANDARD address space owned by someone
//     else. Inventing `/adm/obj/n/synthetic` inside it would pollute that namespace, which is
//     the opposite of the open-standards posture this slice serves. It needs a decision about
//     WHERE such a flag belongs, not a quick append.
//     ⭐ #786 MEASURED TWO THINGS THAT MAKE THAT DECISION CHEAPER, and pinned them in
//     `TheADMObjectCarriesNoOriginTests`:
//       (a) **Whether the standard reserves a vendor namespace is UNMEASURED and not measurable
//           from public sources.** The public README of `immersive-audio-live/ADM-OSC` defines
//           only `/adm/obj/{n}/…` and says a fuller dictionary "is being discussed"; the
//           document that would answer it — "Specification v1.0 and implementation guide" — is
//           an AES e-library paper (aes2.org id=22722), i.e. paywalled. So today a session
//           cannot check whether an extension address would even be LEGAL. Written as
//           UNMEASURED rather than guessed (§2), because "there is no vendor space" and "I could
//           not read the spec" are different facts and only the second one is ours.
//       (b) ⛔ **THE OBVIOUS WORKAROUND IS FALSE BY DEFAULT.** "An ADM integrator can just also
//           subscribe to our own `/echoelmusic/bio/synthetic`" sounds right and does not hold:
//           `OSCSender` and `ADMOSCSender` are INDEPENDENT senders with separately persisted
//           targets (`net.osc.host`/`net.osc.port` vs `net.adm.host`/`net.adm.port`) and
//           different default ports. A renderer listening on the ADM port receives no
//           `/echoelmusic/*` at all. It works only if an operator deliberately aligns both on
//           one host that listens on both ports — a configuration coincidence, not a contract,
//           and never something a spec sheet may claim. This is the half worth a guard: it is a
//           CODE property that could change, and if it changed this bullet would silently
//           overstate how open the open half is.
//   · **Art-Net and sACN** carry DMX and are the honest gap in this family. ⛔ THE FIRST DRAFT
//     CALLED THIS "a genuine cannot — no metadata room at all", AND THAT IS FALSE. A DMX
//     universe is 512 slots; `ArtNetSender.dmxChannels` uses FOUR (dimmer + R + G + B), eight
//     at 16-bit. Over five hundred are free. What is missing is a CONVENTION — a slot a desk
//     would have to be patched to read, which is a very different (and weaker) argument than
//     an impossibility, and one a lighting designer could reasonably reject. Writing "cannot"
//     where the truth is "nobody has designed it" is the same over-claim this whole family of
//     slices exists to remove, one level up.
//   (The discrete-event path stood here as the third open half and is CLOSED by #785 — see
//   the block below. Two halves remain.)
//
// ⭐ #785 — THE EVENT PATH, and the one design difference worth reading before the claims.
// `/echoelmusic/bio/event/*` now carries provenance too, through `OSCSender.eventMessages`.
// The ordering question the bullet above registered has an answer: the flag goes immediately
// BEFORE the event it describes, and again only when the origin CHANGES. It is NOT the batch
// path's unconditional `insert`, and that asymmetry is deliberate, not an oversight:
//   · A batch is ~1 Hz and already carries several messages, so re-stating the flag every time
//     is free and lets a late receiver learn the state on its next frame.
//   · Events CLUSTER — a strap delivers several per-RR beats in one 100 ms drain, breath onsets
//     arrive in pairs. Re-stating per event would multiply traffic on the one path shaped by
//     latency, for no information. So the sender LATCHES the last announced value across
//     drains (`lastAnnouncedEventSynthetic`) and the builder is pure and takes it as input.
//   · A receiver that joins mid-session therefore learns the state from the BATCH, which is
//     exactly what CLAUDE.md's "als ZUSTAND latchen" already asks of it. The event path is not
//     a second source of truth for the state; it is the same state, announced when it moves.
// The third rejected shape is unchanged from #639 and now has its own claim: appending a float
// to `/bio/event/*` would break every integrator on the `[confidence, aux]` contract (claim 15).
//
// ⚠️ THE FOUNDER GATE THIS SLICE RETRACTED, stated here because a retraction that only lives in
// a commit message is not written down. `BioSimulator`'s header registered "whether to add …
// a synthetic marker on the OSC egress" as **a founder question (#462)**. #639 answers the OSC
// half unilaterally, and the reasons are on the record: the sentence bundled two decisions, the
// screen half was already shipped without an ask (#627), and this one is additive, reversible
// and breaks no published contract. #785 answers the EVENT half on the same reasoning; the two
// halves neither answers (ADM-OSC, DMX) stay registered as open, above. If the founder wants the flag gone, deleting the `insert`
// restores the previous wire exactly.

#if canImport(Network)
import Foundation
import XCTest
@testable import Echoelmusic

final class TheWireSaysWhoseBodyTests: XCTestCase {

    private static let provenance = "/echoelmusic/bio/synthetic"

    /// A frame every gate accepts, so `bioMessages` is non-empty and the batch gate opens.
    private func liveFrame(_ source: BioSource) -> BioSampleFrame {
        BioSampleFrame(timestamp: 1000, heartRateBPM: 64, hrvNormalized: 0.45,
                       breathRate: 12, breathPhase: 0.3, coherence: 0.62,
                       motionEnergy: 0, source: source)
    }

    /// A frame no gate accepts: no pulse, no plausible breath.
    private func deadFrame(_ source: BioSource) -> BioSampleFrame {
        BioSampleFrame(timestamp: 1000, heartRateBPM: 0, hrvNormalized: 0,
                       breathRate: 0, breathPhase: 0.25, coherence: 0,
                       motionEnergy: 0, source: source)
    }

    /// The bundle's repo-root idiom - copied, not re-invented (#416/#786). It SKIPS when the
    /// tree is absent so claim 16's source read cannot report a green it did not earn.
    private func repoRoot() throws -> URL {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(
            atPath: root.appendingPathComponent("docs").path) else {
            throw XCTSkip("""
                docs/ not present under \(root.path) - claim 16 reads doc text, so it SKIPS \
                rather than reporting a green it did not earn
                """)
        }
        return root
    }

    private func messages(_ f: BioSampleFrame) -> [(address: String, floats: [Float])] {
        OSCSender.bioMessages(for: f)
    }

    // MARK: - 1–2  the flag is present, and it tells the two cases apart

    /// 1 — REGRESSION. The demo generator's values now announce themselves.
    func testADemoFrameLabelsItselfOnTheWire() {
        let msgs = messages(liveFrame(.fallback))
        guard let flag = msgs.first(where: { $0.address == Self.provenance }) else {
            return XCTFail("""
                A `.fallback` frame sent \(msgs.map(\.address)) and no \(Self.provenance). \
                The demo generator is allowed to egress by design; without this address a \
                lighting desk or a fellow performer cannot tell it from a body.
                """)
        }
        XCTAssertEqual(flag.floats, [1], """
            \(Self.provenance) carried \(flag.floats) for a demo frame. 1 means synthetic.
            """)
    }

    /// 2 — REGRESSION, and the half that is easy to get wrong: a real body sends the address
    /// with 0 rather than omitting it.
    ///
    /// ⚠️ WHAT OMISSION MEANS UNDER THE BATCH GATE, stated precisely because the first draft of
    /// this comment was loose. Absence of this address does NOT mean "not measured" the way it
    /// does for every other address in this function — it means one of exactly two things: the
    /// batch was empty (nothing measured at all, so the frame is silent end to end, claim 3),
    /// or the sender predates #639. Making a real body send 0 is what keeps those two the only
    /// readings; letting it stay silent would add a third and make the address useless.
    func testARealBodyAlsoSaysSoRatherThanStayingSilent() {
        for source in [BioSource.cameraPPG, .ble, .faceCam] {
            let msgs = messages(liveFrame(source))
            guard let flag = msgs.first(where: { $0.address == Self.provenance }) else {
                XCTFail("""
                    A `\(source)` frame omitted \(Self.provenance). An absent flag cannot be \
                    told apart from an old build; 0 is a FACT here, not a missing measurement.
                    """)
                continue
            }
            XCTAssertEqual(flag.floats, [0], "\(source) is a real body and must send 0")
        }
    }

    // MARK: - 3  the #245 counterweight — and the reason for the batch gate

    /// 3 — COUNTERWEIGHT, green on both trees, and the assertion that shapes the whole slice.
    /// #245: a frame with nothing measured must be SILENT, so a receiver reads absence as
    /// absence rather than "unchanged". The first cut of this slice appended the flag
    /// unconditionally and turned every dead frame into traffic. Gating on the BATCH keeps
    /// both laws: silence stays total, and nothing that speaks does so anonymously.
    ///
    /// ⚠️ THE INVARIANT IS "NEVER ALONE", NOT "ALWAYS EMPTY" — and the first rewrite of this
    /// case got that wrong in the direction #364 names. It asserted flat `msgs.isEmpty`. Motion
    /// rides a STRUCTURAL gate (#215): it is absent because nothing produces it, not because 0
    /// is suspect, and the day a CoreMotion provider lands `motionEnergy: 0` becomes a real
    /// reading that this same dead frame legitimately sends. The batch is then non-empty, the
    /// provenance flag correctly rides along — and a flat `isEmpty` (or a `XCTAssertFalse` on
    /// the flag) would redden the BLOCKING bundle on the commit that added a sensor, with a
    /// failure message blaming the provenance flag for someone else's feature.
    ///
    /// So the assertion is the law itself, in both worlds: **the flag never travels without at
    /// least one value beside it.** With no motion producer that reduces to total silence,
    /// which is #245; with one, it reduces to "motion plus its origin", which is still the
    /// batch gate doing its job. Neither reading needs this file edited.
    func testTheProvenanceFlagNeverTravelsAlone() {
        for source in [BioSource.fallback, .cameraPPG] {
            let msgs = messages(deadFrame(source))
            let addresses = msgs.map(\.address)
            let values = addresses.filter { $0 != Self.provenance }
            if addresses.contains(Self.provenance) {
                XCTAssertFalse(values.isEmpty, """
                    A `\(source)` frame with nothing measured sent \(Self.provenance) and \
                    NOTHING else. #245: silence is the protocol's only word for "I do not \
                    know", and a bare flag is still traffic — a receiver that sees traffic \
                    reads the missing addresses as unchanged, not absent. The flag is gated on \
                    the BATCH; it must never open a batch of its own.
                    """)
            }
            if ModSource.motion.hasProducer {
                XCTAssertEqual(values, ["/echoelmusic/bio/motion"], """
                    A motion producer exists now, so a dead frame legitimately sends motion 0 \
                    and nothing else — but its values were \(values). Re-read this case rather \
                    than the flag: what changed is #215's structural gate, not #639's.
                    """)
            } else {
                XCTAssertTrue(msgs.isEmpty, """
                    A `\(source)` frame with no pulse and no plausible breath produced \
                    \(addresses). With no motion producer (#215) nothing at all is measured, \
                    so the batch must be empty end to end.
                    """)
            }
        }
    }

    // MARK: - 4–5  the old contract is not disturbed

    /// 4 — REGRESSION. First in the list, so a receiver that DOES process a tick in order
    /// reads the origin before the values.
    ///
    /// ⚠️ A COURTESY, NOT A GUARANTEE, and the guard says so rather than implying a promise
    /// the transport cannot keep: these become separate UDP datagrams and UDP does not
    /// preserve order. The address is re-sent with every frame and only changes when the
    /// player switches source, so a receiver latching it as STATE is correct and a one-tick
    /// inversion self-corrects. This pins what the sender controls.
    func testTheOriginIsOfferedBeforeTheValues() {
        let msgs = messages(liveFrame(.fallback))
        XCTAssertEqual(msgs.first?.address, Self.provenance, """
            \(Self.provenance) is no longer the first message of the batch (order: \
            \(msgs.map(\.address))). The sender cannot guarantee arrival order over UDP, but \
            it can control what it offers first.
            """)
    }

    /// 5 — COUNTERWEIGHT, both assertions. The existing addresses are untouched: the origin
    /// arrived as its OWN address, never as an extra argument. Appending a second float to
    /// `/heart/bpm` would have been the smaller diff and would have broken every receiver
    /// already bound to the published contract. Green on the parent too — the parent had no
    /// provenance at all — which is exactly what a counterweight over a rejected design looks
    /// like (§3, and the ⛔ in the grading block above).
    func testTheExistingAddressesKeepTheirOldShape() {
        let msgs = messages(liveFrame(.cameraPPG))
        guard let bpm = msgs.first(where: { $0.address == "/echoelmusic/bio/heart/bpm" }) else {
            return XCTFail("the fixture no longer emits /heart/bpm — re-anchor this case (#454)")
        }
        XCTAssertEqual(bpm.floats.count, 1, """
            /echoelmusic/bio/heart/bpm now carries \(bpm.floats.count) floats. Provenance must \
            never ride along as an extra argument on an existing address — that silently \
            breaks every integrator on the published contract.
            """)
        XCTAssertEqual(bpm.floats.first, 64, "the value itself must be unchanged")
    }

    // MARK: - 6–7  what this slice must NOT have changed

    /// 6 — COUNTERWEIGHT, and the wrong fix this file exists to rule out. The tempting reading
    /// of "demo data leaves the device unlabelled" is "so stop sending it". That would break
    /// demo mode — which is how the instrument is shown without a body attached — and would
    /// look like a privacy improvement while removing a feature. `.fallback` is Echoel's OWN
    /// synthesis; 5.1.3 is about the Health store and does not touch it.
    func testTheDemoSourceMayStillLeaveTheDevice() {
        XCTAssertTrue(BioEgressPolicy.allowsEgress(.fallback), """
            The demo source was blocked from egress. Labelling it was the fix; silencing it \
            removes the mode the instrument is demonstrated in, and 5.1.3 does not apply to \
            Echoel's own synthesis.
            """)
        XCTAssertFalse(messages(liveFrame(.fallback)).isEmpty,
                       "a demo frame must still produce values, now labelled")
    }

    /// 7 — COUNTERWEIGHT. 5.1.3 is untouched: the Health store still never reaches the wire,
    /// so the new address can never describe a HealthKit frame in the first place.
    func testHealthStoreSourcesStillCannotEgressAtAll() {
        for source in [BioSource.healthKit, .watch, .oura] {
            XCTAssertFalse(BioEgressPolicy.allowsEgress(source), """
                `\(source)` became egress-allowed. App Store 5.1.3: data from the HealthKit \
                store may not be shared with third parties, and a UDP packet to a user-typed \
                host is exactly that. Adding provenance does not license sending it.
                """)
        }
    }

    // MARK: - 8  the batch gate is not the pulse gate

    /// 8 — REGRESSION, and the case that separates "gated on the batch" from "gated on the
    /// pulse" — a distinction the prose asserts and nothing else executes. A breath-only frame
    /// (no pulse anywhere, so no `/heart/*` at all) is a real and common state: the respiration
    /// estimator locks before the pulse does, and a VJ mapping breath to opacity is bound to
    /// exactly this batch. It must still carry its origin.
    ///
    /// The two breath assertions are the embedded counterweight: green on both trees, and
    /// without them the flag assertion would be satisfied by a frame that sent the flag and
    /// nothing else — the very shape claim 3 forbids.
    func testABreathOnlyBatchStillCarriesItsOrigin() {
        let breathOnly = BioSampleFrame(timestamp: 1000, heartRateBPM: 0, hrvNormalized: 0,
                                        breathRate: 12, breathPhase: 0.3, coherence: 0,
                                        motionEnergy: 0, source: .fallback)
        let msgs = messages(breathOnly)
        let addresses = msgs.map(\.address)
        XCTAssertTrue(addresses.contains("/echoelmusic/bio/breath/rate"),
                      "the fixture no longer emits breath at all — re-anchor this case (#454)")
        XCTAssertFalse(addresses.contains("/echoelmusic/bio/heart/bpm"),
                       "this fixture must have NO pulse, or it stops testing the breath-only case")
        guard let flag = msgs.first(where: { $0.address == Self.provenance }) else {
            return XCTFail("""
                A breath-only demo batch (\(addresses)) went out with no \(Self.provenance). \
                The gate is the BATCH, not the pulse: a VJ mapping breath to opacity gets a \
                simulator's breathing with nothing that says so.
                """)
        }
        XCTAssertEqual(flag.floats, [1], "a breath-only demo batch is still synthetic")
    }

    // MARK: - 9–15  the discrete-event path (#785)

    /// A stamped event. `aux` is an inter-beat interval in ms for `.heartbeat`, per `BioEvent`.
    private func beat(_ source: BioSource?, confidence: Float = 0.82,
                      aux: Float = 640) -> BioEvent {
        BioEvent(timestamp: 2000, kind: .heartbeat, confidence: confidence,
                 aux: aux, source: source)
    }

    private func built(_ events: [BioEvent], lastAnnounced: Bool? = nil)
        -> (messages: [(address: String, floats: [Float])], announced: Bool?) {
        OSCSender.eventMessages(for: events, lastAnnounced: lastAnnounced)
    }

    private static let beatAddress = "/echoelmusic/bio/event/heartbeat"

    /// 9 — REGRESSION. A demo burst announces itself, and BEFORE the event it describes.
    /// Ordering is asserted by WHOLE-LIST equality rather than by `contains`, because array
    /// equality is positional and `contains` is not: a flag that arrives after the value it
    /// labels leaves a receiver one event behind for the whole burst, and `contains` would
    /// happily accept that.
    func testADemoEventBurstAnnouncesItselfBeforeTheFirstEvent() {
        let out = built([beat(.fallback)])
        let addresses = out.messages.map(\.address)
        XCTAssertEqual(addresses, [Self.provenance, Self.beatAddress], """
            A demo heartbeat produced \(addresses). Expected the flag first, then the event: \
            an integrator reading `/bio/event/heartbeat` from a simulator otherwise has no \
            way at all to tell — the same gap #639 closed on the batch path.
            """)
        XCTAssertEqual(out.messages.first?.floats, [1], "1 means synthetic")
        XCTAssertEqual(out.announced, true, """
            The builder must report what it announced, or the caller's latch cannot carry \
            across drains and the flag degenerates to once-per-event.
            """)
    }

    /// 10 — REGRESSION. A real body says 0 rather than staying silent, for the reason claim 2
    /// spells out one screen up: absence must keep meaning exactly one thing.
    func testARealBodysEventsAlsoSaySo() {
        for source in [BioSource.cameraPPG, .ble, .faceCam] {
            let out = built([beat(source)])
            XCTAssertEqual(out.messages.map(\.address),
                           [Self.provenance, Self.beatAddress], """
                A `\(source)` heartbeat produced \(out.messages.map(\.address)).
                """)
            XCTAssertEqual(out.messages.first?.floats, [0], """
                `\(source)` is a real body; 0 is a FACT here, not a missing measurement.
                """)
            XCTAssertEqual(out.announced, false)
        }
    }

    /// 11 — REGRESSION, and the whole reason this path got a latch instead of copying the batch
    /// path's unconditional `insert`. Breath onsets and per-RR heartbeats CLUSTER: a strap
    /// delivers several beats in one 100 ms drain. Re-stating provenance per event would
    /// multiply traffic on the one path shaped by latency.
    func testASameOriginBurstAnnouncesItselfExactlyOnce() {
        let out = built([beat(.fallback, aux: 640), beat(.fallback, aux: 655),
                         beat(.fallback, aux: 631)])
        let flags = out.messages.filter { $0.address == Self.provenance }
        XCTAssertEqual(flags.count, 1, """
            Three same-origin events produced \(flags.count) flags in one drain \
            (\(out.messages.map(\.address))). Once per CHANGE, not once per event.
            """)
        XCTAssertEqual(out.messages.count, 4, "one flag plus three events")
    }

    /// 12 — REGRESSION. A source switch mid-drain must re-announce, and immediately before the
    /// event it describes — not at the head of the burst, where it would mislabel every event
    /// in front of the switch.
    func testASourceChangeMidBurstReAnnouncesInPlace() {
        let out = built([beat(.fallback), beat(.cameraPPG)])
        XCTAssertEqual(out.messages.map(\.address),
                       [Self.provenance, Self.beatAddress,
                        Self.provenance, Self.beatAddress], """
            A demo→camera switch produced \(out.messages.map(\.address)). The second flag \
            must sit between the two events, or the camera beat inherits the demo label.
            """)
        // Guarded rather than subscripted: on a shorter list a raw `[2]` would TRAP and the
        // named failure above would never be printed (`guard all array access`).
        let flags = out.messages.filter { $0.address == Self.provenance }.map(\.floats)
        XCTAssertEqual(flags, [[1], [0]], """
            The two flags carried \(flags). Demo first (1), then the camera beat (0).
            """)
        XCTAssertEqual(out.announced, false, "the latch ends on the last event's origin")
    }

    /// 13 — REGRESSION. The latch survives the drain boundary: a second drain of the SAME
    /// origin adds no flag. Without this the once-per-change rule would hold only inside a
    /// single 100 ms tick, which is not a rule at all at strap rates.
    func testASecondDrainOfTheSameOriginIsSilentAboutOrigin() {
        let out = built([beat(.fallback)], lastAnnounced: true)
        XCTAssertEqual(out.messages.map(\.address), [Self.beatAddress], """
            A repeat drain re-announced provenance (\(out.messages.map(\.address))). \
            The caller latches `announced`; matching state must produce nothing.
            """)
        XCTAssertEqual(out.announced, true)
    }

    /// 14 — **SPLIT: one counterweight assertion and one regression assertion**, and the
    /// header's GRADING block explains why they stay in one method. #245's silence law on the
    /// new path: an empty drain — the normal state, since events are sparse and the poll is
    /// 10 Hz — must emit NOTHING, not a bare flag describing no event.
    ///
    /// The MESSAGE assertions are the counterweight (green on the parent too: its inline loop
    /// simply sent nothing when the queue was empty) and are the executable form of the second
    /// rejected shape, "send it unconditionally". The `announced` assertions are a REGRESSION —
    /// the parent has no latch at all, so nothing there could preserve it across an empty
    /// drain. ⛔ THIS COMMENT FIRST CLAIMED THE WHOLE METHOD WAS A COUNTERWEIGHT, which the
    /// GRADING block above retracts; corrected here too, because a claim and its own
    /// refutation in one file is #425 and this file has already paid for it once.
    func testAnEmptyDrainSaysNothingAtAll() {
        let out = built([])
        XCTAssertTrue(out.messages.isEmpty, """
            An empty drain emitted \(out.messages.map(\.address)). The flag never travels \
            alone (claim 3, same law): a receiver must read absence as absence.
            """)
        XCTAssertNil(out.announced, "nothing announced, so nothing latched")

        let repeated = built([], lastAnnounced: false)
        XCTAssertTrue(repeated.messages.isEmpty, "an empty drain is silent whatever the latch")
        XCTAssertEqual(repeated.announced, false, "and it must not FORGET the latch either")
    }

    /// 16 — REGRESSION (#788). Every doc that LISTS a discrete event address must also say the
    /// events carry provenance. `docs/dev/VJ_BRIDGE.md` and `docs/architecture.html` described
    /// the flag with the BATCH rule only ("sent first in every tick that carries a value"), which
    /// was complete before #785 and became a half-truth the moment the event path got its own
    /// cadence — in the two tables an INTEGRATOR reads, which is the whole audience this family
    /// of slices exists for. An under-claim, not an over-claim, and it would never have shown up
    /// in a scan looking for false statements.
    ///
    /// ⭐ DIRECTORY-DRIVEN ON PURPOSE, and that is #787's lesson applied one cycle later. A named
    /// list of two files would have missed `docs/dev/FEATURE_MATRIX.md`, which also lists the
    /// event addresses — I only found the third file by running the sweep instead of trusting the
    /// two I had just edited. The corpus defines itself: any file under `docs/` that names
    /// `/echoelmusic/bio/event/` is in scope, whatever its extension or directory depth.
    ///
    /// ⚠️ #364: this does NOT mandate a wording. It asks only that a doc listing the event
    /// addresses mentions `/echoelmusic/bio/synthetic` somewhere, so a reader of that table
    /// learns the events are labelled at all. Removing provenance from the event path is a
    /// legitimate future decision — it turns this red, and the message says what to pull.
    func testEveryDocListingEventAddressesMentionsTheirProvenance() throws {
        let docs = try repoRoot().appendingPathComponent("docs")
        guard let walker = FileManager.default.enumerator(atPath: docs.path) else {
            return XCTFail("cannot walk docs/ — re-anchor this claim (#454)")
        }
        var listing: [String] = []
        var silent: [String] = []
        for case let rel as String in walker {
            guard rel.hasSuffix(".md") || rel.hasSuffix(".html") else { continue }
            guard let text = try? String(contentsOf: docs.appendingPathComponent(rel),
                                         encoding: .utf8) else { continue }
            guard text.contains("/echoelmusic/bio/event/") else { continue }
            listing.append(rel)
            if !text.contains(Self.provenance) { silent.append(rel) }
        }
        XCTAssertFalse(listing.isEmpty, """
            No file under docs/ names /echoelmusic/bio/event/ any more. That is not a pass — the \
            needle can no longer match its corpus (#454/#779). Re-anchor before trusting a green.
            """)
        XCTAssertTrue(silent.isEmpty, """
            \(silent.count) doc(s) list the discrete event addresses but never mention \
            \(Self.provenance): \(silent.joined(separator: ", ")).
            Since #785 those events ARE labelled — the flag goes immediately before the event it \
            describes and again only on a change of origin, latched across polls. A table that \
            lists the addresses and stays silent about it leaves an integrator believing a \
            simulator's heartbeat bang is indistinguishable from a body's, which is exactly the \
            gap #639 opened this family to close. If provenance was deliberately REMOVED from the \
            event path, this red is correct and the register above plus CLAUDE.md's OSC section \
            move in the SAME commit (#456).
            """)
    }

    /// 15 — COUNTERWEIGHT, the executable form of the FIRST rejected shape and the load-bearing
    /// one: appending provenance as an extra argument on `/bio/event/*` would break every
    /// integrator reading `[confidence, aux]`. Green on the parent by construction — the parent
    /// sent exactly these two floats — so it guards the decision rather than the defect.
    func testTheEventAddressesKeepTheirOldTwoFloatShape() {
        let out = built([beat(.fallback, confidence: 0.71, aux: 812)])
        guard let event = out.messages.first(where: { $0.address == Self.beatAddress }) else {
            return XCTFail("the heartbeat event vanished — re-anchor this case (#454)")
        }
        XCTAssertEqual(event.floats, [0.71, 812], """
            `\(Self.beatAddress)` carried \(event.floats). The published contract is exactly \
            [confidence, aux]; provenance is an ADDITIVE address, never a third argument.
            """)
    }
}
#endif
