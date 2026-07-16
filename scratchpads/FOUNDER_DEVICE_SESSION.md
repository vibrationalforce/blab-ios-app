# Founder Device Session — EINE Sitzung, alles abhaken (2026-07-16)

**Warum dieses Dokument:** Der projektweite Audit (2026-07-16, wf_a57ff877-49d) hat den
einen echten strategischen Engpass benannt: **352 geräte-unverifizierte Commits unter dem
TestFlight-Freeze, zwei DEFAULT-ON-Flags auf dem Kern-Klangpfad.** Der Founder ist der
einzige Geräte-Prüfer (single point of failure). Statt pro Punkt zu blockieren, bündeln wir
ALLE geräte-/urteils-gebundenen Punkte in EINE Sitzung am Freeze-Lift.

> **Regel:** Solange dieser Freeze läuft, baue ich autonom weiter (flag-OFF, reversibel).
> NICHTS hiervon wird geflippt/eingereicht, bis du es an EINEM Gerät geprüft hast.
> Rollback für jedes Flag: `FeatureFlags.set(.<flag>, false)`.

---

## A · Kern-Klangpfad verifizieren (die zwei DEFAULT-ON-Flags)

- [ ] **multiRoll** — zwei dichte MIDI-Spuren gleichzeitig hörbar? Jede mit eigenem Timbre?
      CPU < 30 %, Speicher im Rahmen (Xcode-Gauge beim Spielen)?
- [ ] **laneAUInstruments** — ein Drittanbieter-AUv3-Instrument einer Spur zugewiesen → spielt
      es? Kein Stuck-Note beim Mid-Take-Wechsel?
- [ ] Menü/Picker reagiert flüssig während Biofeedback läuft (kein 10-Hz-Freeze)?
- [ ] Launch bleibt still bis zum ersten Arm (keine Bio-Stimme beim Start)?
- **Wenn ein Flag fehlschlägt:** `FeatureFlags.set(.<flag>, false)` = Ein-Zeilen-Rollback,
      dann melde mir den Symptom-Fall (device-log-triage / watch-clip).

## B · S2-W2 „Spur = Instrument" — Slice-7-Geräte-Gate (Flag `voiceKindRouting`, aktuell OFF)

Erst NACH bestandenem Gate flippe ich Slice 8 (den fxBus-Pin — irreversibel-ish, macht
`TrackInstrument.fxBus` zur Engine-Zusage). Prüfen mit Flag testweise ON:

- [ ] **Drums-Spur trommelt** (Kit statt Poly) — Groove OHNE Becken testen (das 4-Pad-Kit
      voiced GM-Becken 49/51/55/57/59 aktuell als gestimmte Toms; Becken-Pad ist ein
      späterer Ausbau, kein Blocker).
- [ ] **Bass-Spur wummert** fühlbaren Sub (Oktav-Fold-Band) — und **bei A≠440 in Tune**
      (der Kammerton-Fan aus Slice 5 muss greifen; teste einmal mit A=432).
- [ ] Poly-Spuren unverändert; kein Menü-Freeze; CPU < 30 % bei 4-Spur-Doc.
- [ ] Kein hängender Ton beim Mid-Take-Instrumentwechsel.
- [ ] **Live-Same-Region-Instrumentwechsel** (S2-W2-6 Code-Review-LOW): ändere die
      builtinInstrument der PRIMARY-Lane MITTEN im Take ohne Region-Grenze zu kreuzen —
      der Roll bindet die Kind-Stimme erst an der nächsten Region-Grenze / beim
      Transport-Restart neu (refreshStructure feuert rollKindSink nur bei
      oldActive≠newActive). Falls das am Gerät stört, ist der Fix ein gezieltes
      rollKindSink-Re-Fire bei builtinInstrument-Change (kein Blocker fürs Gate).
- **Design-Bestätigung nötig:** der `.drums`-Bus-Effekt ist EIN geteilter Charakter über
      BeatPlayer UND alle Lane-Kits (kein Per-Lane-Kit-FX in v1). Ist das gewollt? (Per-Lane-
      Kit-FX wäre ein separater, aufgeschobener Workstream.)

## C · App-Store-Wahrheit verifizieren (2 Beschreibungs-Zeilen)

- [ ] **BLE-Gurt end-to-end** (Polar H10, jetzt bestellt): Gurt anlegen → Puls-Pille zeigt den
      Gurt-Namen, HR/HRV kommt an, überlebt Foreground. Die Listing-Zeile nennt „Polar,
      Wahoo, Garmin".
