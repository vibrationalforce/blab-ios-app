// MultipeerInvitationTests.swift
// Echoelmusic — Live Colabo consent (App Store audit 2026-07-16, 5.1.1/5.1.2):
// invitations are NEVER auto-accepted. These tests pin the pending-invitation
// state machine (one at a time, respond exactly once, stop() declines).

#if canImport(MultipeerConnectivity)
import XCTest
@testable import Echoelmusic

@MainActor
final class MultipeerInvitationTests: XCTestCase {

    func testInvitation_surfacesPending_andAcceptRespondsTrueOnce() {
        let colab = MultipeerSession()
        var answers: [Bool] = []
        colab.handleInvitation(from: "Aylin") { answers.append($0) }
        XCTAssertEqual(colab.pendingInvitation?.peerName, "Aylin", "invitation waits for the user")
        XCTAssertTrue(answers.isEmpty, "nothing is answered before the user decides")

        colab.respondToInvitation(accept: true)
        XCTAssertEqual(answers, [true])
        XCTAssertNil(colab.pendingInvitation, "card clears after the answer")

        colab.respondToInvitation(accept: true)   // no pending → must be a no-op
        XCTAssertEqual(answers, [true], "MC handler is answered exactly once")
    }

    func testInvitation_declineRespondsFalse() {
        let colab = MultipeerSession()
        var answers: [Bool] = []
        colab.handleInvitation(from: "Ben") { answers.append($0) }
        colab.respondToInvitation(accept: false)
        XCTAssertEqual(answers, [false])
        XCTAssertNil(colab.pendingInvitation)
    }

    func testNewerInvitation_declinesThePreviousPendingOne() {
        // An unanswered MC handler would dangle into the inviter's 20 s timeout —
        // a second invitation must resolve the first with a decline.
        let colab = MultipeerSession()
        var first: [Bool] = []
        var second: [Bool] = []
        colab.handleInvitation(from: "Aylin") { first.append($0) }
        colab.handleInvitation(from: "Ben") { second.append($0) }
        XCTAssertEqual(first, [false], "superseded invitation is declined, not dropped")
        XCTAssertEqual(colab.pendingInvitation?.peerName, "Ben")

        colab.respondToInvitation(accept: true)
        XCTAssertEqual(second, [true])
    }

    func testStop_declinesAPendingInvitation() {
        let colab = MultipeerSession()
        var answers: [Bool] = []
        colab.handleInvitation(from: "Aylin") { answers.append($0) }
        colab.stop()
        XCTAssertEqual(answers, [false], "stop() must not leave the MC handler dangling")
        XCTAssertNil(colab.pendingInvitation)
    }
}
#endif
