// TheMonitorInsertIsAnEmptyPassThroughTests — pins #832 (V1a of the vocal chain).
//
// THE SLICE (decisions.csv:398/450): before any vocal DSP rides on the singer's monitor
// path, the AUAudioUnit render CONTRACT is proven with an EMPTY pass-through insert —
// zero sound change, mounted between `monitorMixer` and `masterMixer` (one connect
// site, untouched by the voice-tune rewires, stereo so V1b gets left/right).
//
// KINDS (§1), per test:
// · tests 1–2 are END-TO-END BEHAVIOUR — they run the production factory and the real
//   render block on this host and compare samples. This is the strong kind, and it is
//   the entire purpose of V1a: if the AU contract breaks, it breaks HERE, not on the
//   founder's device.
// · tests 3–5 are SOURCE-TEXT SCANS over AudioEngine.swift / MonitorInsertAU.swift.
// · Whether the insert is audible-neutral on a REAL route is a DEVICE PROBE — open,
//   answered by the next founder log's `insert in` + unchanged monitoring sound.
//
// GRADING (§3): every test names a symbol or line this same commit creates — the file
// does not compile against the parent tree, so no assertion has a verdict there
// (FORWARD guards, zero regressions bookable). Source-scan logic was driven in Python
// against the worktree before push; the end-to-end expectations are derived (#442):
// a pass-through's output IS its input, exactness is not a tolerance question.
//
// #364: nothing here forbids V1b. When the pass-through gains its processing stage,
// test 2's "no per-sample loop" scan goes red on purpose and its message names the
// prose to move in the same commit.

import Foundation
import XCTest
#if canImport(AVFoundation)
import AVFoundation
import AudioToolbox
#endif
@testable import Echoelmusic

final class TheMonitorInsertIsAnEmptyPassThroughTests: XCTestCase {

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
            degrades gracefully (monitoring builds without the insert), but V1a's deliverable \
            is a working AU contract — a nil here means the contract is broken everywhere.
            """).auAudioUnit
        XCTAssertTrue(unit is MonitorInsertAudioUnit, """
            The factory's component description resolved to some OTHER audio unit — the \
            registration is not reaching our subclass, so the node in the monitor chain is \
            not the pass-through this file certifies.
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
            The render block returned \(status) instead of noErr — the pass-through \
            contract failed on the \(hostProvidesBuffers ? "host-buffer" : "nil-mData") \
            branch.
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

    // MARK: - 1. END-TO-END: the output IS the input, on the host-buffer branch

    @MainActor
    func testTheRenderBlockPassesTheInputThroughBitExactly() async throws {
        let (input, output) = try await renderOnce(hostProvidesBuffers: true)
        guard output.count == input.count else { return }
        for channel in 0..<input.count {
            // Exactness, not tolerance (#442): a pass-through COPIES. Any epsilon here
            // would let a quiet DSP stage ship inside the "empty" insert.
            XCTAssertEqual(output[channel], input[channel], """
                Channel \(channel) is not bit-identical through the insert. V1a's whole \
                claim is ZERO sound change — if this differs, either a stage crept in \
                (that is V1b, a separate deliberate slice) or the buffer plumbing is wrong.
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
            moved, re-anchor; if it was removed, the V1a groundwork for the commissioned \
            vocal chain is gone and CLAUDE.md's vocal-chain line must say so (#456).
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

    // MARK: - 4. The pass-through is EMPTY — no DSP name reaches it (V1b's tripwire)

    func testTheInsertFileCarriesNoProcessingStage() {
        let insert = code("Sources/Echoelmusic/Audio/MonitorInsertAU.swift")
        guard !insert.isEmpty else { return }
        XCTAssertTrue(insert.contains("return pull(&pullFlags, timestamp, frameCount, 0, outputData)"), """
            The render block no longer ends in the direct pull-into-output call — the \
            pass-through IS that call. If a processing stage landed here, this is V1b: \
            move this guard's claims and the six prose homes the vocal-chain guard names, \
            in the same commit (#456).
            """)
        for stage in ["EchoelFXChain", "EchoelHarmonizer", "EchoelGranular", "processInPlace"] {
            XCTAssertFalse(insert.contains(stage), """
                `\(stage)` appeared in the V1a insert. That is the V1b wiring — a \
                deliberate separate slice with an audio-thread review, a mic-owned \
                preset, and six prose homes to move (#456). It must not arrive as a \
                side effect of the pass-through file growing.
                """)
        }
    }

    // MARK: - 5. The device probe can read whether the insert was in the chain

    func testTheOnBreadcrumbNamesTheInsertState() {
        let engine = code("Sources/Echoelmusic/Audio/AudioEngine.swift")
        guard !engine.isEmpty else { return }
        XCTAssertTrue(engine.contains("insert \\(monitorInsertAttached ? \"in\" : \"out\"), "), """
            The monitor-ON breadcrumb no longer states whether the insert made it into \
            the chain. V1a's device probe is exactly this word in the founder's next \
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
