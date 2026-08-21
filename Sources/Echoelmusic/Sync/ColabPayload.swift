// ColabPayload.swift
// Echoel — the wire format for Live Colabo (nearby peer-to-peer session sharing).
// Kept OUTSIDE the MultipeerConnectivity gate so it's pure Foundation/Codable and
// ci.yml can execute its round-trip test on Linux (MultipeerConnectivity is iOS-only).
// Forward-compatible (optional fields) so a newer sender never breaks an older receiver.

import Foundation

/// One person's live bio numbers for the side-by-side Colabo display
/// (kind "bio", ecosystem plan E5). Each person sees their OWN values next to
/// each other — never combined into a cross-person score (decision 2026-06-20:
/// no cross-person coherence readout; connected music-making yes, "group sync
/// score" no). `0` means "not available", mirroring `BioSampleFrame`.
public struct BioPeek: Codable, Sendable, Equatable {
    public var bpm: Float
    public var coherence: Float       // 0…1; 0 = not available
    public var hrvNormalized: Float   // 0…1
    public var breathRate: Float      // breaths/min; 0 = not available
    /// #629. Were these numbers MEASURED, or produced by the Demo source?
    ///
    /// `nil` means "the sender did not say" — an older build, which had no such field.
    /// It must render exactly like today (unmarked), never like `false`: reading a silent
    /// sender as "real" would be the same over-claim this field exists to end, only
    /// dressed as a default. `false` is a positive statement by a build that knows.
    ///
    /// ⚠️ THE DEMO IS NOT BLOCKED FROM THE WIRE, and that is deliberate. `BioEgressPolicy`
    /// admits `.fallback` (Echoel synthesises it itself; 5.1.3 is about what is read out of
    /// HealthKit), and this type's own `writable` doc already settles the shape of the
    /// choice: dropping the peek blanks the peer's row, which ASSERTS the network stopped —
    /// "the worse of the two lies". Rehearsing or teaching with the simulator is a real use.
    /// Mark it, do not silence it.
    ///
    /// ⚠️ Optional, so the synthesized `init(from:)` decodes it with `decodeIfPresent` and
    /// an older peer's payload still round-trips — the forward-compatibility promise in this
    /// file's header, kept rather than quoted.
    public var synthetic: Bool?

    /// ⚠️ NON-FINITE INPUT BECOMES `0` HERE, which is this type's own documented "not
    /// available" — a widening of the existing convention, not a silent rounding.
    ///
    /// #512. `ColabPayload.encoded()` is `try? JSONEncoder().encode(self)`, and
    /// `JSONEncoder`'s default `nonConformingFloatEncodingStrategy` is `.throw`. So ONE
    /// non-finite channel made the whole payload fail to encode, `try?` turned the throw
    /// into `nil`, and `send` returned having done nothing — for as long as the source kept
    /// producing it. On the peer's screen that is indistinguishable from the network going
    /// quiet, which since #508 blanks the row after eight missed sends: **a single bad rPPG
    /// sample took FOUR good numbers off someone else's display and kept them off.** The
    /// direction was safe; the cause was misreported, and nothing anywhere said so.
    ///
    /// ⭐ WHY COERCE PER CHANNEL RATHER THAN DROP THE PEEK. `bioLine` renders `0` as
    /// "— bpm" / "coherence not available", so a coerced channel reads as exactly what it
    /// is. Dropping the peek would blank the whole row, i.e. assert that the network
    /// stopped — false, and the worse of the two lies. Three good numbers and one dash is
    /// the honest report.
    ///
    /// ⚠️ IT SITS ON THE MEMBERWISE INIT, not inside `egressible(from:)`, because `BioPeek`
    /// is `public` with this init and a hand-built one reaches `encoded()` with nothing on
    /// the wire path to notice — the same hole #511 closed for PROVENANCE, closed here for
    /// FINITENESS. The two questions stay in two places on purpose (#416): one asks which
    /// source may leave the phone, the other whether a number can be written down at all.
    ///
    /// ⚠️ WHAT IT DOES NOT COVER, stated rather than implied. (a) The fields are `var`, so
    /// an assignment after init can put NaN back; no caller does today, and the receive
    /// side is non-finite-safe anyway (`bpm > 0` and `coherence > 0` are both false for
    /// NaN, and `PeerReading.live(at:)` reads a non-finite age as GONE). (b) The
    /// synthesized `init(from:)` bypasses this, which is tolerable only because
    /// `JSONDecoder`'s default non-conforming strategy is `.throw` as well — a decoded
    /// value that reached `inf` by MAGNITUDE alone would still slip past, and lands in the
    /// same already-safe display path. (c) The OTHER payload kind carries `Project`, i.e.
    /// `bpm`, `a4Hz`, a whole `SynthPatch` and every `Note`, through this exact encoder
    /// with this exact hazard. That is a wider slice and is registered, not smuggled in
    /// here — #512 fixes the channel that carries LIVE SENSOR data, which is the one this
    /// repo has already had to guard for non-finite input three times (#433/#434/#497).
    ///
    /// #629: `synthetic` defaults to `nil`, NOT to `false`. A hand-built peek — the exact
    /// hole the `egressible` factory below exists to narrow — then says "unknown" instead of
    /// claiming a measurement it cannot vouch for. The default is the honest direction, not
    /// the convenient one.
    public init(bpm: Float, coherence: Float, hrvNormalized: Float, breathRate: Float,
                synthetic: Bool? = nil) {
        self.bpm = Self.writable(bpm)
        self.coherence = Self.writable(coherence)
        self.hrvNormalized = Self.writable(hrvNormalized)
        self.breathRate = Self.writable(breathRate)
        self.synthetic = synthetic
    }

