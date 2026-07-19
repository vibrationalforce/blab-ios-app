// AudioLanePlayer.swift
// Echoel — the transport-driven executor for AUDIO lanes: on each transport window
// it plays / stops each audio lane's active region. This is the COORDINATOR half,
// kept Foundation-only + fully unit-tested by abstracting the device player behind
// `AudioRegionSink`. The thin AVFoundation adapter (an AudioClipPlayer per lane,
// attached to the engine) and the transport wiring land in a following, device-
// verified cycle — this file has NO AVFoundation, no audio-thread code, no state
// the render path touches.
//
// It composes the two already-tested pieces: TimelineScheduling decides WHICH
// region a lane plays and WHEN it changes (onset/clear); AudioRegionPlayback maps
// the song tick to the media-file position + remaining length. WIRED since v191
// (EchoelmusicApp: `timelinePlayer.audioLanes = AudioLanePlayer(...)`) — audio
// lanes now sound in time with the arrangement; it stays allocation-free on the
// render path (the `.unchanged`/onset/clear windows do all reconciliation).
//
// LIVE MIXER (H4, closed the original known gap): `.unchanged` windows reconcile
// the lane's gain/pan against what the sink last received — a mid-region level
// move re-gains live, mute stops now, unmute RE-STARTS the region at the honest
// file position (the one-shot segment is gone), and pan edits land immediately.
// The caller keeps the doc's mixer fields fresh (TimelineRegionPlayer merges the
// store's live values each step), so this file stays a pure function of its input.

import Foundation

/// The device player a lane drives, abstracted so the coordinator's mapping logic
/// is testable without AVFoundation. The wiring cycle provides an AudioClipPlayer-
/// backed implementation (attach to the engine, `scheduleSegment`).
@MainActor
public protocol AudioRegionSink: AnyObject {
    /// Begin playing `url` from `fromSeconds` into the file, for up to
    /// `lengthSeconds` of MEDIA time, at linear `gain`. Replaces any current
    /// playback on this sink. `stretch` (Slice B) is the resolved Echoel stretch
    /// plan for the region: rate 1.0 plays on the plain, bit-identical path;
    /// rate ≠ 1.0 renders through the sink's warp chain (pitch held for Clean,
    /// riding the tempo for Tape).
    func play(url: URL, fromSeconds: Double, lengthSeconds: Double, gain: Float,
              stretch: StretchPlan)
    /// Stop this sink's playback.
    func stop()
    /// Open `url` and attach to the engine WITHOUT playing (warm-up). Called at
    /// prime time for every lane so the graph mutation (which pauses the whole
    /// engine in this codebase's attach pattern) happens BEFORE playback — a lane
    /// whose first region starts at bar 9 must not pause the running mix mid-song
    /// (audio-thread review HIGH 2). `warped` (Slice B): true when any region of
    /// this lane plays `url` warped, so the sink can attach its warp chain NOW,
    /// at prime time, never mid-song. Default: no-op.
    func preload(url: URL, warped: Bool)
    /// Release engine resources when the lane is removed (reconcile). Default: no-op.
    func detach()
    /// Beats-Executor: pre-render the media window `fromSeconds`→`+lengthSeconds`
    /// of `url` time-stretched by `rate` (pitch held, transient-locked WSOLA) so a
    /// Beats region's onset schedules a READY buffer instead of stretching live.
    /// Called at prime time (transport parked). Default: no-op — a sink without
    /// an offline renderer plays the region through its Clean chain instead.
    func prepareBeats(url: URL, fromSeconds: Double, lengthSeconds: Double, rate: Double)
    /// Live mixer (H4): set this lane's output gain WITHOUT re-scheduling — a
    /// mid-region level/solo edit must be heard now. Default: no-op.
    func setGain(_ gain: Float)
    /// Live mixer (H4): set this lane's stereo pan (−1…1). Default: no-op.
    func setPan(_ pan: Float)
}

public extension AudioRegionSink {
    func preload(url: URL, warped: Bool) {}
    func detach() {}
    func prepareBeats(url: URL, fromSeconds: Double, lengthSeconds: Double, rate: Double) {}
    func setGain(_ gain: Float) {}
    func setPan(_ pan: Float) {}
}

