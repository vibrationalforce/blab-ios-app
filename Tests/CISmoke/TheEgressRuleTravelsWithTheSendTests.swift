//
//  TheEgressRuleTravelsWithTheSendTests.swift
//  Echoelmusic — CISmoke (#511)
//
//  ⚠️ LIMITS FIRST. Two of these assertions drive shipped code end to end: `BioPeek`,
//  `BioSampleFrame`, `BioSource` and `BioEgressPolicy` are all `public` Foundation-only
//  value types, so the 5.1.3 decision and the four-number projection really run here.
//  The other four are SOURCE SCANS — `MultipeerSession` lives behind
//  `#if canImport(MultipeerConnectivity)` and needs a real MC stack, and the send loop is
//  a `.task` on a `View` this bundle cannot instantiate. **That two phones actually stop
//  exchanging a HealthKit-sourced pulse is a two-device check and OPEN.**
//
//  ⭐ WHAT THIS IS ABOUT. App Store 5.1.3: data read out of the HealthKit store may not be
//  shared with third parties. Echoel's network senders have honored that for a long time
//  (`OSCSender`, `ADMOSCSender`, `ArtNetSender` each ask `BioEgressPolicy`). The PEER path
//  did too — but the rule lived as a `&&` inside `LiveColaboView`'s stream loop, because
//  `sendBio` took an already-built `BioPeek` and a peek carries no source. #511 moved it
//  into the send. This file exists so it cannot move back out.
//
//  ⭐ THE POLICY IS ASKED, NOT RESTATED — and then ALSO pinned. Half of these assertions
//  derive the expectation from `BioEgressPolicy.allowsEgress` so the factory can never
//  drift from the rule; on their own they would be a tautology (`BioEgressPolicy`'s own
//  header records exactly that failure at #186: "a tautology wearing a regression test's
//  clothes"). The other half hardcodes the three refused sources, because a policy that
//  quietly widened to allow everything would keep the derived half green. Neither half
//  alone is worth anything.
//
//  ⚠️ HONEST GRADING (#433), and it is the #464 situation said plainly: this file CANNOT
//  BE GRADED against the parent tree at all — every behavioural case names
//  `BioPeek.egressible(from:)`, which does not exist there, so the bundle does not compile
//  and NO assertion has a verdict. Hand-transcribed instead (Python rebuild of
//  `SourceText.codeOnly` plus the brace matcher, run against `git show b098d97:` and the
//  worktree, every needle driven separately). **FOUR of the five scan needles are red on the
//  parent — and they are TWO findings, not four.** (1) The signature took a `BioPeek`: that
//  makes the signature needle red for its stated reason AND makes the body needle red by
//  ANCHOR ABSENCE, which is one absence reported twice (#486), not a second catch. (2) The
//  call site hand-built a peek: that makes `colab.sendBio(f)` absent AND `sendBio(BioPeek`
//  present — two sides of one fact, counted once. **ONE** needle is green on both trees, a
//  true counterweight: no peek-shaped send in `MultipeerSession`. The four behavioural cases
//  drive a symbol this very commit adds and could never have been red; booking them as
//  regressions would be the #433 defect in the flattering direction.
//
//  ⚠️ `SourceText.codeOnly` is PROPHYLACTIC here, and that is MEASURED rather than assumed:
//  raw versus stripped differ on **0 of 5** needle verdicts, on BOTH trees. This sentence has
//  now been written three ways and the history is the point (#484/#485 each had to retract
//  the stronger claim once, #486 twice): the first draft claimed prophylactic without running
//  the numbers, the second measured **1 of 6** and called the stripper load-bearing — and
//  that one flipping needle was the freshness counterweight, which is deliberately no longer
//  in this file (see the ⛔ block below; it belongs to #508's guard, where the stripper still
//  IS load-bearing for exactly that reason).
//
//  ⚠️ It stays anyway, and not only because #453 gave the whole blocking bundle one
//  definition: the negative needle is ONE WORD from colliding with its own obituary.
//  `MultipeerSession`'s doc says "do NOT add a `sendBio(_ peek: BioPeek)` overload", which
//  does not contain `sendBio(BioPeek` — write that retraction without the argument label and
//  this guard goes RED ON CORRECT CODE. The #486/#491 collision waiting to happen: this repo
//  writes down what it removed, so a negative scan eventually lands on its own gravestone.
//

import XCTest
@testable import Echoelmusic