    /// `0` — this type's "not available" — for anything JSON cannot carry. Deliberately NOT
    /// a clamp to a plausible range: narrowing a FINITE reading here would invent a number
    /// the body never produced, the mistake #424/#426/#433 each had to undo. It answers one
    /// question only: can this be written down.
    private static func writable(_ v: Float) -> Float { v.isFinite ? v : 0 }

    /// The ONE projection from a measured frame to the four numbers a peer sees —
    /// and the ONE place App Store 5.1.3 is decided for the peer path. Returns `nil`
    /// when this frame's source may not leave the device.
    ///
    /// ⭐ WHY IT IS A FACTORY AND NOT A GUARD AT THE CALL SITE. Until #511 the rule
    /// lived as a `&&` inside `LiveColaboView`'s stream loop, and `sendBio` took an
    /// already-built `BioPeek` — a value that carries NO source, so the send could not
    /// have re-checked even if it wanted to. `MultipeerSession.sendBio`'s own doc
    /// registered that as a follow-up ("moving it would need this signature to take the
    /// frame rather than the peek"). Two things made it worth doing rather than leaving
    /// registered: (a) `BioPeek` is `public` with a memberwise `init`, so ANY future
    /// caller could hand-build one and send it, with nothing on the wire path to notice;
    /// (b) #508 had already IDENTIFIED the obvious later cleanup — *the frame is fresh
    /// now, drop the guard* — and named it as a hazard, in two places: an ⚠️ prohibition
    /// on the call site itself ("dropping this guard because the frame is now fresh would
    /// ship the exact 5.1.3 violation the network senders forbid") and a counterweight
    /// test written to block it. #511 does not disagree with that warning; it removes the
    /// POSSIBILITY instead of relying on a reader heeding it. Freshness is not provenance,
    /// and a 5.1.3 violation is not a bug you find in a hearing test; it is a rejection.
    ///
    /// ⛔ AND THE FIRST DRAFT OF THIS PARAGRAPH SAID THE OPPOSITE — in three artefacts at
    /// once (here, the call site, the commit message). It read "#508 wrote the obvious
    /// later cleanup into that very call site", which frames the author of the
    /// prohibition as its proposer. A future session reading it would learn that #508
    /// endorsed dropping the guard — precisely the belief the original comment existed to
    /// prevent. Found by a reviewer, verified against `git show b098d97:` before
    /// correcting. **A comment that misattributes a decision is worse than one that is
    /// merely stale: it cannot be caught by re-measuring, only by re-reading the source
    /// it cites.**
    ///
    /// ⚠️ It CALLS `BioEgressPolicy` rather than re-stating the source list. That is the
    /// #186 lesson, written in `BioEgressPolicy`'s own header: the first cut of the event
    /// gate inlined the rule and its test re-implemented it, so the test passed with the
    /// production guard deleted — "a tautology wearing a regression test's clothes".
    ///
    /// ⚠️ Freshness is deliberately NOT decided here. `LiveColaboView` asks
    /// `bus.usableBio()` before calling, because "is this measurement still current" is a
    /// question about the BUS and its per-source window, while this asks only "may this
    /// source's numbers leave the phone". Folding both into one function would make a
    /// frozen-frame fix and a compliance rule share a single `if`, which is how one of
    /// them gets dropped while the other is being edited.
    public static func egressible(from frame: BioSampleFrame) -> BioPeek? {
        guard BioEgressPolicy.allowsEgress(frame.source) else { return nil }
        return BioPeek(bpm: frame.heartRateBPM,
                       coherence: frame.coherence,
                       hrvNormalized: frame.hrvNormalized,
                       breathRate: frame.breathRate,
                       // #629 — the SAME projection point that decides 5.1.3 also decides
                       // provenance, for the same reason it was moved here in #511: this is
                       // the only place that still HAS the frame. `BioPeek` carries no
                       // source, so nothing downstream could recover this if it were asked
                       // one call later. `.fallback` is the one synthetic source the policy
                       // above admits, so the question is exactly this comparison.
                       synthetic: frame.source.isSynthetic)
    }
}