@MainActor
public final class AudioLanePlayer {

    /// Makes a fresh device sink for a lane (injected; the wiring cycle returns an
    /// AudioClipPlayer-backed sink attached to the engine).
    private let makeSink: () -> AudioRegionSink
    /// Resolves a clip id to a playable file URL (injected; the wiring cycle passes
    /// `clips.clip(id:)` → mediaRef → URL). `nil` ⇒ nothing to play (the lane stops).
    private let resolveURL: (UUID) -> URL?
    /// Resolves a clip id to the media's NATIVE tempo (Slice B; injected —
    /// `clips.clip(id:)?.nativeBPM`). `0` ⇒ unknown ⇒ a warped region honestly
    /// plays unstretched (rate 1.0), exactly like the editor preview.
    private let resolveNativeBPM: (UUID) -> Double

    private var sinks: [UUID: AudioRegionSink] = [:]
    /// H4 live mixer: the gain/pan last pushed to each lane's sink, so the per-step
    /// reconcile only touches the sink on a REAL edit. `appliedGain == 0` also means
    /// "silenced by mute/solo at (or since) the onset" — the unmute path uses it to
    /// know it must re-start the region (a stopped one-shot can't just re-gain).
    private var appliedGain: [UUID: Float] = [:]
    private var appliedPan: [UUID: Float] = [:]

    // MARK: - Clip-Launch override (S1 of PLAN_AUDIO_CLIP_LAUNCH — audio-lane launch)
    //
    // A LAUNCHED audio clip overrides its lane's arrangement and LOOPS its region
    // window until stopped — the audio twin of the MIDI ClipLaunchEngine override.
    // A MIDI launch re-windows for free every tick; an audio region is a ONE-SHOT
    // file segment, so a launched clip must be RE-TRIGGERED at each loop boundary
    // (`LaunchTiming.loopWrapped`, already tested). RUNTIME-ONLY like the MIDI
    // launch: never persisted, dropped on every transport reset (the caller clears
    // it in the same paths it clears the MIDI launch). GOLDEN GATE: while
    // `overrides.isEmpty` every path below is byte-identical to arrangement-only
    // playback — this whole slice is inert until a caller (S2) sets an override.

    /// One lane's launched region + the song tick its loop phase is anchored to.
    private struct AudioLaunchOverride { let region: TimelineRegion; let startedAtTick: Int }
    private var overrides: [UUID: AudioLaunchOverride] = [:]

    /// True when NO lane carries a launch override (the golden-gate query).
    public var hasLaunchOverrides: Bool { !overrides.isEmpty }
    /// Whether a launched region currently overrides this lane's arrangement.
    public func isLaunchOverriding(_ laneID: UUID) -> Bool { overrides[laneID] != nil }

    /// Begin (or replace) a launched override on `laneID`: loop `region` from its
    /// content top starting now, anchored at `tick` (the launch boundary). Reuses
    /// the SAME `start` path as the arrangement, so a launched clip sounds
    /// byte-identical to that region playing from the arrangement.
    public func setLaunchOverride(_ region: TimelineRegion, laneID: UUID,
                                  atTick tick: Int, in doc: TimelineDocument, bpm: Double) {
        overrides[laneID] = AudioLaunchOverride(region: region, startedAtTick: max(0, tick))
        start(region, laneID: laneID, atTick: region.startTick, in: doc, bpm: bpm)   // from the top
    }

    /// End the launch on `laneID`: hand the lane back to the arrangement region
    /// active at `tick` (or stop it in a gap). No-op when the lane isn't overridden.
    public func clearLaunchOverride(laneID: UUID, atTick tick: Int,
                                    in doc: TimelineDocument, bpm: Double) {
        guard overrides.removeValue(forKey: laneID) != nil else { return }
        if let region = TimelineScheduling.activeRegion(in: doc, laneID: laneID, at: tick) {
            start(region, laneID: laneID, atTick: tick, in: doc, bpm: bpm)
        } else {
            sinks[laneID]?.stop()
            appliedGain[laneID] = 0
        }
    }

