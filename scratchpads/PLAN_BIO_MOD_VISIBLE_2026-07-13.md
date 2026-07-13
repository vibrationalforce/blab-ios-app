# PLAN — Item 2: Bio-Modulation LIVE sichtbar (2026-07-13)

**Founder-Ask (Reihenfolge-Item 2):** "welche Parameter das Biofeedback bewegt —
live sichtbar. Leaf-Views, KEIN 30-Hz-Read im Root/Ancestor (Menü-Freeze-Gesetz)."

## Ist-Zustand (auditiert)
- `Core/FXModulation.swift` — reiner Kern: `FXModRoute { carrier: FXModCarrier (bio(ModSource)|lfo), target: FXModTarget, depth, bipolar, curve, enabled }`. Pure Mapping-Helfer (`offset`, `combine`, `value`). Linux-getestet.
- `Tools/FXBioModulator.swift` — `@MainActor @Observable`, ~30-Hz-`tick()`: liest `bus.freshBio()`, summiert Route-Offsets pro Target, schreibt in `EchoelFXChain`. **`routes` ist observable; die LIVE-Beiträge (Signal/Offset pro Route/Target) sind NICHT observable** — nur intern in `tick()`.
- Kein Display existiert, das zeigt "Puls bewegt gerade Filter Cutoff um +X".

## Gesetz (kritisch)
30-Hz-`@Observable` NIE im Root/Ancestor lesen → reißt offene Menüs/Picker ab (Menü-Freeze, CLAUDE.md 10.76.41/48/50). **Nur** in einer eigenen Leaf-`View`, die ihren eigenen Lese-Takt hat.

## Design (law-abiding)
1. **Modulator publiziert einen NIEDRIG-Rate-Snapshot** (nicht die 30-Hz-Kette in die UI ziehen):
   - Neuer Wert-Typ `BioModContribution { routeID, carrierName, targetName, signal01, offset, unit }` (pure, Sendable, Testable).
   - `FXBioModulator` bekommt `public private(set) var liveContributions: [BioModContribution] = []` (observable), aktualisiert in `tick()` **gedrosselt auf ~8–10 Hz** (Zähler: nur jeden N-ten Tick schreiben), damit die Observation-Last niedrig bleibt. Kein Audio-Thread-Bezug (control-plane).
   - Wenn `!isRunning` oder keine aktiven Routes → `[]` (Anzeige "Keine Bio-Modulation aktiv").
2. **Leaf-View `BioModulationLiveView`** (eigenes Struct, liest NUR `modulator.liveContributions`):
   - Pro Contribution eine Zeile: `Carrier → Target` + horizontaler Balken (signal01) + aktueller Wert/Offset (EchoelValueField-Lesestil, dimensionslos = rohe Dezimalzahl).
   - Flash/Bewegung ≤ ruhig; Balken slewt (keine harten Sprünge, ratenbasiert genügt hier optisch — 10 Hz).
   - Uncodixfy: legible Zahl zuerst, Balken zweitrangig; keine Glow/Neon.
3. **Tür:** eine bestehende Sheet-Slot/Sektion wiederverwenden (KEINE neue `.sheet` an die Kette hängen — SIGSEGV-Gesetz). Kandidat: als Sektion in `EchoelFXView` (wo die Routes eh editiert werden) ODER am Track-Head-Menü ("Bio-Modulation (live)"). Erst prüfen, wo ohne Sheet-Wachstum machbar.

## Test-first
- `BioModContributionTests`: bei gegebener Route + Frame liefert der Snapshot-Builder den erwarteten `signal01`/`offset` (nutzt `FXModulation.offset` + `ModSource.normalizedValue`) — reiner Wert-Test, kein 30-Hz-Timing.
- Drossel-Test: `liveContributions` wird nur alle N Ticks neu gesetzt (Zähler-Logik als pure Funktion herausziehen: `shouldPublish(tick:everyN:)`).
- Leer-Zustand: `!isRunning` → `[]`.

## Council
Neue sichtbare Fläche + >1 Datei → kurz Council (Architect/Vision/Skeptic/User-Advocate): ist der Live-Balken "wow + kontemplativ" genug oder nur ein Debug-Meter? Vision-Keeper: das ist der KERN der Echoel-These (Körper bewegt den Klang sichtbar) — verdient Sorgfalt, nicht Dev-HUD-Look.

## Reihenfolge-Notiz
AUv3-Struktur "sitzt" nach U3b (Param-Vereinheitlichung + Per-Spur-Belegung sichtbar/setzbar). U5 (State-Recall Auto-Reload) = spätere Stabilitäts-Passe. Item 3 (externe AUv3 erlebbar) durch U3b bereits vorangebracht. Nächster numerischer Punkt = dieser (Item 2).