final class TheEgressRuleTravelsWithTheSendTests: XCTestCase {

    // MARK: - The rule itself (real behaviour, end to end)

    /// The factory agrees with the policy on EVERY source — it asks rather than restates.
    func testTheFactoryFollowsThePolicyForEverySource() {
        for source in allBioSources {
            let peek = BioPeek.egressible(from: frame(source: source))
            XCTAssertEqual(peek != nil, BioEgressPolicy.allowsEgress(source), """
                `BioPeek.egressible(from:)` disagrees with `BioEgressPolicy.allowsEgress` \
                for \(source). The factory must ASK the policy, never keep its own copy of \
                the source list (#186, #416).
                """)
        }
    }

    /// …and the three Health-store-derived sources are refused, stated outright. Without
    /// this, a policy that widened to `return true` everywhere would keep the check above
    /// green while shipping the 5.1.3 violation.
    func testHealthDerivedSourcesCannotReachAPeer() {
        for source in [BioSource.healthKit, .watch, .oura] {
            XCTAssertNil(BioPeek.egressible(from: frame(source: source)), """
                A frame sourced from \(source) produced a peer payload. App Store 5.1.3: \
                data obtained from the HealthKit store may not be shared with third \
                parties, and a nearby peer is a third party.
                """)
        }
    }

    /// An allowed frame's four numbers travel verbatim — the projection is the one place
    /// they are derived, so it must not quietly re-scale or substitute anything.
    func testAnAllowedFrameTravelsWithItsOwnNumbers() throws {
        let f = frame(source: .cameraPPG, bpm: 61.5, coherence: 0.42,
                      hrv: 0.37, breath: 5.8)
        let peek = try XCTUnwrap(BioPeek.egressible(from: f))
        XCTAssertEqual(peek.bpm, 61.5)
        XCTAssertEqual(peek.coherence, 0.42)
        XCTAssertEqual(peek.hrvNormalized, 0.37)
        XCTAssertEqual(peek.breathRate, 5.8)
    }

    /// COUNTERWEIGHT. `BioSource` is not `CaseIterable`, so the sweep above walks a list
    /// written by hand. Adding a case without extending that list would leave the new
    /// source unswept — and a new sensor is exactly when someone must decide, on purpose,
    /// whether its numbers may leave the phone.
    func testANewBioSourceForcesAnEgressDecision() {
        for raw in UInt8(0)...UInt8(allBioSources.count - 1) {
            XCTAssertNotNil(BioSource(rawValue: raw),
                            "raw value \(raw) has no case — the hand-written list is stale.")
        }
        XCTAssertNil(BioSource(rawValue: UInt8(allBioSources.count)), """
            `BioSource` gained a case. Add it to `allBioSources` here AND decide in \
            `BioEgressPolicy.allowsEgress` whether it may leave the device (5.1.3) — the \
            default of "it compiled" is not a decision.
            """)
    }

    // MARK: - The wiring (source scans)

    /// The send takes the FRAME and applies the rule itself. Both halves matter: a
    /// signature that took a peek could not check anything (that was the defect), and a
    /// frame-shaped signature that forgot to ask would be worse than the old call site,
    /// because it looks safe.
    func testTheSendAsksTheRuleItself() throws {
        let text = try source("Sources/Echoelmusic/Sync/MultipeerSession.swift")
        XCTAssertTrue(text.contains("public func sendBio(_ frame: BioSampleFrame)"), """
            `sendBio` no longer takes a `BioSampleFrame`. A `BioPeek` carries no source, so \
            a peek-shaped signature makes the 5.1.3 gate impossible to apply here and pushes \
            it back out to whoever remembers (#511).
            """)
        let body = try declarationBody(of: "public func sendBio(_ frame: BioSampleFrame) {",
                                       in: "Sources/Echoelmusic/Sync/MultipeerSession.swift")
        XCTAssertTrue(body.contains("BioPeek.egressible(from: frame)"), """
            `sendBio` does not ask `BioPeek.egressible(from:)`. Taking the frame is only \
            half of it — the point is that the send APPLIES the rule.
            """)
    }

    /// COUNTERWEIGHT (#343). Every assertion above would stay green on a tree that deleted
    /// the stream loop entirely: nothing shared, nothing leaked, all rules obeyed. So pin
    /// that the view still sends.
    func testTheStreamLoopStillSharesTheOwnReading() throws {
        let text = try source("Sources/Echoelmusic/Studio/LiveColaboView.swift")
        XCTAssertTrue(text.contains("colab.sendBio(f)"), """
            `LiveColaboView` no longer streams the own bio reading to peers. If sharing was \
            removed on purpose, delete this assertion in the same commit — do not let a \
            compliance guard stand in for a feature that is gone.
            """)
    }