    /// Drop every launch override WITHOUT touching audio (the caller's transport-reset
    /// path calls `stopAll` for the audio, exactly like the MIDI `launch.removeAll`).
    public func clearAllLaunchOverrides() { overrides.removeAll() }

    /// S3 (song-loop wrap): fold every override's loop anchor by `deltaTicks`, the
    /// audio twin of `ClipLaunchEngine.shift` — when the transport tick timebase
    /// wraps by the loop length, the launched-segment timebase folds with it so its
    /// next `loopWrapped` fires at the right (post-wrap) boundary instead of reading
    /// a stale anchor (elapsed < 0). Whole-bar loop lengths keep grid alignment.
    public func shiftLaunchOverrides(by deltaTicks: Int) {
        guard deltaTicks != 0, !overrides.isEmpty else { return }
        for (laneID, ov) in overrides {
            overrides[laneID] = AudioLaunchOverride(region: ov.region,
                                                    startedAtTick: ov.startedAtTick + deltaTicks)
        }
    }

    /// S3 (structure edit): drop any override whose lane or region no longer exists,
    /// stopping its now-orphaned audio (mirrors `ClipLaunchEngine.prune`). The caller
    /// re-primes the freed lanes through the normal arrangement path afterwards.
    public func pruneLaunchOverrides(validLaneIDs: Set<UUID>, validRegionIDs: Set<UUID>) {
        guard !overrides.isEmpty else { return }
        for (laneID, ov) in overrides where !validLaneIDs.contains(laneID)
            || !validRegionIDs.contains(ov.region.id) {
            overrides[laneID] = nil
            sinks[laneID]?.stop()
            appliedGain[laneID] = 0
        }
    }

    /// S3 (song-loop wrap, re-trigger): drive the OVERRIDDEN lanes across the wrap in
    /// the SAME folded frame the anchors were just folded into (`shiftLaunchOverrides`).
    /// `prime` warms the files but SKIPS overridden lanes, so the wrap-coincident
    /// re-trigger of a launched one-shot segment would otherwise be dropped — a bar of
    /// silence at the top of every song loop for a boundary-aligned launched loop
    /// (audio-thread review, S3a). Passing the folded window `(lastTick − loopTicks,
    /// newTick)` lets `loopWrapped` itself decide: a boundary coincident with the wrap
    /// re-fires the segment from its loop top; a segment that SPANS the wrap is left
    /// playing (reconcile only). This is the audio twin of `ClipLaunchEngine.tick`
    /// running after `shift`. No-op with no overrides (golden gate).
    public func applyWrappedOverrides(in doc: TimelineDocument, fromTick: Int,
                                      toTick: Int, bpm: Double) {
        guard !overrides.isEmpty else { return }
        for laneID in doc.audioLaneIDs {
            guard let ov = overrides[laneID] else { continue }
            applyLaunchOverride(ov, laneID: laneID, fromTick: fromTick,
                                toTick: toTick, in: doc, bpm: bpm)
        }
    }

    public init(makeSink: @escaping () -> AudioRegionSink,
                resolveURL: @escaping (UUID) -> URL?,
                resolveNativeBPM: @escaping (UUID) -> Double = { _ in 0 }) {
        self.makeSink = makeSink
        self.resolveURL = resolveURL
        self.resolveNativeBPM = resolveNativeBPM
    }

