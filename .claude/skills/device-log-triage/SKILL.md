---
name: device-log-triage
description: Use when given an iOS crash or on-device anomaly — a .ips file,
  Console/device log, echoel_diag.log, or a MetricKit MXCrashDiagnostic — to reach a
  root cause and a minimal fix. Echoel has NO local Swift build, so device logs + CI
  are the only ground truth. Load when the user pastes a crash/diag log, reports an
  on-device crash/freeze, or asks "why did it crash on TestFlight".
---

# Device Log Triage (Echoel)

Echoel ships to TestFlight and iterates from device logs the founder pastes
(often `echoel_diag.log` with timestamped launch/rPPG/transport lines). This skill
turns that raw text into a routed fix.

## Steps

- [ ] Identify the build/version in the log header (e.g. "10.76.56 (2092)"). Confirm
      the fix you're verifying is actually IN that build — a fix pushed after the
      build number the user sees is NOT yet on their device.
- [ ] For a real crash `.ips`: match the correct dSYM to the exact app version, then
      symbolicate (Xcode auto-symbolicates a linked dSYM; else `atos`). MetricKit
      `MXCrashDiagnostic` arrives UNSYMBOLICATED.
- [ ] Read the crashing thread's top frames + termination reason (EXC_BAD_ACCESS,
      SIGSEGV, watchdog 0x8badf00d, `required condition is false: ...`).
- [ ] For an `echoel_diag.log` (no stack): read the last lines before the gap/stop —
      the last successful stage tells you where it died (launch stages, "camera
      started", "polyVoice.noteOn", "stopEverything").

## Route to the fix (Echoel signatures)

- [ ] `required condition is false: _isInput` → a tap on `AVAudioEngine.outputNode`
      (forbidden) → reuse `RetroCapture` ring; load `avaudio-route-resilience`.
- [ ] SwiftUI metadata / type-metadata decoder frame, SIGSEGV at first render, black
      screen → `.sheet`-chain metadata limit → load `swiftui-render-safety`.
- [ ] Freeze/ANR while biofeedback runs (not a crash), menu/Picker unresponsive →
      10 Hz `@Observable` read in an ancestor body → `swiftui-render-safety`
      diagnosing section (audit the PARENT/ROOT).
- [ ] Captured/exported audio "höher"/pitch-shifted vs. live → 48k-vs-actual
      sample-rate mismatch on a camera-active route → `avaudio-route-resilience`.
- [ ] Audio-thread stack (render block) with malloc/lock/objc_msgSend → run the
      `audio-thread-reviewer` agent.

## Output

- [ ] One-line root cause + the smallest fix (≤3 files, Ralph Wiggum). No refactor.
- [ ] State honestly whether the fix is compile-verified (CI/Xcode gate) vs.
      device-verified — an audio-graph/route fix is NOT proven until a device run.
