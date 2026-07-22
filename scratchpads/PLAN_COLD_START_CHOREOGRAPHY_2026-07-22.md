# PLAN — Vision Step 2: Cold-Start Choreography

**Vision law #1:** "app open, finger on camera, in 3 seconds it lives and glows,
no menu/setup." Step 1 (instrument-home) made the app OPEN into the living
instrument. Step 2 is the first-seconds sequence: **enter → it lives → invite the
finger → first tone → first touch**, without a setup wall and without breaking the
mandatory safety gate or the camera-permission law.

## Current wiring (grounded)

- `EchoelmusicApp.swift:283-288`: first run shows `OnboardingView(isComplete:
  $hasCompletedOnboarding, shouldAutoPlay: $shouldAutoPlay)`; after completion →
  `mainContent` (WorkspaceView, now the fullscreen instrument home).
- `OnboardingView.swift`: a STATIC 3-page intro (welcome → wider-vision →
  ready+safety). Its `shouldAutoPlay` binding is **wired but unused** ("Retained
  for binding parity … unused in v10") — the dormant hook for "after onboarding,
  auto-start". Its copy leads with the METRIC ("Your heartbeat makes music", "lock
  a key and BPM", "Export to your DAW") and its header comment is FACTUALLY FALSE
  ("does not read biometrics on the audio path" — reading bio IS the core feature).
- Bio start today is MANUAL: the header pulse pill posts `.echoelToggleBio`;
  `EchoelStudioView` owns start/stop and runs the permission ask at a real bio-use
  moment (UX-3), never context-free at launch.

## Council verdict (2026-07-22)

Keep the mandatory safety gate (epilepsy/driving/medical — cannot be removed).
"No setup" = drop the rest of the multi-page friction and fall into the living
instrument. Auto-arming the camera MUST follow a user gesture — the onboarding
"Start" tap IS that gesture, so arming bio right after Start is consented (the
dormant `shouldAutoPlay` intent). Reuse the `.echoelToggleBio` path (studio owns
bio start) — no second launch owner. Brand copy is founder territory — propose,
don't autonomously reword the poetic lines.

## Slices

### 2a — gesture-consented auto-arm after onboarding (SAFE-AUTONOMOUS)
Wire the dormant `shouldAutoPlay`: when the user taps "Start" on the onboarding
ready page (the consenting gesture), set `shouldAutoPlay = true`; `mainContent`
reads it once on appear and posts `.echoelToggleBio` (the exact path the pulse
pill uses) so the bio-generative instrument arms itself and "lives" the moment
they enter. Guarded once (a @State/one-shot) so it fires only on the fresh
onboarding→home transition, never on every launch. The camera-permission dialog
then appears as a direct consequence of the Start tap — honest, gesture-driven.
- **Open question for founder/device-verify:** permission dialog IMMEDIATELY on
  entry vs. after the user sees the instrument glow idle first. Vision leans
  "immediate" ("in 3 seconds it lives"), but a dialog-on-entry can feel abrupt.
  This is the one timing call to confirm on device.
- Render safety: no sheet added; `shouldAutoPlay` is low-frequency; the post is in
  an `.onAppear`/one-shot, not a body read.

### 2b — one-time finger-on-camera + touch-to-play invitation (SAFE-AUTONOMOUS)
A single gentle, FADING whisper on the instrument home (once, persisted via
`@AppStorage` e.g. `onboard.instrumentHintSeen`): "📷 Finger auf die Kamera bringt
es zum Leben" + "👆 Berühre das Bild zum Spielen". A leaf overlay in
FloatingVisualWindow's card — reduce-motion aware (no motion → static then fade),
flash-safe (opacity only, ≤ the 3 Hz rule trivially), auto-dismiss after a few
seconds or on first touch. Reads NO bio (freeze rule), adds NO sheet. This is what
makes law #1 actually discoverable — a user has no other way to learn "finger on
the camera". HELD until 2a's permission-timing is settled so the two don't fight.

### 2c — wonder-first copy + shortened intro (FOUNDER SIGN-OFF)
Flip the onboarding + ready copy from metric-first to wonder-first per the STANCE
("lead with WONDER not the metric; pulse/HRV is an honest footnote, not the
hero"). Shorten the 3-page intro toward the safety gate + one wonder line. Brand
voice is the founder's — I draft options, founder picks tone. NOT autonomous.

## This cycle's ship (honest, non-speculative)
- The PLAN above (sanctioned "ERST PLAN + Council").
- Fix the FACTUALLY FALSE `OnboardingView` header comment ("v10 Beat-MVP does not
  read biometrics on the audio path") — a correctness fix so a future session
  isn't misled; comment-only, zero behavior change.

## Sequence to execute (on founder return / next cycles)
1. 2a wired (confirm permission-timing on device).
2. 2b invitation leaf (mandatory ui-state reviewer).
3. 2c copy — founder drafts/approves tone.

Depends on nothing risky; each slice is reversible. No audio-thread, no Rausch
triad, no sheet growth, no ancestor bio read.