- [ ] **AUv3 im Fremd-Host** (AUM / GarageBand): Echoelmusic als Plugin geladen, spielt. Zeile
      nennt „AUv3 inside Logic, GarageBand or AUM".
- **Wenn eins fehlschlägt:** ich tausche die exakte Zeile per Ein-Commit gegen eine
      abgeschwächte Fassung VOR dem Submit (Fallback-Zeilen schreibe ich vor).

## D · Screenshots (nur du, am echten Gerät)

- [ ] 6.9" Set (1320×2868), 8 Shots laut `docs/dev/APP_STORE_LISTING_v1.md` — die ersten 3:
      (1) Instrument spielt + Bio-Strip, (2) Immersive Visual, (3) „Generate from Body".
      Captions sind fertig getextet (keyword-tragend) — verbatim übernehmen.
- [ ] 6.5" Set falls bequem.

## E · Ein-Feld-App-Store-Entscheide (kurz bestätigen)

- [ ] Privacy-Label = **„Data Not Collected"** (on-device, kein Server/Analytics/Account) — OK?
- [ ] Kategorie Music + Health & Fitness — OK?
- [ ] Preis Free, kein IAP in v1.0 — OK (Echoel Live = v1.1)?

---

## F · Piano-Roll-Editing (#58 „nicht mehr rudimentär") — kurz durchspielen

- [ ] **Note verschieben** (Body ziehen → neue Tonhöhe/Position), **Länge ziehen**
      (rechte Kante), **Velocity malen** (die Lane UNTER dem Raster). Alles über die
      eine Geste, entschieden beim Antippen. Fühlt sich das flüssig an?
- [ ] **Velocity-Lane-Erreichbarkeit (Slice-4b-Entscheid):** die Lane sitzt aktuell
      UNTER den 49 Tonreihen — im Editor NACH UNTEN scrollen, um sie zu sehen. Frage:
      soll ich sie an den unteren Rand PINNEN (immer sichtbar)? Das kostet Horizontal-
      Offset-Sync (fragiler in der Launch-View) — darum warte ich auf dein Ja + wie
      der echte Viewport aussieht, bevor ich es umbaue.
- **#58-Stand + eine Richtungsfrage (kein Blocker):** die Station kann jetzt Note
      **setzen · verschieben · in der Länge ziehen · Velocity malen · mehrfach
      auswählen+löschen · als Gruppe verschieben** (6 Primitive). Das adressiert dein
      „noch sehr rudimentär". OFFEN: **manuelles Pro-Note-MPE** (pro Note Bend/Slide/
      Pressure von Hand zeichnen). Council-Einschätzung: das konkurriert mit dem
      Echoel-Kern (Ausdruck kommt aus dem Körper — globales Bio→MPE) und riecht nach
      „control-room cosplay". **Willst du manuelles Per-Note-MPE, oder war das Editing
      der Punkt?** Ich baue Slice 6 nur auf dein Ja (dann eigene Strecke, Note-Feld
      absent=Bio-MPE unverändert).

## Was ich WÄHRENDDESSEN autonom weiterbaue (nicht geräte-gebunden)

- S2-W2 Slice 6 (Primary-Roll-Kind-Routing, riskanteste reine Scheibe) — flag-OFF.
- Sheet-Chain-Konsolidierung in `EchoelStudioView` (Root-Body: 8×.sheet + 1×.cover → EIN
  `.sheet(item:)`-Enum) — Schutz gegen den SIGSEGV-Black-Screen, BEVOR eine Roadmap-UI eine
  weitere Sheet anhängt.
- #58 MIDI/MPE-Station (Velocity-Lane zuerst), danach #54 Warp (nach Freeze-Lift-Verify).
- Kleinschulden: #57 (Lane-Label + Notice-Compose), #62 (lane-gate Move-Vorschau), CI-Guard-
  Symmetrie; #63 Archiv-Hygiene; #52 SEO (Pipeline).

**Deferred bis eigener Zyklus:** #36 Oktaver (spawnt Stimmen — audio-thread-verifiziert bauen),
#61 EEG (Muse S Athena unterwegs), #60 Bio-Session-Brain (Council gegen die Wellness-Linie),
#59 Weather-Synth, #51 Publish (net-new, verwässern bio-first pre-launch).
