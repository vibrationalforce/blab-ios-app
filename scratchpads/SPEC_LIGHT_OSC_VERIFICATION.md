# Hardware verification recipe — ADM-OSC · Art-Net · sACN (with Roman / Deufel)

Echoel emits open-standard wire protocols; the code + packet kernels are unit-tested,
but on-the-wire reception needs real receivers. This is the on-site checklist so the
output can be confirmed in minutes against a monitor or a real rig.

Prereqs: iPhone + laptop on the SAME Wi-Fi/LAN. iPhone Settings → Privacy → Local
Network → allow Echoelmusic. Start a bio source in the app (Demo is fine for wire-test).
Find the laptop's LAN IP (macOS: System Settings → Network, e.g. 192.168.1.50).

## 1) ADM-OSC (immersive object out) — Sync tab → "Send to immersive rig"
- Set Host = laptop IP, Port = 9000, Object = 1, toggle ON.
- Monitor options:
  - **Protokol** (Hexler, free OSC monitor) — listen on UDP 9000.
  - or `python-osc`: `python -m pythonosc.osc_server` style dump, or a 5-line dispatcher on 9000.
- Expect (values move with the body):
  - `/adm/obj/1/position/azimuth`  float −180…180  (breath)
  - `/adm/obj/1/position/elevation` float 0…60     (HRV)
  - `/adm/obj/1/position/distance` float 0…1       (1−coherence)
  - `/adm/obj/1/gain`              NOT sent by the bio arm (#215 — nothing measures
    motion). It appears only while notes SOUND, from the music arm
    (`MusicMediaMap.admMessages`, master level → 0.3…1). If the rig is silent and you
    see no /gain at all, that is the expected result, not a fault.
- Into a real renderer: point Host at the **FletcherMachine / L-ISA / d&b / SPAT**
  controller's ADM-OSC input; object 1 should move. Validate ranges with the
  `immersive-audio-live/ADM-OSC` repo's Python stress-test if a renderer rejects values.

## 2) Art-Net (DMX over IP) — Sync tab → "Send to lighting rig"
- Set Host = the Art-Net node IP (or 255.255.255.255 broadcast), Universe = 0, ON.
- Monitor options:
  - **DMX Workshop** (Artistic Licence, Win) or **Art-Net View**, or **QLC+** (free,
    cross-platform) with an Art-Net input universe, or a hardware node (ENTTEC ODE etc.).
- Expect ArtDMX on UDP 6454, universe 0, channels:
  - ch1 dimmer ← coherence (0.3…1), ch2 R ← heart rate, ch3 G ← HRV, ch4 B ← breath.
- Real fixture: a 4-ch RGB+dimmer fixture patched at universe 0 / address 1 should
  fade with the body (no strobing — values are smoothed, ≤3 Hz).

## 3) sACN / E1.31 — Sync tab → "Send to sACN rig"
- Shipped as **UNICAST**: set Host = receiver IP, Universe = 1, ON. (Multicast button
  fills 239.255.x.x but needs Apple's multicast entitlement — defer until granted.)
- Monitor options:
  - **sACNView** (free), **QLC+** sACN input, **DMX Workshop** (sACN), or a node that
    speaks E1.31 (most modern nodes do).
  - Point the receiver to accept unicast on universe 1 (some default to multicast only —
    set it to listen for unicast, or use a node that accepts both).
- Expect an E1.31 Data Packet on UDP 5568, universe 1, 512 slots, start code 0; same
  4-channel fixture mapping as Art-Net.

## Quick sanity without any console
`tcpdump`/Wireshark on the laptop, filtered:
- ADM-OSC: `udp port 9000`  · Art-Net: `udp port 6454`  · sACN: `udp port 5568`
Seeing periodic packets (~30 Hz light, ~10 Hz OSC) that change as you breathe = ✅.

## Status
- Code + kernels: unit-tested, shipping (Art-Net build 1543; sACN + OSC full-res events next build).
- Wire reception: to be confirmed on-site with Roman (Adamson/FletcherMachine) and/or
  Felix Deufel (Grapes/ZiMMT) using the above. Log results back into decisions.csv.