    // ⛔ THE FRESHNESS COUNTERWEIGHT IS DELIBERATELY NOT HERE, and the first draft of this file
    // had it. #508 fixed a DIFFERENT half of the same line — the loop read the raw,
    // never-cleared `bus.latestBio` and re-encoded a frozen frame onto other people's screens
    // for the rest of the session — and `AQuietPeerStopsLookingAliveTests` already pins both
    // halves of that (`bus.usableBio()` present, `bus.latestBio` absent) as its own claim 1.
    // Restating them here would be a second, weaker copy of a live assertion: the #416 defect,
    // and the exact thing CLAUDE.md warns about for guards that sit next to each other.
    //
    // ⚠️ The division is by SUBJECT, not by file convenience. #508 owns "is this reading still
    // current"; #511 owns "may this source's numbers leave the phone at all". They meet on one
    // line of source and answer different questions — which is the whole reason #511 moved one
    // of them out of that line and left the other in.

    /// COUNTERWEIGHT. The convenience overload is the whole hole: `BioPeek` is `public` with
    /// a memberwise `init`, so anyone could hand-build one and send it with no source ever
    /// consulted.
    func testNoPeekShapedSendCameBack() throws {
        for path in ["Sources/Echoelmusic/Sync/MultipeerSession.swift",
                     "Sources/Echoelmusic/Studio/LiveColaboView.swift"] {
            let text = try source(path)
            XCTAssertFalse(text.contains("sendBio(BioPeek"), """
                \(path) sends a hand-built `BioPeek`. That bypasses the 5.1.3 gate by \
                construction — the peek has no source for anyone downstream to check.
                """)
        }
    }

    // MARK: - Fixtures

    /// Hand-written because `BioSource` is deliberately not `CaseIterable` (its raw values
    /// are persisted). `testANewBioSourceForcesAnEgressDecision` keeps this honest.
    private let allBioSources: [BioSource] = [
        .fallback, .healthKit, .oura, .ble, .watch, .cameraPPG, .faceCam
    ]

    private func frame(source: BioSource,
                       bpm: Float = 70,
                       coherence: Float = 0.5,
                       hrv: Float = 0.4,
                       breath: Float = 6) -> BioSampleFrame {
        BioSampleFrame(timestamp: 1000,
                       heartRateBPM: bpm,
                       hrvNormalized: hrv,
                       breathRate: breath,
                       breathPhase: 0.5,
                       coherence: coherence,
                       motionEnergy: 0,
                       source: source)
    }

    // MARK: - Source access (house template)

    private struct EgressAnchorMissing: Error { let reason: String }

    /// Directory-gated, never per-file (#475): a `fileExists` bracket around each read turns
    /// the very catastrophe this file guards against into a green SKIP.
    private func source(_ relativePath: String) throws -> String {
        let here = URL(fileURLWithPath: #filePath)
        let root = here.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources").path)
        else { throw XCTSkip("source tree not present under \(root.path)") }
        let path = root.appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: path.path) else {
            throw EgressAnchorMissing(reason: """
                \(relativePath) is missing while the tree is present — it was renamed or \
                moved. Re-anchor this scan; do not let it skip (#454).
                """)
        }
        return SourceText.codeOnly(try String(contentsOf: path, encoding: .utf8))
    }

    /// The brace-matched body following `key`, which must end in its opening brace.
    private func declarationBody(of key: String, in relativePath: String) throws -> String {
        let text = try source(relativePath)
        guard let start = text.range(of: key) else {
            throw EgressAnchorMissing(reason: """
                \(relativePath) no longer declares `\(key)`. This scan is anchored on it; \
                re-anchor rather than deleting the assertion.
                """)
        }
        var depth = 0
        var index = text.index(before: start.upperBound)   // the opening brace itself
        while index < text.endIndex {
            if text[index] == "{" { depth += 1 }
            if text[index] == "}" {
                depth -= 1
                if depth == 0 { return String(text[start.upperBound..<index]) }
            }
            index = text.index(after: index)
        }
        throw EgressAnchorMissing(reason: "Unbalanced braces after `\(key)` in \(relativePath).")
    }
}