/// One peer's last reading, and WHEN it arrived HERE.
///
/// #508. `BioPeek` carries no time at all, so a receiver holding one cannot tell a peer
/// who is still breathing into their phone from a peer whose phone went into a pocket
/// ten minutes ago — the numbers just stand there, perfectly steady, on someone else's
/// screen. That is #503/#507's defect on the one surface where the stale number belongs
/// to a DIFFERENT PERSON, and that is what makes it worse here: your own held pulse is
/// at least yours, while a held peer pulse is a claim about a body you cannot see.
///
/// ⭐ THE STAMP IS ARRIVAL, NEVER A SENDER FIELD, and that is the load-bearing choice.
/// A `sentAt` on `BioPeek` would need a wire change, would be blank from every older
/// sender, and — the part that decides it — could not report the failures that actually
/// happen: a dropped Wi-Fi link, a backgrounded app, a peer that crashed. A sender
/// cannot tell you that it stopped sending. Only the receiver can notice.
///
/// ⚠️ The stamp lives WITH the value rather than in a parallel `[String: TimeInterval]`
/// (#416): two dictionaries would be two things to clear on every disconnect and stop
/// path, and the day one of them is missed the row lies again.
public struct PeerReading: Sendable, Equatable {

    /// How often a sharing peer sends one reading. ONE definition: `LiveColaboView`'s
    /// stream loop sleeps for exactly this, and `staleAfter` below is DERIVED from it,
    /// so changing the cadence moves the window with it instead of leaving one tuned
    /// for a rate nobody sends any more.
    public static let sendInterval: TimeInterval = 0.4

    /// Silence longer than this stops a row claiming a live peer. Derived: eight
    /// consecutive missed sends. The transport is deliberately `.unreliable` (a lost
    /// telemetry frame is worthless a moment later), so single drops are ordinary and
    /// a two-frame window would make every row flicker on normal Wi-Fi jitter.
    ///
    /// ⚠️ It is NOT a copy of `BioSource.freshnessWindow`, deliberately: it answers a
    /// DIFFERENT question. The sender already applied the freshness window to its own
    /// body before it sent anything; this window asks whether the NETWORK is still
    /// delivering. Reusing the 6 s here would double-count one question and answer the
    /// other never. The honest total latency is therefore the sum: up to the sender's
    /// own window, plus this one, from the last real measurement to a blanked row.
    public static let staleAfter: TimeInterval = sendInterval * 8

    public let peek: BioPeek
    /// `CFAbsoluteTimeGetCurrent()` at the moment this frame arrived on THIS device —
    /// never a sender clock. Two phones are not clock-synchronised.
    public let arrivedAt: TimeInterval

    public init(peek: BioPeek, arrivedAt: TimeInterval) {
        self.peek = peek
        self.arrivedAt = arrivedAt
    }

    /// The reading while it is still arriving; `nil` once the peer has gone quiet.
    ///
    /// The skew tolerance is not invented here — it is the same allowance
    /// `EngineBus.usableBio()` applies to its own frames, asked the same way rather
    /// than minted a second time (#416/#426). Non-finite inputs make every comparison
    /// false and therefore read as GONE: the safe direction, because blanking a row is
    /// cheaper than asserting a live person from a number nothing can date.
    ///
    /// ⛔ AND UNTIL #545 THAT PARAGRAPH WAS FALSE SEVEN LINES ABOVE ITS OWN REFUTATION:
    /// it said "asked the same way rather than minted a second time" while the guard
    /// below wrote `-1` as a literal — there was no constant to ask. A claim and its own
    /// refutation inside one declaration (#425), and the more dangerous shape of it,
    /// because the claim is the one a reviewer would have checked FOR. It now asks
    /// `BioSource.futureSkewTolerance`, and the sentence is true.
    ///
    /// ⚠️ BOTH OPERANDS ARE LOCAL, so this is skew and not network delay:
    /// `MultipeerSession` stamps `arrivedAt` with the RECEIVER's clock on delivery. Do
    /// not "keep a second literal because two phones are not clock-synchronised" — that
    /// rationale sounds right, is wrong here, and would read as a do-not-delete note.
    public func live(at now: TimeInterval) -> BioPeek? {
        let age = now - arrivedAt
        guard age <= Self.staleAfter,
              age >= -BioSource.futureSkewTolerance else { return nil }
        return peek
    }
}

public struct ColabPayload: Codable, Sendable, Equatable {
    public var kind: String          // "session" | "bio"; reserved: "tempo", "chat"…
    public var senderName: String
    public var project: Project?
    /// Live bio reading (kind "bio"). Optional so older receivers ignore it.
    public var bio: BioPeek?

