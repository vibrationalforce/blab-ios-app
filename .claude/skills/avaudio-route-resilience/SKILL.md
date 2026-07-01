---
name: avaudio-route-resilience
description: Use when editing AudioEngine, MicrophoneManager, RetroCapture, taps, or
  ANY code that starts/reconfigures AVAudioEngine — especially alongside camera/rPPG
  activation. Prevents route-change resets and the 48k-vs-44.1k sample-rate mismatch
  (captured audio plays "viel höher"/pitch-shifted; or a format fatal) that fires
  when the camera route activates mid-performance. Load when adding a tap, starting
  the engine, or debugging audio pitch/dropping/crashing after the camera turns on.
---

# AVAudioEngine Route Resilience (Echoel)

Echoel-specific risk: **rPPG turns the camera ON mid-performance** → the audio route
switches (remote-I/O ↔ voice-processing-I/O) and iOS may grant **44.1 kHz** even
though we request 48 kHz. This has already produced a real bug: `RetroCapture`
captured 44.1k samples into a 48k-stamped file → the exported .mp4 played ~9% too
fast (higher pitch + off timing). The next latent risk is an unhandled
configuration-change resetting the engine mid-session.

## Checklist

- [ ] **Never hardcode 44100/48000** for a tap, ring buffer, or output file. Read the
      REAL rate from the tap's format: `node.outputFormat(forBus:).sampleRate`, and use
      it for BOTH the file format AND all seconds↔frames math. (Fixed in
      `RetroCapture.captureSampleRate` — follow that pattern for any new capture.)
- [ ] **Observe the three notifications** where audio + camera coexist:
      `AVAudioSession.routeChangeNotification`,
      `NSNotification.Name.AVAudioEngineConfigurationChange`, and
      `AVAudioSession.interruptionNotification`.
- [ ] **On config/route change:** the engine may have stopped attached players and
      reset connections. Reconcile: re-query formats, rebuild/reconnect nodes if the
      format changed, re-install taps (a tap installed against the OLD format is stale),
      and restart the engine if it stopped.
- [ ] **Never cache an `AVAudioFormat` across a route change.** Re-query
      `inputNode.inputFormat(forBus:)` / `mainMixerNode.outputFormat(forBus:)`
      immediately before (re)installing any tap.
- [ ] **Guard the start-after-switch race:** verify formats are valid
      (`sampleRate > 0 && channelCount > 0`) before `engine.start()`; if not settled,
      log and skip rather than crash.
- [ ] **Interruption began/ended:** deactivate/reactivate the session and resume
      players; don't assume the graph survived.

## Test path (mandatory — this is the exact failure path)

- [ ] Start audio → activate camera/rPPG → confirm: NO fatal, audio continues, and a
      subsequent capture/export has the CORRECT pitch/tempo (matches live).
- [ ] Because there is no local Swift build, audio-graph correctness needs a
      device/TestFlight run — compile + review alone will NOT catch an `_isInput`
      assertion or a sample-rate mismatch.

Composes with `audio-thread-reviewer` (the tap callback stays lock/malloc/objc-free).
