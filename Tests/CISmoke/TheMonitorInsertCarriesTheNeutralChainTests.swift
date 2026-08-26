// TheMonitorInsertCarriesTheNeutralChainTests — pins #832 (V1a) + #839 (V1b-1).
//
// THE SLICES (decisions.csv:398/450): V1a proved the AUAudioUnit render CONTRACT with
// an EMPTY pass-through insert between `monitorMixer` and `masterMixer` — and the
// founder's v10.79.424 logs show `insert in` on device. V1b-1 mounts the mic-owned
// `EchoelFXChain` inside that render block, NEUTRAL: every stage flag explicitly off,
// so the output stays bit-identical while the chain's DSP cost runs on device for the
// first time. #841 (V1b-2) opened the HARMONIZER's door — runtime preset via ONE
// apply path (TheHarmonyVoicesReachTheSingersDoorTests pins it); the DEFAULTS this
// file pins stay all-off, so claim 4's count remains the law: a stage sounds only
// after the singer acts, never because a default drifted.
//
// (This file was `TheMonitorInsertIsAnEmptyPassThroughTests` until #839 — renamed
// because after V1b-1 the insert is NOT empty, and a guard whose name states a
// falsehood is the #374 defect. Claims 1–2 survive the rename UNCHANGED in meaning:
// a neutral chain is identity by construction, so bit-exactness still holds and now
// proves MORE — the chain really is neutral, not merely absent.)
//
// KINDS (§1), per test:
// · tests 1–2 are END-TO-END BEHAVIOUR — they run the production factory and the real
//   render block (WITH the chain in it since #839) on this host and compare samples.
// · tests 3–5 are SOURCE-TEXT SCANS over AudioEngine.swift / MonitorInsertAU.swift /
//   EchoelFXChain.swift.
// · Whether the neutral chain is audible-neutral and CPU-invisible on a REAL route is
//   a DEVICE PROBE — open, answered by the next founder log (unchanged monitoring
//   sound, no crackle while monitoring runs).
//
// GRADING (§3, for the #839 slice against its parent): claims 1–2 and 3 and 5 are
// COUNTERWEIGHTS — green on both trees (the neutral chain preserves bit-exactness, and
// the mount/breadcrumb sites are untouched). Claim 4 is the flipped tripwire: on the
// parent its needles (`EchoelFXChain(`, `processInPlace`, the 15 `= false` lines) are
// absent — ONE absence, reported once (#486). The all-off count uses a DERIVED
// denominator (the chain's own `…Enabled` declarations, #416), so it could never have
// been green-by-accident on the parent. Driven in Python against parent and worktree
// before push.
//
// #364: nothing here forbids V1b-2. Turning a stage ON for the voice will red claim 4's
// all-off count BY DESIGN — its message names the prose to move in the same commit.
//
// #840 ADDENDUM (same cycle family): the chain rate now FOLLOWS the negotiated bus
// format — a rate mismatch rebuilds the neutral chain through the one factory, held in
// a swap box the render block captures (so a block the host fetched early still sees
// the swap). Claim 4 grew two needles for it; on #840's parent they are red as ONE
// absence (#486) while everything else in this file is a counterweight, green on both.

import Foundation
import XCTest
#if canImport(AVFoundation)
import AVFoundation
import AudioToolbox
#endif
@testable import Echoelmusic

final class TheMonitorInsertCarriesTheNeutralChainTests: XCTestCase {

    // MARK: - helpers