    /// Apply the transport window `fromTick`→`toTick`: for each audio lane, start
    /// its newly-entered region (`.load`), stop it on leaving into a gap (`.clear`),
    /// or leave it playing (`.unchanged`). Order-independent, so a loop wrap works
    /// when the caller passes the real from/to ticks (mirrors the MIDI player).
    public func apply(in doc: TimelineDocument, fromTick: Int, toTick: Int, bpm: Double) {
        // Reconcile: release any sink whose lane was removed / re-typed since the last
        // apply (else that lane's audio would keep sounding with no way to stop it).
        let live = Set(doc.audioLaneIDs)
        for laneID in sinks.keys.filter({ !live.contains($0) }) {
            sinks[laneID]?.stop()
            sinks[laneID]?.detach()   // release the engine node, not just the playback
            sinks[laneID] = nil
            appliedGain[laneID] = nil
            appliedPan[laneID] = nil
            overrides[laneID] = nil   // a removed lane's launch dies with it
        }
        for laneID in doc.audioLaneIDs {
            // S1 Clip-Launch: a LAUNCHED lane ignores the arrangement — it loops its
            // launched region, re-triggering the one-shot segment at each loop wrap
            // (`LaunchTiming.loopWrapped`) and honoring live mix in between. Idle
            // engine (no override) ⇒ the arrangement switch below, byte-identical.
            if let ov = overrides[laneID] {
                applyLaunchOverride(ov, laneID: laneID, fromTick: fromTick,
                                    toTick: toTick, in: doc, bpm: bpm)
                continue
            }
            switch TimelineScheduling.laneEvent(in: doc, laneID: laneID,
                                                fromTick: fromTick, toTick: toTick) {
            case .unchanged:
                // H4 (closes this file's original KNOWN GAP): no region boundary,
                // but a live mixer edit may have changed the lane's gain/pan —
                // reconcile against what the sink last got.
                reconcileMix(laneID, in: doc, atTick: toTick, bpm: bpm)
            case .clear:
                sinks[laneID]?.stop()
                appliedGain[laneID] = 0
            case .load(let region):
                start(region, laneID: laneID, atTick: toTick, in: doc, bpm: bpm)
            }
        }
    }

    /// Prime the audio lanes whose region is ACTIVE at `tick` (play()/seek entry):
    /// an already-active region reads `.unchanged` and would never load, so this is
    /// its onset twin — the audio analog of the MIDI `primeSecondaryLanes`.
    public func prime(in doc: TimelineDocument, atTick tick: Int, bpm: Double) {
        for laneID in doc.audioLaneIDs {
            // Warm EVERY lane that has any content: open the files + attach nodes
            // now, while nothing is sounding — the attach pattern pauses the whole
            // engine, which must never happen mid-song at a late region's onset
            // (audio-thread review HIGH 2). PERF-01: preload EVERY DISTINCT file
            // the lane will play, not just the earliest — the sink keeps one node
            // per distinct format, so a lane mixing (say) a 48 kHz mono take with
            // a 44.1 kHz stereo loop crosses their boundary with NO mid-song
            // attach (the old single-node sink re-attached = full-mix dropout at
            // every crossing). The sink memoizes known URLs, so a loop-wrap
            // re-prime is a pure no-op.
            let laneRegions = doc.regions.filter { $0.laneID == laneID }
                .sorted { $0.startTick < $1.startTick }
            // Slice B: OR-merge the warp need per URL — if ANY region plays this
            // file warped (and its native tempo is known), the sink must attach
            // its warp chain NOW, at prime time, never mid-song (review HIGH 2).
            var need: [URL: Bool] = [:]
            var order: [URL] = []
            for region in laneRegions {
                guard let url = self.resolveURL(region.clipID) else { continue }
                let warped = region.warpEnabled && resolveNativeBPM(region.clipID) > 0
                if let existing = need[url] {
                    need[url] = existing || warped
                } else {
                    need[url] = warped
                    order.append(url)
                }
            }
            for url in order {
                sink(for: laneID).preload(url: url, warped: need[url] ?? false)
            }
            // Beats-Executor: pre-render every Beats region's media window NOW,
            // while the transport is parked — its onset then schedules a ready,
            // transient-locked buffer at rate 1 (never a live stretch mid-song).
            for region in laneRegions {
                guard let url = self.resolveURL(region.clipID) else { continue }
                let plan = StretchPlan.resolve(mode: region.stretchMode,
                                               warpEnabled: region.warpEnabled,
                                               nativeBPM: resolveNativeBPM(region.clipID),
                                               projectBPM: bpm,
                                               capabilities: StretchMode.timelineCapabilities)
                if plan.mode == .beats, plan.rate != 1.0 {
                    let mediaLength = TimelineTime.seconds(
                        fromTicks: region.lengthTicks, bpm: bpm) * plan.rate
                    sink(for: laneID).prepareBeats(url: url,
                                                   fromSeconds: region.contentOffsetSeconds,
                                                   lengthSeconds: mediaLength,
                                                   rate: plan.rate)
                }
            }
            // S3: a LAUNCHED lane keeps its override — the arrangement re-prime (song-
            // loop wrap / structure edit) must NOT clobber it with an arrangement
            // region (the MIDI `primeSecondaryLanes` guards the same way). The files
            // are still warmed above; only the arrangement start/stop is skipped.
            // play()/relocate() clear overrides BEFORE prime, so those paths are
            // unaffected (the map is empty there).
            if overrides[laneID] != nil { continue }
            guard let region = TimelineScheduling.activeRegion(in: doc, laneID: laneID, at: tick) else {
                sinks[laneID]?.stop()
                continue
            }
            start(region, laneID: laneID, atTick: tick, in: doc, bpm: bpm)
        }
    }

