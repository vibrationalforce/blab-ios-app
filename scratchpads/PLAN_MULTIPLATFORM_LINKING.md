# Multiplatform Linking — iPhone-First, Inclusively Connected

**Authority:** Owner direction 2026-05-30 — *"iPhone First. Alle Plattformen sollen creativ
und inclusiv sinnvoll miteinander verknüpft werden."*

The principle: **iPhone is the instrument and the hub.** Every other Apple surface is not a
separate app to maintain — it is a *meaningful extension* of the live iPhone session, sharing
state through one App Group (`group.com.echoelmusic`) and the typed `EngineBus`. We ship
iPhone first; each surface lands in its own dedicated cycle, never speculatively.

## Roles (how each surface extends the instrument)

| Surface | Bundle | Creative + inclusive role |
|---|---|---|
| **iPhone app** | `com.echoelmusic.app` | The hub. Sensing (heart/breath/motion), synthesis, video, RTMP, OSC/MIDI/MPE I/O, the live session of record. |
| **AUv3** | `…app.auv3` | Echoel as an instrument *inside* other DAWs (Logic, AUM, Cubasis) — the bio-reactive voice travels into existing workflows. |
| **watchOS** | `…app.watchkitapp` | On-body sensing + glanceable bio state + transport remote. Performer-worn control without touching the phone. **Constraint:** Watch HR ≈ 4–5 s latency → NO beat-sync; use Polar H10 for tight loops. |
| **Widgets** | `…app.widgets` | Lock/Home-screen surfacing of live or last-session bio + session state. Inclusive at-a-glance access, no app launch. |
| **App Clip** | `…app.clip` *(deferred)* | Zero-install entry for installations/events: scan a code at a venue → instant bio-reactive experience. Inclusion = no download barrier. |
| **Notification Service** | `…app.notification-service` *(deferred)* | Rich session/stream/coherence notifications (e.g. "stream live", "coherence peak"), enriched media. |
| **macOS / visionOS / tvOS** | `com.echoelmusic.app` (universal) | Big-canvas performance + broadcast: Mac for the studio/stage rig, visionOS for spatial/immersive, tvOS for venue/cinema display. Universal Purchase = buy once, perform anywhere. |

## Shared spine (so links are "sinnvoll", not bolted-on)

1. **App Group `group.com.echoelmusic`** — shared session/bio state across app + extensions.
2. **`EngineBus` topics** (`bioFrames` / `controllerEvents` / `bioEvents`) — the contract any
   surface subscribes to; no point-to-point coupling.
3. **OSC `/echoelmusic/bio/*` + MIDI/MPE** — the open boundary to external stage tools, DAWs,
   lighting, and other devices, so the instrument is inclusive of any rig.

## Sequencing (don't scaffold ahead of need)

1. iPhone hub — current focus, ship to TestFlight first.
2. Widgets + watchOS — already have targets; wire to shared state after TestFlight is green.
3. App Clip + Notification Service — registered in ASC; add targets in their own cycles with
   entitlements + provisioning verified (see `docs/dev/APP_STORE_CONNECT.md`).
4. macOS / visionOS / tvOS — universal-purchase canvases, post-MVP.

**Hard rule:** one surface per cycle, each with its own build-green gate. iPhone parity first.
