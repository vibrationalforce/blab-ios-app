# PLAN — Full-Vision Apple-Ecosystem Loop (Ralph Wiggum Lambda)

**Goal (owner-set, 2026-06-01):** Realize the *complete* echoelmusic.com vision across the
**entire Apple ecosystem** — not a reduced MVP — by converging through atomic one-cycle loops.

**Mode:** Ralph Wiggum Lambda. ONE target/feature per cycle. Build → verify → ship → loop.
No batching. Build-green is the only gate. Each cycle ≤3 files where possible.

---

## 0 · Canonical decisions (locked this cycle)

1. **CI generator = XcodeGen `project.yml`.** `testflight.yml` runs
   `xcodegen generate --spec project.yml`. Anything not in `project.yml` does **not** ship.
   `Project.swift` (Tuist) is the *reference* for porting ecosystem targets — it already
   declares Widgets / Watch / TV / Vision / Mac — but is **not** the shipping spec.
2. **Signing-safe pattern (the repo's hard-won rule).** Never embed a new extension/target
   blind. For each new target: (a) add to `project.yml` with its dependency **OFF** the main
   app, confirm it *compiles* via CI `build_only=true`; (b) only then wire it as an embedded
   dependency + verify `com.echoelmusic.app.<suffix>` provisioning resolves under automatic
   signing (`-allowProvisioningUpdates` + ASC API key); (c) then `build_only=false` to TestFlight.
   This is exactly why AUv3 stays dependency-disabled until provisioning is confirmed.
3. **No new top-level `Sources/` dirs** without approval. Per-platform target sources live
   under their own `Sources/Echoelmusic<Platform>/` (Widgets, Watch already scaffolded in Tuist).
4. **App Group `group.com.echoelmusic`** is the cross-surface bus. Bio vitals flow
   phone → App Group → every surface via the existing `BioFeedbackManager` bridge.

---

## 1 · echoelmusic.com surface → Apple platform map

The website promises one body-driven instrument across every surface. Mapped to where each
surface most naturally lives in the ecosystem:

| Website promise | Primary surface | Secondary | Status today |
|---|---|---|---|
| "Your body is the controller" (HR/HRV/breath/motion) | iPhone (HealthKit/Polar) + **Watch** (on-wrist HR) | Vision | iPhone LIVE; Watch ❌ |
| Full production studio (synth/seq/mix/export) | iPhone | **Mac** (desktop DAW surface) | iPhone LIVE; Mac ❌ |
| Living visuals (Metal) | iPhone | **Vision** (immersive), **TV** (big screen) | iPhone PARTIAL |
| Film & stream (capture / RTMP) | iPhone | Mac | capture PARTIAL; RTMP **0 code** |
| Control any light (DMX/Art-Net) | iPhone/Mac (LAN) | — | **0 code (ROADMAP)** |
| Glanceable bio + transport | **Widgets** (Home/Lock) | Watch complications | ❌ |
| Live alerts (session/stream events) | **Notification Service** ext | — | ❌ deferred |
| Instant try (no install) | **App Clip** | — | ❌ deferred |

---

## 2 · Loop backlog (ordered — one cycle each)

> **Execution-ready diffs per target:** `scratchpads/SPEC_ECOSYSTEM_TARGETS.md` (exact
> `project.yml` blocks, entitlements, Info.plists, source lists — each follow cycle is pure
> execution). **Cross-cutting prerequisite (Cycle CX):** the app's `BioFeedbackPublisher` is
> dormant (never started) and nothing reloads `WidgetCenter` — wire both before any glance
> *content* cycle, else widget/watch show "No session yet".

Ordered by *value ÷ signing-risk*. Earliest cycles are zero new-signing (compile-only or
content), so the green pipeline is never bet on a blind embed.

### Phase E — Ecosystem scaffolding (port Tuist → XcodeGen, signing-safe)
- **C1 — Green baseline.** Dispatch CI `build_only=true` on this branch; confirm iOS + AUv3
  still archive after the doc cycle. Record run #. *(No code.)*
- **C2 — Widgets target (compile-only).** Port `EchoelmusicWidgets` from `Project.swift` into
  `project.yml`, dependency OFF main app. CI `build_only` → confirm it compiles. Files:
  `project.yml`, (existing) widget source.
- **C3 — Widgets embed + provision.** Wire as embedded extension; verify
  `com.echoelmusic.app.widgets` provisioning resolves. CI `build_only=false`.
- **C4 — Widget content.** Live bio widget (HR / HRV / coherence) reading App Group via
  `BioFeedbackManager`. TimelineProvider, ≤3 entries/cadence. WCAG: no flashing.
- **C5 — watchOS target (compile-only).** Port `EchoelmusicWatch` into `project.yml`,
  dependency OFF. CI compile.
- **C6 — watchOS embed + provision** (`com.echoelmusic.app.watchkitapp`). CI ship.
- **C7 — watchOS content.** On-wrist HealthKit HR → App Group → phone bio bus. Honor the
  hard constraint: Watch HR ~4–5 s latency → **display/trend only, NO beat-sync** (CLAUDE.md).

### Phase D — Desktop & immersive (Universal Purchase, shared `com.echoelmusic.app`)
- **C8 — macOS target.** Decision first: native AppKit/SwiftUI vs Mac Catalyst. Strategy doc
  says native Mac (ship before Loopy Pro Mac). Port `EchoelmusicMac` to `project.yml`,
  compile-only, then signing.
- **C9 — visionOS target.** Port `EchoelmusicVision`; immersive bio-reactive visual scene.
- **C10 — tvOS target.** Port `EchoelmusicTV`; big-screen visuals / installation output.

### Phase X — Extensions & reach
- **C11 — Notification Service extension** (`…notification-service`): session/stream event alerts.
- **C12 — App Clip** (`…clip`): instant bio-reactive demo, no install.

### Phase F — Feature depth toward full website parity (per-platform, after surfaces exist)
- RTMP live stream (HaishinKit — the *one* sanctioned new dependency; currently **0 code**,
  no `Sources/.../Stream/` dir despite CLAUDE.md claim). Add only after iPhone surface stable.
- EchoelLux (DMX-512 / Art-Net 4 over LAN) — `NSLocalNetworkUsageDescription` already declared.
- EchoelStage (NDI/Syphon, projection) — integrate, don't reimplement.
- EchoelAI (on-device CoreML, bio-reactive only — never generative/cloud).
- EchoelLoop canvas module (Loopy-Pro-style widgets, bio-modulated) — the Tools-tab payload.

---

## 3 · Per-cycle definition of done
1. `project.yml` change is minimal and the **main iOS app still archives green** (never regressed).
2. New target compiles in CI before it is embedded; embedded before it gets real content.
3. No force-unwrap / no audio-thread allocation / `os_log` only / WCAG ≤3 Hz flash.
4. Conventional commit; `metrics.jsonl` appended; this file's backlog checkbox advanced.
5. No esoteric copy; science-first bio displays (legible numbers > decoration).

---

## 4 · Open owner-gated items (do not guess)
- **macOS: native vs Catalyst?** (affects C8 scope substantially.)
- **`com.echoelmusic.app.voice`** (`EchoelVoice` AUv3 in `Project.swift`) — register in ASC,
  fold into `…auv3`, or drop? (`APP_STORE_CONNECT.md` note.)
- **App Group mismatch:** `fastlane/Appfile` comments say `group.com.echoelmusic.shared`;
  entitlements say `group.com.echoelmusic`. Confirm the portal-registered ID before Watch/Widgets
  rely on it — a mismatch breaks extension provisioning.
- **GitHub PAT rotation** (owner pasted token in plaintext 2026-06-01 → rotate; never committed).

---

*Cycle 0 (this file + `APP_STORE_CONNECT.md` truth-fix) establishes the track. Next: C1 green
baseline dispatch, then C2 Widgets compile-only.*