    /// Stop every lane (transport stop / teardown).
    public func stopAll() {
        for sink in sinks.values { sink.stop() }
    }

    // MARK: - Private

    /// Start `region` on `laneID` at `tick`: gate on the lane's audible gain, resolve
    /// the file, map the tick to the media position + remaining length, and drive the
    /// sink. A muted / soloed-away lane or an unresolvable file stops instead.
    private func start(_ region: TimelineRegion, laneID: UUID, atTick tick: Int,
                       in doc: TimelineDocument, bpm: Double) {
        // CLIP-6: the region instance's own gain rides on the lane's mixer gain
        // (region.gain is init/decode-clamped 0…2; the sink clamps the product).
        let gain = doc.effectiveGain(for: laneID) * region.gain
        // Record the gate result even when silenced: an unmute mid-region must know
        // the lane was at 0 so it restarts the region (see reconcileMix).
        appliedGain[laneID] = gain
        guard gain > 0,
              let url = resolveURL(region.clipID) else {
            sinks[laneID]?.stop()
            if gain > 0 { appliedGain[laneID] = 0 }   // unresolvable file ⇒ not sounding
            return
        }
        // Slice B: the region's stretch plan — rate 1.0 unless the placement opts
        // in (warpEnabled) AND the clip's native tempo is known. Beats-Executor:
        // the timeline consumer now executes Beats too (prime-time pre-render in
        // TimelineAudioSink; a missing buffer falls back to the Clean chain at
        // play time — per-consumer capabilities stay the truth mechanism).
        let plan = StretchPlan.resolve(mode: region.stretchMode,
                                       warpEnabled: region.warpEnabled,
                                       nativeBPM: resolveNativeBPM(region.clipID),
                                       projectBPM: bpm,
                                       capabilities: StretchMode.timelineCapabilities)
        // Media position at this tick (mid-region entry advances it — rate-aware:
        // a warped region consumes media rate× as fast as song time passes);
        // remaining MEDIA length to the region boundary (source = output × rate,
        // the AudioRegionPlayback.frameCount identity). Both are the tested maps.
        let from = AudioRegionPlayback.filePositionSeconds(for: region, atTick: tick,
                                                           bpm: bpm, stretchRate: plan.rate)
            ?? region.contentOffsetSeconds
        let length = TimelineTime.seconds(fromTicks: region.endTick - tick, bpm: bpm)
            * plan.rate
        let lane = sink(for: laneID)
        lane.play(url: url, fromSeconds: from,
                  lengthSeconds: max(0, length), gain: gain, stretch: plan)
        // H4: audio lanes take the lane's stereo position too (B2 gave TimelineLane
        // a pan; the synth voices honored it, audio lanes never did).
        let pan = clampedPan(in: doc, laneID: laneID)
        lane.setPan(pan)
        appliedPan[laneID] = pan
    }