    public init(kind: String, senderName: String, project: Project? = nil, bio: BioPeek? = nil) {
        self.kind = kind; self.senderName = senderName; self.project = project; self.bio = bio
    }

    /// Encode, letting the encoder's error out.
    ///
    /// ⛔ WHY THE THROWING FORM EXISTS (#518). `encoded()` is a `try?`, so it answers
    /// "did it work" and destroys "why not". For the bio stream that is the right
    /// trade — a lost telemetry frame is worthless a moment later, and logging one
    /// per drop at `PeerReading.sendInterval` would flood. For the SESSION share it
    /// is not: that failure is terminal for the user's tap, and the encoder's
    /// `codingPath` names the FIELD that could not be written — which is the whole
    /// value of keeping it (#514's substantive half, on the same `Project`).
    ///
    /// ⭐ ONE DEFINITION (#416). `encoded()` is now this method behind a `try?`, so
    /// there is a single answer to "how does a `ColabPayload` become bytes". Do NOT
    /// give the share path its own `JSONEncoder()` — a second construction is a
    /// second place for a future `outputFormatting`/`dateEncodingStrategy` to be set
    /// on one wire path and not the other.
    ///
    /// ⚠️ THE WIRE FORMAT IS UNCHANGED. Default `JSONEncoder`, as before; in
    /// particular `nonConformingFloatEncodingStrategy` stays `.throw`, which is what
    /// makes a NaN a reportable failure rather than a silently-substituted number
    /// (#512 pinned that, and it must keep failing here for #518 to have anything
    /// to report).
    public func encodedThrowing() throws -> Data { try JSONEncoder().encode(self) }

    public func encoded() -> Data? { try? encodedThrowing() }
    public static func decode(_ data: Data) -> ColabPayload? {
        try? JSONDecoder().decode(ColabPayload.self, from: data)
    }

    /// Replace the sender's CLAIM about who it is with the transport's FACT.
    ///
    /// ⛔ WHY THIS EXISTS (#517). `senderName` is a field the sender writes into the JSON.
    /// `MCSessionDelegate.session(_:didReceive:fromPeer:)` hands over the AUTHENTICATED
    /// `MCPeerID` alongside the bytes — and `handleData` dropped it on the floor, then
    /// keyed and displayed everything by the field. Three consequences, all reachable
    /// today with two connected phones:
    ///
    ///  · **The row a bio reading lands in was chosen by the sender.** `peerReadings` is
    ///    keyed by name and `PeerReadingsSection` renders `peerReadings.keys` DIRECTLY,
    ///    so a peer could write into somebody else's row, or conjure a row for a name
    ///    that is not in the session at all.
    ///  · **Such a row can never be removed.** The disconnect path clears
    ///    `peerReadings[peerID.displayName]` — the TRANSPORT name. A reading filed under
    ///    a different key survives every disconnect for the rest of the process. That is
    ///    exactly the property #508 was built to give ("a quiet peer stops looking
    ///    alive"), defeated through the key rather than through the timestamp.
    ///  · **The import card names the claim.** `incomingCard(inc.senderName, project)`
    ///    asks "do you want to load this project from X" — and X was whatever the sender
    ///    typed. A peer could present as somebody you trust.
    ///
    /// ⭐ ONE WRITE, NOT FIVE (#416). The alternative was to fix each reader — the reading
    /// key, the status line, the import card — which is four places that must all keep
    /// remembering not to trust a field that is sitting right there. Replacing the claim
    /// with the fact AT THE BOUNDARY means no downstream reader can get it wrong, because
    /// after this call the field IS the transport name.
    ///
    /// ⚠️ THE WIRE IS UNCHANGED, said plainly: we still SEND `senderName` (from our own
    /// `myPeerID.displayName`), and an older peer still sends its own. This changes only
    /// what WE believe on receipt. Removing the field would be a protocol change and
    /// would break a peer running an older build.
    ///
    /// ⚠️ AND IT DOES NOT MAKE NAMES UNIQUE. `MCPeerID.displayName` comes from
    /// `UIDevice.current.name`, which on iOS 16+ returns the MODEL ("iPhone") unless the
    /// app holds the user-assigned-device-name entitlement — which Echoel does not declare
    /// (measured: zero hits for `user-assigned-device-name` across the entitlements). So
    /// three phones in a room are three peers all called "iPhone", and they still collide
    /// into one row. That is a SEPARATE defect about identity (#513); this one is about
    /// AUTHORITY, and fixing authority first is what makes a later unique name safe rather
    /// than merely different.
    public func attributed(to peerName: String) -> ColabPayload {
        var copy = self
        copy.senderName = peerName
        return copy
    }
}
