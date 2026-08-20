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
// KIND (§1): **END-TO-END BEHAVIOUR**, all eight claims. `OSCSender.bioMessages(for:)` is
// `nonisolated static`, and `BioSampleFrame` / `BioSource` / `BioEgressPolicy` are public
// Foundation-only value types, so this bundle drives the shipped producer and reads its real
// output. No source-text scanning and no needles anywhere in this file. What stays a DEVICE
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
// ⚠️ #364: a DIFFERENT provenance shape is not forbidden. A richer per-source address, a
// bundle, or a return channel would all satisfy the law and turn claims 1/2/4/8 red — that is
// the moment to rewrite this file. What is forbidden silently is a `.fallback` frame's values
// reaching the wire with nothing that says so.
//
// ⚠️ STILL OPEN and deliberately NOT solved here, because each needs its own decision:
//   · **ADM-OSC** (`/adm/obj/{n}/*`) is a PUBLISHED STANDARD address space owned by someone
//     else. Inventing `/adm/obj/n/synthetic` inside it would pollute that namespace, which is
//     the opposite of the open-standards posture this slice serves. It needs a decision about
//     WHERE such a flag belongs, not a quick append.
//   · **Art-Net and sACN** carry DMX and are the honest gap in this family. ⛔ THE FIRST DRAFT
//     CALLED THIS "a genuine cannot — no metadata room at all", AND THAT IS FALSE. A DMX
//     universe is 512 slots; `ArtNetSender.dmxChannels` uses FOUR (dimmer + R + G + B), eight
//     at 16-bit. Over five hundred are free. What is missing is a CONVENTION — a slot a desk
//     would have to be patched to read, which is a very different (and weaker) argument than
//     an impossibility, and one a lighting designer could reasonably reject. Writing "cannot"
//     where the truth is "nobody has designed it" is the same over-claim this whole family of
//     slices exists to remove, one level up.
//   · The discrete-event path (`/echoelmusic/bio/event/*`) carries `[confidence, aux]` and is
//     also unlabelled. It goes through `drainAndSendEvents`, not `bioMessages`, so it is a
//     separate edit with a separate ordering question.
//
// ⚠️ THE FOUNDER GATE THIS SLICE RETRACTED, stated here because a retraction that only lives in
// a commit message is not written down. `BioSimulator`'s header registered "whether to add …
// a synthetic marker on the OSC egress" as **a founder question (#462)**. #639 answers the OSC
// half unilaterally, and the reasons are on the record: the sentence bundled two decisions, the
// screen half was already shipped without an ask (#627), and this one is additive, reversible
// and breaks no published contract. The three halves it does NOT answer (ADM-OSC, DMX, events)
// stay registered as open, above. If the founder wants the flag gone, deleting the `insert`
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
}
#endif