    /// H4 live-mixer reconcile for a lane sitting INSIDE an unchanged region (or a
    /// gap): push a changed gain/pan to the sink. Three gain cases — silenced (→0):
    /// stop; un-silenced (0→): re-START the region so the file position is honest
    /// (the previous one-shot segment is gone); level moved (>0→>0): live re-gain.
    private func reconcileMix(_ laneID: UUID, in doc: TimelineDocument, atTick tick: Int, bpm: Double) {
        guard let lane = sinks[laneID] else { return }
        // CLIP-6: the TOTAL gain (lane mixer × active region's own gain) is what
        // `appliedGain` tracks — a gap (no active region) contributes unity so a
        // silent lane's gate bookkeeping stays lane-driven. One lookup, reused
        // by the un-silence branch (review LOW).
        let active = TimelineScheduling.activeRegion(in: doc, laneID: laneID, at: tick)
        let gain = doc.effectiveGain(for: laneID) * (active?.gain ?? 1)
        let oldGain = appliedGain[laneID] ?? gain
        if gain != oldGain {
            if gain <= 0 {
                lane.stop()
                appliedGain[laneID] = 0
            } else if oldGain <= 0 {
                if let region = active {
                    start(region, laneID: laneID, atTick: tick, in: doc, bpm: bpm)
                }
                // No active region (gap): stay at 0 — the next onset starts it.
            } else {
                lane.setGain(gain)
                appliedGain[laneID] = gain
            }
        }
        let pan = clampedPan(in: doc, laneID: laneID)
        if pan != (appliedPan[laneID] ?? 0) {
            lane.setPan(pan)
            appliedPan[laneID] = pan
        }
    }

    /// S1 Clip-Launch: drive one launched lane for the window `fromTick`→`toTick`.
    /// On a loop wrap the one-shot segment is re-triggered from the region's top;
    /// otherwise a live mixer edit is reconciled against the OVERRIDE region's gain
    /// (not the arrangement's), so mute/level/pan work on a launched clip too.
    private func applyLaunchOverride(_ ov: AudioLaunchOverride, laneID: UUID,
                                     fromTick: Int, toTick: Int,
                                     in doc: TimelineDocument, bpm: Double) {
        if LaunchTiming.loopWrapped(from: fromTick, to: toTick,
                                    sinceTick: ov.startedAtTick,
                                    loopLength: ov.region.lengthTicks) {
            start(ov.region, laneID: laneID, atTick: ov.region.startTick, in: doc, bpm: bpm)
        } else {
            reconcileLaunchMix(ov, laneID: laneID, atTick: toTick, in: doc, bpm: bpm)
        }
    }

    /// H4-style live-mixer reconcile for a LAUNCHED lane — mirrors `reconcileMix`
    /// but gates on the override region's gain, and re-starts at the honest loop
    /// PHASE (not the top) on un-silence, so an unmute mid-loop resumes in place.
    private func reconcileLaunchMix(_ ov: AudioLaunchOverride, laneID: UUID,
                                    atTick tick: Int, in doc: TimelineDocument, bpm: Double) {
        guard let lane = sinks[laneID] else { return }
        let gain = doc.effectiveGain(for: laneID) * ov.region.gain
        let oldGain = appliedGain[laneID] ?? gain
        if gain != oldGain {
            if gain <= 0 {
                lane.stop()
                appliedGain[laneID] = 0
            } else if oldGain <= 0 {
                // Un-silence at the honest loop phase: file offset = content position
                // within this loop cycle (a stopped one-shot can't resume; re-schedule).
                let contentTick = LaunchTiming.loopContentTick(now: tick,
                                                               sinceTick: ov.startedAtTick,
                                                               loopLength: ov.region.lengthTicks)
                start(ov.region, laneID: laneID,
                      atTick: ov.region.startTick + contentTick, in: doc, bpm: bpm)
            } else {
                lane.setGain(gain)
                appliedGain[laneID] = gain
            }
        }
        let pan = clampedPan(in: doc, laneID: laneID)
        if pan != (appliedPan[laneID] ?? 0) {
            lane.setPan(pan)
            appliedPan[laneID] = pan
        }
    }

    private func clampedPan(in doc: TimelineDocument, laneID: UUID) -> Float {
        let p = doc.lanes.first(where: { $0.id == laneID })?.pan ?? 0
        return max(-1, min(1, p))
    }

    private func sink(for laneID: UUID) -> AudioRegionSink {
        if let existing = sinks[laneID] { return existing }
        let created = makeSink()
        sinks[laneID] = created
        return created
    }
}
