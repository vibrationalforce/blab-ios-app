# ECHOEL SESSION PROTOCOL — v1

Status: **draft, schema v1** · Source of truth for the wire types:
`Sources/Echoelmusic/Core/SpatialScene.swift` (S1). This document and those
types change **in the same commit** (P3 protocol-first rule, spatial
expansion prompt v2.0).

## Purpose

One transport-agnostic contract for sharing a spatial **scene** (audio
objects + room + listener) between Echoel peers and external renderers.
State sync only — **never audio** (audio renders locally on every peer;
"wir streamen den Puls, nicht das Audio"). Transports that may carry these
messages later: MultipeerConnectivity, SharePlay GroupSession messenger,
WebSocket. The protocol does not know or care which.

## Principles

- **P1 capability, not platform** — any client that speaks this JSON is a
  peer, whether it runs Echoel, a lighting desk bridge, or a browser view.
- **P2 every device is a peer with a role** — see Roles below; capability
  is enforced by role, not by device type.
- **P3 protocol-first** — types and this spec co-evolve in one commit.
- **P4 portable core** — payloads are plain JSON of Foundation-only value
  types; no Apple-specific types on the wire.

## Coordinate convention (ADM / ITU-R BS.2076)

| Field | Unit | Range | Meaning |
|---|---|---|---|
| `azimuth` | degrees | −180 … +180 | 0 = front, positive = LEFT (counter-clockwise) |
| `elevation` | degrees | −90 … +90 | positive = up |
| `distance` | normalized | 0 … 1 | room-relative (1 = room reference radius) |

Cartesian (derived, never on the wire): x = right, y = front, z = up.
Same convention as the shipping `ADMOSCSender` (`/adm/obj/{n}/position/*`).

## Roles (P2)

| Role | canEditScene | canAdjustMix | canPerform | rendersOutput |
|---|---|---|---|---|
| `author` | ✓ | ✓ | ✓ | — |
| `performer` | — | — | ✓ | — |
| `renderer` | — | — | — | ✓ |
| `mixControl` | — | ✓ | — | — |
| `observer` | — | — | — | — |

A device may hold multiple roles (stage iPhone = `performer` + `renderer`).
Receivers MUST ignore messages whose sender's role does not permit the
action (e.g. a `scene.diff` that adds objects from a non-author).

## Message envelope

Every message is one JSON object:

```json
{
  "v": 1,
  "seq": 42,
  "sender": "peer-uuid-string",
  "roles": ["author", "performer"],
  "type": "scene.diff",
  "payload": { }
}
```

- `v` — protocol major version. A receiver MUST discard messages with a
  higher major version than it speaks (and MAY report it).
- `seq` — per-sender monotonic counter; receivers drop duplicates/reorders.
- `sender` — stable peer id (UUID string, chosen once per install).
- `roles` — the sender's roles, asserted at session join and repeated in
  each message so late joiners need no lookup.
- `type` / `payload` — see below.

## Message types (v1)

### `hello` — session join
Payload: `{ "name": "<display name>", "roles": [...], "sceneRevision": <n|null> }`
The author answers a `hello` with `scene.full`.

### `scene.full` — complete scene document
Payload = `SpatialScene` JSON (below). Sent by the author on join, on
request, or as periodic keyframe. Receivers replace their scene wholesale
when `revision` is newer.

### `scene.diff` — incremental update
Payload = `SpatialScene.Diff` JSON (below). Applied only when the local
scene's `revision` is the diff's base (i.e. `toRevision` follows what the
receiver has); otherwise the receiver requests `scene.full` via `resync`.

### `resync` — request a keyframe
Payload: `{ "haveRevision": <n> }`. The author responds with `scene.full`.

### `bye` — orderly leave
Payload: `{}`. Peers SHOULD remove `ownerPeer`-owned objects of a departed
performer after a grace period (author's decision, not automatic).

Live high-rate control values (bio frames, object motion at frame rate) are
**not** protocol messages in v1 — they stay on the existing OSC/ADM-OSC
paths. This protocol carries *structure*, OSC carries *streams*.

## Payload schemas (v1)

### SpatialScene

```json
{
  "version": 1,
  "revision": 7,
  "objects": [ SpatialObject, ... ],
  "room": RoomModel
}
```

### SpatialObject

```json
{
  "id": "voice-1",
  "position": { "azimuth": -30.0, "elevation": 10.0, "distance": 0.8 },
  "extent": 0.0,
  "gain": 1.0,
  "roomSend": 0.2,
  "motionRef": null,
  "visualRef": null,
  "ownerPeer": null
}
```

`id` is immutable for the object's lifetime. `extent`, `gain`, `roomSend`
are 0…1. `motionRef` (Layer 7 trajectory id), `visualRef` (Layer 3 AV
object id) and `ownerPeer` are optional strings, omitted or `null` when
unset.

### RoomModel

```json
{
  "width": 8.0, "depth": 10.0, "height": 4.0,
  "decayTime": 1.2, "diffusion": 0.7,
  "listener": { "x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0 }
}
```

Sizes in meters (1…200 wall, 1…60 height), `decayTime` seconds (0.1…30),
`diffusion` 0…1, `listener.yaw` degrees −180…+180 (0 = facing +y).

### SpatialScene.Diff

```json
{
  "added": [ SpatialObject, ... ],
  "removed": [ "object-id", ... ],
  "changed": [ SpatialObject, ... ],
  "room": RoomModel | null,
  "toRevision": 8
}
```

## Versioning rules

- **Major** (`v` in envelope, `version` in scene): breaking change — new
  required field, changed semantics. Receivers reject higher majors.
- Additive optional fields do NOT bump the major; decoders MUST ignore
  unknown keys (Swift `Codable` default behaviour).
- `revision` orders scene states within a session; `seq` orders messages
  per sender. Neither survives a session — persistence is out of scope v1.

## Out of scope (v1, by design)

Audio transport (never), clock/transport sync (ADR-002 — tendency
SharePlay), authentication (session-invite trust model for now), motion
trajectory definitions (Layer 7 — will add a `motion.*` message family and
bump to v2 when they land).
