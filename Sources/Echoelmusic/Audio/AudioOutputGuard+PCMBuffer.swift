#if canImport(AVFoundation)
import AVFoundation

/// The buffer-shaped half of `AudioOutputGuard`.
///
/// Lives in `Audio/` rather than beside the rest of the guard in `DSP/` because
/// `DSP/` is kept Foundation-only by hygiene (`project.yml`) and this needs
/// AVFoundation. Same rule, same result — non-finite → 0, finite audio bit-exact.
///
/// ── WHY THE PLAYER-NODE PATH NEEDS ITS OWN GUARD ────────────────────────────
/// `AVAudioPlayerNode`s feed `masterMixer` alongside the render blocks, and it is
/// tempting to dismiss them as Apple nodes replaying decoded PCM. They are not:
/// they replay buffers WE build — baked fade envelopes and `WSOLAStretcher`
/// renders — carrying user-imported audio that nothing on the import path checks
/// for finiteness. A float32 file with NaN/inf bit patterns survives decode,
/// survives the fade multiply (`NaN * g == NaN`) and survives the stretch.
///
/// ── SWEEP AT FILL TIME, NOT AT SCHEDULE TIME ────────────────────────────────
/// Callers must sweep where a buffer's contents are FINALISED, not before each
/// `scheduleBuffer`. Two reasons, and the first is the load-bearing one:
///
/// 1. **Cost.** `TimelineAudioSink` caches its stretched buffer per `BeatsKey` and
///    reschedules it on every qualifying region onset. A five-minute stereo clip is
///    ~28.8 M samples; re-sweeping that per schedule would burn a full pass on the
///    main actor for a buffer that cannot have changed since the last one.
/// 2. **Aliasing.** At fill time the buffer is still local to its builder and no
///    node can hold it. Sweeping a cached buffer in place at schedule time would
///    mutate memory a previously-scheduled node may still be reading.
///
/// Fill time also means the sweep only ever touches a buffer its own builder still
/// owns exclusively. That rules out mutating memory some other component handed us
/// — which is why `AudioEngine.schedulePlayback` / `scheduleLoopPlayback` are
/// deliberately NOT wired: they take a buffer from an arbitrary caller, and both
/// currently have ZERO callers in `Sources/` and `Tests/`. Sweeping there would
/// mutate someone else's memory behind their back to protect a path nothing uses.
/// If either is ever wired up, sweep at whatever fills the buffer it is given.
extension AudioOutputGuard {

    /// Replace every non-finite sample in `buffer` with silence, in place.
    ///
    /// No-op for a non-float format: `floatChannelData` is nil there, and an integer
    /// sample cannot be NaN or infinite in the first place. Reinterpreting those
    /// bytes as `Float` would corrupt real audio, so the nil is a hard stop, not a
    /// case to work around.
    ///
    /// Honours `frameLength`, never `frameCapacity` — the tail past the written
    /// length is not audio and is left alone.
    public static func sweepNonFinite(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }

        // `stride` is 1 for the deinterleaved layout (one pointer per channel) and
        // `channelCount` for the interleaved one (a single pointer over all
        // channels). Reading it rather than assuming deinterleaved is what keeps
        // this correct if a file's processing format ever arrives interleaved —
        // assuming the wrong layout would sweep 1/N of the samples and silently
        // miss the rest.
        let stride = buffer.stride
        if stride == 1 {
            for channel in 0..<Int(buffer.format.channelCount) {
                sweepNonFinite(channels[channel], count: frames)
            }
        } else {
            sweepNonFinite(channels[0], count: frames * stride)
        }
    }
}
#endif
