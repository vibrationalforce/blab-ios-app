import XCTest
@testable import Echoelmusic

/// #1006 — the light output addresses a rig, not a single lamp.
///
/// WHY IT EXISTS. Echoel's positioning names Installation · Event · Cinema · Theater, and the
/// light output wrote ONE 4-channel block starting at DMX slot 1 (8 in 16-bit). The two
/// protocols then failed differently, which is how it stayed unnoticed:
///
///   · Art-Net sends a SHORT packet — other fixtures hold their last values and look stuck
///   · sACN pads to a full 512 slots BY SPECIFICATION — so Echoel actively drove every other
///     fixture to zero. They went dark and stayed dark for as long as it streamed
///
/// The artist's only workaround was re-patching every lamp in the venue onto address 1.
///
/// ⚠️ WHAT IT DOES NOT CLAIM, and claim 4 is what keeps that honest: this is ADDRESSING, not
/// spatial differentiation. N fixtures get N IDENTICAL colours, because both DMX arms produce
/// exactly one global colour. Selling it as light moving through a room would be the class of
/// over-claim this repo keeps having to retract.
///
/// ⭐ THE ORDERING IS THE SAFETY PROPERTY, and claim 2 is the one to keep. `FlashGuard` slews
/// the dimmer and the colour channels on the ONE block; that is what makes the 3 Hz ceiling a
/// guarantee. Fanning BEFORE the slew would hand the guard N independent histories — same
/// maths, N times the state, one bug away from a rig that strobes on every lamp but the first.
///
/// ⚠️ HONEST GRADING, transcribed against both trees — and corrected before committing, for
/// the THIRD time in one session. Claims 1, 2, 3 and 4 are green on the worktree and red on
/// `HEAD`; claim 5 is the only one green on both. My draft header said 4 was the green-on-both
/// one, on the reasoning that what it FORBIDS (an over-claim about per-fixture colour) was
/// never there — true, and irrelevant: the claim asserts a caption that does not exist one
/// commit back, so it cannot pass there.
///
/// The pattern behind all three misses is now written down rather than re-learned: **a claim's
/// grading is decided by whether its NEEDLE exists on `HEAD`, not by whether its POINT is about
/// the past or the future.** Claim 5 is green on both because its needle is an ABSENCE
/// (`composeUniverse(` must not appear), and an absence can hold on both trees.
final class TheLightReachesMoreThanOneLampTests: XCTestCase {

    private static let artNet = "Sources/Echoelmusic/Sync/ArtNetSender.swift"
    private static let sacn = "Sources/Echoelmusic/Sync/SACNSender.swift"
    private static let patchbay = "Sources/Echoelmusic/Studio/PatchbayView.swift"

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

    // 1 — BEHAVIOURAL: the kernel, including the cases that would break a rig.
    func testTheFanRepeatsTheBlockWithoutOverlappingOrOverflowing() {
        let block: [UInt8] = [10, 20, 30, 40]

        XCTAssertEqual(DMXFixtureFan.fanned(block, count: 1, spacing: 0), block, """
            One fixture is not the identity. This is the SHIPPED default, so a difference \
            here means every existing rig's wire changed the day this landed.
            """)
        XCTAssertEqual(DMXFixtureFan.fanned(block, count: 0, spacing: 0), block,
                       "a nonsensical count must degrade to one fixture, not to an empty universe")
        XCTAssertEqual(DMXFixtureFan.fanned(block, count: 3, spacing: 0),
                       [10, 20, 30, 40, 10, 20, 30, 40, 10, 20, 30, 40], """
            Back-to-back fanning is wrong. Spacing 0 must mean the block's own width, which is \
            how a rig is patched by default.
            """)
        XCTAssertEqual(DMXFixtureFan.fanned(block, count: 2, spacing: 6),
                       [10, 20, 30, 40, 0, 0, 10, 20, 30, 40], """
            A wider spacing must leave the gap slots at zero. Echoel does not know what lives \
            between the fixtures; sending anything else there is a guess on someone's rig.
            """)
        XCTAssertEqual(DMXFixtureFan.fanned(block, count: 2, spacing: 2),
                       [10, 20, 30, 40, 10, 20, 30, 40], """
            A spacing NARROWER than the block must be floored to the block width. Without that \
            floor, fixtures overlap and each one writes its neighbour's channels — the block \
            width is the floor, not merely the default.
            """)

        let fanned = DMXFixtureFan.fanned(block, count: DMXFixtureFan.maxFixtures, spacing: 60)
        XCTAssertLessThanOrEqual(fanned.count, DMXFixtureFan.universeSlots, """
            The fan produced more than one universe (\(fanned.count) slots). A DMX universe is \
            512; anything past that is not a big packet, it is an invalid one.
            """)
        XCTAssertEqual(Array(fanned.prefix(4)), block,
                       "the first fixture must still be at the start of the universe")
    }

    // 2 — the ordering that keeps the flash ceiling a guarantee.
    func testTheFanRunsAfterTheSlewInBothSenders() throws {
        for file in [Self.artNet, Self.sacn] {
            let text = try source(file)
            guard let slew = text.range(of: "applySlewedColour("),
                  let fan = text.range(of: "DMXFixtureFan.fanned(channels") else {
                return XCTFail("""
                    \(file) no longer both slews and fans. If the fan is gone the rig is back \
                    to one lamp; if the slew is gone the 3 Hz ceiling is gone with it.
                    """)
            }
            XCTAssertLessThan(slew.lowerBound, fan.lowerBound, """
                \(file) fans the block BEFORE slewing it. `FlashGuard` smooths one block and \
                that is what makes the flash ceiling a guarantee — fanning first hands it N \
                independent histories, which is the same maths with N times the state and one \
                bug away from a rig that strobes on every lamp but the first.
                """)
        }
    }

    // 3 — the shipped default addresses exactly one fixture.
    func testBothSendersDefaultToASingleFixture() throws {
        for file in [Self.artNet, Self.sacn] {
            let text = try source(file)
            XCTAssertTrue(text.contains("public var fixtureCount: Int = 1"), """
                \(file) does not default to ONE fixture. Any other default changes what a \
                stranger's rig does on first open, which is the one thing a light output may \
                never do — and it would make this whole slice a behaviour change rather than \
                an addition.
                """)
            XCTAssertTrue(text.contains("public var fixtureSpacing: Int = 0"),
                          "\(file) does not default to back-to-back spacing")
        }
    }

    // 4 — COUNTERWEIGHT: the copy does not promise light moving through a room.
    func testTheCopySellsAddressingAndNotSpatialLight() throws {
        let text = try source(Self.patchbay)
        XCTAssertTrue(text.contains("every lamp shows the SAME colour"), """
            The Light section's caption no longer says the fixtures share one colour. Both DMX \
            arms produce exactly ONE global colour, so any wording that suggests per-fixture \
            variation — light travelling across a rig, the body moving through the room — is \
            an over-claim. Per-fixture variation needs a producer that exists nowhere in this \
            repo; when it exists, change the caption then.
            """)
    }

    // 5 — COUNTERWEIGHT: the fan does not sneak in through the doorless composer.
    func testNeitherSenderRoutesThroughTheDoorlessComposer() throws {
        for file in [Self.artNet, Self.sacn] {
            let text = try source(file)
            XCTAssertFalse(text.contains("composeUniverse("), """
                \(file) now calls `composeUniverse()`. That path re-applies its own master and \
                blackout and never passes through `FlashGuard.slewedDimmer` — so routing the \
                fan through it would double-apply the master AND drop the flash ceiling in one \
                move. It looks like reuse and is neither.
                """)
        }
    }
}