    private func code(_ repoRelative: String) -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent(repoRelative)
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            XCTFail("ANCHOR MISSING: \(repoRelative) could not be read — fail, not skip (§4)")
            return ""
        }
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    #if canImport(AVFoundation)
    /// Runs the production render block once over a known ramp and returns the output
    /// samples. `hostProvidesBuffers == false` exercises the nil-`mData` branch of the
    /// contract (the unit must supply its scratch). The buffer list is hand-built —
    /// hijacking an `AVAudioPCMBuffer`'s list to nil out `mData` would fight that
    /// type's own memory bookkeeping.
    @MainActor
    private func renderOnce(hostProvidesBuffers: Bool) async throws -> (input: [[Float]], output: [[Float]]) {
        var instantiated: AVAudioUnit?
        let landed = expectation(description: "factory instantiation")
        MonitorInsertFactory.instantiate { unit, _ in
            instantiated = unit
            landed.fulfill()
        }
        await fulfillment(of: [landed], timeout: 10)
        let unit = try XCTUnwrap(instantiated, """
            The production factory failed to instantiate the insert ON THIS HOST. The app \
            degrades gracefully (monitoring builds without the insert), but the vocal \
            chain's deliverable is a working AU contract — a nil here means the contract \
            is broken everywhere.
            """).auAudioUnit
        XCTAssertTrue(unit is MonitorInsertAudioUnit, """
            The factory's component description resolved to some OTHER audio unit — the \
            registration is not reaching our subclass, so the node in the monitor chain is \
            not the insert this file certifies.
            """)
        try unit.allocateRenderResources()
        defer { unit.deallocateRenderResources() }

        let frames = 256
        let frameCount = AUAudioFrameCount(frames)
        let ramp: [[Float]] = (0..<2).map { channel in
            (0..<frames).map { Float($0) * 0.001 + Float(channel) }
        }
        let pull: AURenderPullInputBlock = { _, _, pullFrames, _, abl in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            for b in 0..<buffers.count {
                guard let base = buffers[b].mData?.assumingMemoryBound(to: Float.self) else {
                    return kAudioUnitErr_Uninitialized
                }
                for i in 0..<Int(pullFrames) { base[i] = Float(i) * 0.001 + Float(b) }
            }
            return noErr
        }

        // Hand-built two-buffer AudioBufferList (the canonical size formula: the struct
        // holds ONE inline AudioBuffer, each further channel appends another).
        let listBytes = MemoryLayout<AudioBufferList>.size + MemoryLayout<AudioBuffer>.size
        let listMemory = UnsafeMutableRawPointer.allocate(
            byteCount: listBytes, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { listMemory.deallocate() }
        let list = listMemory.bindMemory(to: AudioBufferList.self, capacity: 1)
        list.pointee.mNumberBuffers = 2
        let hostLeft = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        let hostRight = UnsafeMutablePointer<Float>.allocate(capacity: frames)
        defer {
            hostLeft.deallocate()
            hostRight.deallocate()
        }
        let byteSize = UInt32(frames * MemoryLayout<Float>.stride)
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        buffers[0] = AudioBuffer(
            mNumberChannels: 1, mDataByteSize: byteSize,
            mData: hostProvidesBuffers ? UnsafeMutableRawPointer(hostLeft) : nil)
        buffers[1] = AudioBuffer(
            mNumberChannels: 1, mDataByteSize: byteSize,
            mData: hostProvidesBuffers ? UnsafeMutableRawPointer(hostRight) : nil)

        var timestamp = AudioTimeStamp()
        timestamp.mSampleTime = 0
        timestamp.mFlags = .sampleTimeValid
        var flags = AudioUnitRenderActionFlags()
        let render = unit.internalRenderBlock
        let status = render(&flags, &timestamp, frameCount, 0, list, nil, pull)
        XCTAssertEqual(status, noErr, """
            The render block returned \(status) instead of noErr — the insert contract \
            failed on the \(hostProvidesBuffers ? "host-buffer" : "nil-mData") branch.
            """)

        var output: [[Float]] = []
        for b in 0..<buffers.count {
            guard let base = buffers[b].mData?.assumingMemoryBound(to: Float.self) else {
                XCTFail("output buffer \(b) has no data after render — the unit neither used "
                        + "the host buffer nor supplied its scratch")
                return (ramp, [])
            }
            output.append((0..<frames).map { base[$0] })
        }
        return (ramp, output)
    }

    // MARK: - 1. END-TO-END: the NEUTRAL chain is bit-exact identity (host buffers)

    @MainActor
    func testTheRenderBlockPassesTheInputThroughBitExactly() async throws {
        let (input, output) = try await renderOnce(hostProvidesBuffers: true)
        guard output.count == input.count else { return }
        for channel in 0..<input.count {
            // Exactness, not tolerance (#442): with every stage flag off,
            // `processStereo` returns its input — one `if` per stage, no unconditional
            // sample math. Any difference here means a stage turned ON in the neutral
            // configuration (that is V1b-2, a deliberate separate slice) or the buffer
            // plumbing broke.
            XCTAssertEqual(output[channel], input[channel], """
                Channel \(channel) is not bit-identical through the insert. Since #839 \
                the chain runs INSIDE this block — bit-exactness is the proof it is \
                mounted NEUTRAL. A stage that colors the voice must arrive as V1b-2 \
                with its own door, never as a drifted default.
                """)
        }
    }

    // MARK: - 2. END-TO-END: the nil-mData branch supplies scratch and stays exact

    @MainActor
    func testTheRenderBlockSurvivesAHostThatProvidesNoBuffers() async throws {
        let (input, output) = try await renderOnce(hostProvidesBuffers: false)
        guard output.count == input.count else { return }
        for channel in 0..<input.count {
            XCTAssertEqual(output[channel], input[channel], """
                Channel \(channel) differs on the nil-mData branch — the scratch path of \
                the contract is broken. AVAudioEngine usually provides buffers, so this \
                branch failing would surface only when a host shape changes: exactly the \
                latent class V1a exists to close.
                """)
        }
    }
    #endif

    // MARK: - 3. The chain mounts the insert at ONE site and keeps the insert-less fallback

    func testTheInsertSitsBetweenTheMixersAndTheFallbackSurvives() {
        let engine = code("Sources/Echoelmusic/Audio/AudioEngine.swift")
        guard !engine.isEmpty else { return }
        XCTAssertTrue(engine.contains("masterEngine.connect(monitorMixer, to: insert, format: outFmt)")
                      && engine.contains("masterEngine.connect(insert, to: masterMixer, format: outFmt)"), """
            The insert's two hops are gone from the monitor-chain build. If the insert \
            moved, re-anchor; if it was removed, the V1a/V1b groundwork for the \
            commissioned vocal chain is gone and CLAUDE.md's vocal-chain line must say \
            so (#456).
            """)
        XCTAssertTrue(engine.contains("masterEngine.connect(monitorMixer, to: masterMixer, format: outFmt)"), """
            The insert-less fallback connect is gone — monitoring is now HOSTAGE to the \
            async AU instantiation. The law is the opposite: a nil insert builds the \
            pre-#832 chain exactly, because the founder's most-probed feature must never \
            wait on a factory callback.
            """)
        XCTAssertEqual(engine.components(separatedBy: "masterEngine.disconnectNodeOutput(insert)").count - 1, 2, """
            Expected BOTH teardown sites (the restart-failure rollback and the OFF path) \
            to disconnect the insert's outgoing hop. `disconnectNodeOutput(monitorMixer)` \
            only removes the hop INTO the insert — missing the outgoing one leaves a \
            half-connected node for the next build to trip over.
            """)
    }

    // MARK: - 4. The chain is mounted NEUTRAL — one instance, every stage off (V1b-2's tripwire)

    func testTheChainIsMountedWithEveryStageOff() {
        let insert = code("Sources/Echoelmusic/Audio/MonitorInsertAU.swift")
        guard !insert.isEmpty else { return }
        XCTAssertEqual(insert.components(separatedBy: "EchoelFXChain(").count - 1, 1, """
            Expected exactly ONE EchoelFXChain construction in the insert — zero means \
            the V1b-1 mount is gone (CLAUDE.md's vocal-chain line and the six prose \
            homes in TheVocalChainStopsAtTheAutotuneTests then overstate the path); two \
            means a second owner appeared (the BLE-3 class of defect).
            """)
        XCTAssertTrue(insert.contains("chain.processInPlace(left: left, right: right, frameCount: Int(frameCount))"), """
            The render block no longer feeds the pulled buffers through the chain — the \
            insert is back to an empty pass-through. If that is deliberate (a V1b \
            rollback), this file's name and header, CLAUDE.md's vocal-chain line and \
            the six prose homes go stale in the same commit (#456).
            """)
        XCTAssertTrue(insert.contains("if buffers.count == 2,"), """
            The stereo gate in front of the chain call is gone. `processInPlace` takes \
            (left, right); a mono host shape must stay pure pass-through rather than \
            process one buffer as both channels.
            """)
        // The all-off count uses a DERIVED denominator (#416): the chain's own
        // `…Enabled: Bool` declarations. A 16th stage added to EchoelFXChain without a
        // 16th explicit `= false` here goes red — a new stage must not arrive
        // half-wired on the singer's path with whatever default it happens to carry.
        let chainSource = code("Sources/Echoelmusic/DSP/EchoelFXChain.swift")
        guard !chainSource.isEmpty else { return }
        let declared = chainSource.components(separatedBy: "Enabled: Bool")
            .dropLast().count
        let switchedOff = insert.components(separatedBy: "Enabled = false").count - 1
        XCTAssertEqual(switchedOff, declared, """
            The insert switches \(switchedOff) stage flags off while EchoelFXChain \
            declares \(declared). V1b-1's whole claim is NEUTRAL — every stage \
            explicitly off, because the chain's own defaults (saturation/chorus/limiter \
            on) are tuned for the synth bus and would color the singer's voice as a \
            side effect. Turning a stage ON for the voice is V1b-2: do it as its own \
            slice, and move this count plus the prose homes in the same commit (#456).
            """)
        // #840: the chain rate FOLLOWS the negotiated bus format. The chain's rate is
        // immutable (baked into all 15 stage constructors), so following means
        // REBUILDING through the one neutral factory — which is also where a future
        // mic preset must be re-applied so a rate swap cannot drop it (V1b-2).
        XCTAssertTrue(insert.contains("let negotiated = Float(outputBus.format.sampleRate)"), """
            allocateRenderResources no longer reads the negotiated bus rate. Without \
            it the chain trusts the 48_000 it was constructed with, and a renegotiated \
            route would run every rate-dependent stage (V1b-2's audible ones) against \
            the wrong clock — the #839 review NIT this line exists to close (#840).
            """)
        // #841 reshaped the rebuild into apply-before-publish (`let fresh = …;
        // apply; replace`) — the ordering itself is pinned by
        // TheHarmonyVoicesReachTheSingersDoorTests claim 2 (#416); THIS needle pins
        // only that the rebuild goes through the ONE neutral factory. (The previous
        // one-line spelling went red on the correct tree and was caught by the
        // pre-push drive — the §4 class, fixed in the same commit.)
        XCTAssertTrue(insert.contains("let fresh = Self.neutralChain(sampleRate: negotiated)"), """
            The rate-mismatch branch no longer rebuilds the chain through the ONE \
            neutral factory. Rebuilding any other way forks the all-off configuration \
            (and the mic preset re-apply) into a second spelling — the #416 \
            shape on the singer's own path.
            """)
    }

    // MARK: - 5. The device probe can read whether the insert was in the chain

    func testTheOnBreadcrumbNamesTheInsertState() {
        let engine = code("Sources/Echoelmusic/Audio/AudioEngine.swift")
        guard !engine.isEmpty else { return }
        XCTAssertTrue(engine.contains("insert \\(monitorInsertAttached ? \"in\" : \"out\"), "), """
            The monitor-ON breadcrumb no longer states whether the insert made it into \
            the chain. The device probe is exactly this word in the founder's next \
            diag log — without it, "insert works" and "insert silently absent" produce \
            identical logs (#454's shape).
            """)
        XCTAssertTrue(engine.contains("insert unavailable ("), """
            The instantiation-failure breadcrumb is gone. A factory that fails silently \
            leaves `insert out` in the ON line with no line saying WHY — the exportable \
            log must carry the reason.
            """)
    }
}
