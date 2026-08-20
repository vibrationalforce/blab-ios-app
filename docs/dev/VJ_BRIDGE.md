# Echoel → VJ / Visual / Broadcast bridge

**Echoel is the bio-driven SOURCE at the front of your pipeline.** It already speaks
the input languages of the major pro tools over open standards — so your body, breath
and music can drive Resolume, TouchDesigner, OBS, lighting desks and spatial rigs
**without cloning any of them**. This is the connective layer of the Signal Router
(Tools ▸ Routing): tap a source → a destination, and the bytes flow.

> Everything below ships today (OSC · Art-Net/sACN · ADM-OSC) except where marked.
> Turn an output on by making a connection to it in the patchbay.

---

## 1. OSC out — the universal control feed

Connect **Body** (and/or **Music**) → **OSC Out** in the patchbay, then point the
receiving app at the phone's IP (UDP). Default namespace:

> ⛔ **Every bio address is sent only while its own channel is actually measured (#245).**
> Silence means "not measured" — never "measured as zero" — and your receiver simply holds
> its last value, which is what you want when a finger slips off the camera mid-set. A
> structural 0 would instead collapse a bound scale or slew a Grand Master to black, with
> nothing on the wire to tell that apart from a performer who really stopped.
>
> Two consequences worth knowing BEFORE you build a mapping:
> · A channel-creating receiver (TouchDesigner's OSC In CHOP) will not create a channel that
>   has never been sent. If an address is missing from your CHOP, the sensor has not measured
>   it yet — it is not a connection fault.
> · `/coherence` is the one most likely to stay absent for a whole take. It needs ≥16 accepted
>   RR intervals; the chest strap reaches that after ~16 beats, but the **camera** derives its
>   RR series from a fixed 10-second window (~10 intervals at a resting heart rate), so on a
>   camera session it may never appear. Map coherence when you are on a strap.

| Address | Range | Meaning |
|---|---|---|
| `/echoelmusic/bio/synthetic` | 0 or 1 | **whose body this is.** 1 = the built-in DEMO generator, 0 = a real measured source. Sent FIRST in every tick that carries at least one value, and omitted entirely from a silent tick — so it never arrives alone. **Latch it as state, do not treat it as a prefix:** these are separate UDP datagrams and UDP does not preserve order, so it may land after the values of its own tick; it repeats every tick (~1 Hz) and only changes when the player switches source. If you never see this address while values are arriving, you are talking to an Echoel build that predates this address (it was added with the OSC provenance slice). It answers "is this a body", not "which sensor". |
| `/echoelmusic/bio/heart/bpm` | 40–200 | heart rate — only with a measured pulse |
| `/echoelmusic/bio/heart/hrv` | 0–1 | normalized HRV — needs a pulse AND a non-zero HRV |
| `/echoelmusic/bio/heart/rmssd` · `/sdnn` · `/pnn50` | ms / ms / % | HRV detail (trusted source) — same rule: a pulse plus a real value |
| `/echoelmusic/bio/breath/rate` | 3–40 | breaths per minute — sent only inside that plausibility band |
| `/echoelmusic/bio/breath/phase` | 0–1 | inhale→exhale phase (great for smooth motion) — rides the RATE's gate, never its own value, because 0 is a real position |
| `/echoelmusic/bio/coherence` | 0–1 | HRV coherence — see the note above; frequently absent |
| `/echoelmusic/bio/motion` | 0–1 | body motion energy — **NOT SENT today** (#215): no CoreMotion provider exists, every publisher writes `motionEnergy: 0`. It used to arrive as a constant 0, which no receiver can tell apart from a performer standing still; now the address simply does not appear. It returns when a motion sensor does. |
| `/echoelmusic/bio/event/heartbeat` | trigger | per-beat bang (flash on the beat) |
| `/echoelmusic/bio/event/breath/inhale` · `/exhale` | trigger | breath onsets |
| `/echoelmusic/bio/event/coherence` · `/eeg` · `/motion` | trigger | onset bangs (the `/motion` bang cannot fire while motion energy is a constant 0) |

Music parameters (current chord/pitch/level) drive the Light + Spatial adapters
below; raw musical OSC is on the roadmap (OSCQuery auto-typing).

### Resolume (Arena / Avenue)
1. Echoel: patchbay → connect **Body** → **OSC Out** (and set Resolume's IP/port).
2. Resolume: *Preferences ▸ OSC* → enable input.
3. Right-click any parameter (layer opacity, effect amount, speed) → **Edit OSC** →
   move Echoel (breathe) → Resolume learns the address. Map `breath/phase` to opacity
   or `coherence` to an effect mix for a body-reactive set.

### TouchDesigner
Add an **OSC In DAT/CHOP**, set the port, and the `/echoelmusic/...` channels appear
as named CHOP channels — patch them into anything.

---

## 2. Light — Art-Net / sACN (DMX)

Connect **Music** or **Body** → **Art-Net** (or **sACN**) in the patchbay. Echoel maps
the live chord to colour (`SpectralColor.physicalColor(forChord:)` — octave-transposed into
visible light via CIE 1931, mixed perceptually in OKLab) and sends DMX — drive fixtures
or a lighting desk directly. Bio is the fallback co-modulator when nothing is sounding.
Flash-safety is slew-limited (≤3 Hz, WCAG). See `MusicMediaMapping.swift`.

## 3. Spatial — ADM-OSC

Connect **Music**/**Body** → **ADM-OSC (spatial)**. Echoel emits `/adm/obj/{n}/*`
immersive-object positions (pitch → azimuth, level → distance/gain) for L-ISA / d&b
Soundscape / FletcherMachine and any ADM-OSC renderer.

> ⛔ **The BIO arm follows the same measured-only rule as the OSC feed (#260).** While no
> notes are sounding, the object is positioned from the body: breath phase → azimuth,
> HRV → elevation, coherence → distance. Each of those is sent **only while its own channel
> is measured**, so an object simply stops being driven on an axis rather than being driven
> to a structural zero — which on two of the three axes is an extreme, not a neutral: an
> unmeasured breath would read as hard left, an unmeasured coherence as maximum distance.
> OSC has no "unset", so a renderer keeps the last value it received on that address — plan
> your scene to start from a sane position: Echoel will not push the object to a default. `distance` is the axis most likely to stay
> absent for a whole take (coherence needs ~16 beats, and a camera session may never reach
> it). `/adm/obj/{n}/gain` is driven by the MUSIC arm from the master level; the bio arm
> leaves it alone while nothing measures motion (#215).

## 4. MIDI / MPE out (+ thru)

Connect **Music** → **MIDI Out** to play a DAW (Ableton/Logic) from the body-composed
take. Connect **MIDI In → MIDI Out** for thru: your hardware controller echoes to the
DAW while also playing Echoel.

---

## 5. Broadcast — straight from the phone (no laptop, no OBS)

Echoel's edge over OBS is **phone-native streaming**: Tools ▸ Broadcast → pick RTMP/SRT,
paste the ingest URL + stream key, **Go Live**. (Engine integration: HaishinKit, in
progress — the destination config + routing ship now; see `BroadcastPublisher.swift`.)
You can also arm it from the patchbay: connect a source → **Broadcast (RTMP/SRT)**.

For hybrid setups, feed OBS/Resolume as a source via NDI (roadmap) or send OSC to
control OBS through a bridge (obs-websocket).

---

## The one idea

We don't rebuild Ableton, Resolve, Resolume or OBS. **Echoel is the body-driven
generator they all lack**, wired to them over open standards. The moat is the body;
the bridge is this router.
