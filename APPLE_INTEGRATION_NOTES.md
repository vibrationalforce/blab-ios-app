# APPLE_INTEGRATION_NOTES.md

> **Zweck dieser Datei:** Kontext für Claude Code, damit Architektur- und Entwicklungsentscheidungen im
> Echoelmusic-Repo am Apple-Ökosystem ausgerichtet werden. Diese Datei beschreibt das *Mindset*, die
> *strategische Ausrichtung* und die *offenen technischen Fragen* — sie ist KEINE Implementierungsanweisung
> und überschreibt NICHTS in `CLAUDE.md`. Bei Konflikten gilt `CLAUDE.md` (v7.0) und die geschützten
> DSP-Komponenten bleiben unangetastet (BioEventGraph, HilbertSensorMapper, BioSignalDeconvolver — read-only).

---

## 1. Strategischer Rahmen (das Mindset)

Echoelmusic bleibt ein **eigenständiges, unabhängiges Produkt** im Apple-Ökosystem. Kein Apple-Angestelltenverhältnis,
keine Abgabe der Idee. Die Beziehung zu Apple ist die eines **unabhängigen Entwicklers**, der über offizielle
Developer-Kanäle (DTS, Forums, Feedback Assistant, Labs, künftig Developer Center Berlin) Zugang zu Engineering
und Hardware sucht.

**Leitprinzipien für jede Entwicklungsentscheidung:**

- **Science-only, anti-esoterisch.** Keine pseudowissenschaftliche Sprache in Code-Kommentaren, UI-Strings,
  Doku oder Marketing-Strings. Biosignale werden neutral und faktisch beschrieben (z. B. "HRV", "EEG band power"),
  nicht als "Heilfrequenzen" o. Ä.
- **Standard-APIs vor proprietären Wegen.** Solange es geht, native Apple-Frameworks und Standard-BLE nutzen —
  das hält die App unabhängig und MFi-frei.
- **Kein MFi nötig**, solange Hardware über reines **Core Bluetooth / BLE** spricht. MFi nur, wenn jemals
  lizenzierte Apple-Tech (iAP, CarPlay, HomeKit-over-BLE) gebraucht wird → würde Firmengründung + D-U-N-S erfordern.
- **Featuring-tauglich bauen.** UX, UI-Design, Innovation, Accessibility, Lokalisierung sind nicht nur "nice to have",
  sondern die Bewertungskriterien für App-Store-Featuring. Codeentscheidungen sollten diese Achsen stützen.

---

## 2. Produktvision → technische Ankerpunkte

| Vision / Idee | Apple-Technologie (heute) | Status im Repo / offene Frage |
|---|---|---|
| Biofeedback (HRV, Herzfrequenz) | HealthKit, Core Bluetooth | offen: Echtzeit-Pfad vs. HealthKit-Verzögerung klären |
| EEG-Sensorik (hemisphärisch) | Core Bluetooth (BLE), AccessorySetupKit | offen: Pairing-Flow über AccessorySetupKit? |
| Spatial Audio / immersive Installationen | PHASE, AVAudioEngine spatial mixer, RealityKit Audio | offen: PHASE vs. AVAudioEngine für sensor-getriebene Quellen |
| Knochenschallwandler | Standard-Audioausgabe / BLE-Audio | offen: als Standard-Output behandeln, kein Sonderpfad |
| Head-Tracking | CMHeadphoneMotionManager (CoreMotion) | offen: Integration in Visual-/Audio-Sync |
| visionOS-Erlebnis | visionOS, RealityKit, Reality Composer Pro | offen: eigenes Target oder später? |
| Plugin für Logic/GarageBand | AudioUnit v3 (AUv3) App Extension | offen: AUv3-Target geplant? |
| Multi-Device-Setups (Installationen) | AirPlay / Netzwerk-Sync, OSC (EchoelSync) | offen: AirPlay nötig oder OSC reicht? |
| MIDI 2.0 / MPE | Core MIDI (Universal MIDI Packets) | im Stack vorhanden |
| Laser / Licht / Duft / Vibration | KEINE Apple-API → externe Hardware via BLE/OSC | außerhalb Apple-Framework, separat halten |

---

## 3. Offene technische Fragen für Claude Code (Repo-Abgleich)

Diese Fragen soll Claude Code beim Durchgehen des Repos berücksichtigen / beantworten helfen:

### Audio / Spatial
1. Nutzt der aktuelle Audiograph PHASE, den AVAudioEngine spatial mixer, oder beides? Wo liegt die Grenze?
2. Wie werden Biosignal-Updates (EEG/HRV) mit dem Audio-Render-Thread synchronisiert, ohne Glitches/Priority-Inversion?
3. Gibt es bereits einen Pfad für höhere Ambisonics-Ordnung / dynamische Quell-Repositionierung in Echtzeit?
4. Ist ein **AUv3-Target** vorgesehen, um Echoelmusic-Tools in Logic Pro / GarageBand laufen zu lassen?
5. Head-Tracking: Ist `CMHeadphoneMotionManager` integriert oder geplant?

### Sensorik / Hardware
6. Läuft die BLE-Anbindung (EEG, Sensoren) über klassisches Core Bluetooth oder über **AccessorySetupKit**
   (datenschutzfreundliches Single-Device-Pairing)? Migration sinnvoll?
7. Werden Biosignale in **HealthKit** geschrieben (für "Works with Apple Health" + Persistenz), oder bleiben sie app-intern?
8. Wie ist der Fallback, wenn kein Sensor verbunden ist (Demo-/Simulationsmodus für TestFlight-Reviewer)?

### visionOS / immersiv
9. Gibt es ein visionOS-Target oder ist das ein späterer Meilenstein? Falls geplant: RealityKit-Audio vs. PHASE?
10. Werden die 120fps-Metal-Visuals so abstrahiert, dass sie perspektivisch auf visionOS portierbar sind?

### Installations-/Multi-Device-Layer (EchoelSync)
11. OSC-Output ist vorhanden — reicht das für Multi-Device-Installationen, oder ist AirPlay/Netzwerk-Sync nötig?
12. Wie wird Latenz/Sync zwischen mehreren Geräten in einer Live-Installation gehandhabt?

### Schutz & Struktur
13. Bleiben BioEventGraph, HilbertSensorMapper, BioSignalDeconvolver bei allen Vorschlägen **unverändert**? (Pflicht.)
14. Sind UI-Strings/Kommentare durchgehend science-only formuliert (kein esoterisches Vokabular)?

---

## 4. Was NICHT zu tun ist (Leitplanken)

- ❌ Keine Änderungen an den drei geschützten DSP-Komponenten ohne explizite Freigabe.
- ❌ Kein esoterisches/pseudowissenschaftliches Vokabular in Code, Strings, Doku.
- ❌ Keine MFi-/proprietären Abhängigkeiten einbauen, solange BLE-Standard ausreicht.
- ❌ Kein Hardware-Sonderpfad für Knochenschallwandler — als Standard-Audioausgabe behandeln.
- ❌ Laser/Licht/Duft/Vibration NICHT ins Apple-Framework mischen — sauber über externe BLE/OSC-Schnittstelle trennen.

---

## 5. Externer Apple-Kontext (Hintergrund, nicht im Repo umzusetzen)

- Developer-Account aktiv, TestFlight läuft, Apple Beta Software Program (Software) aktiv.
- Kontaktkanäle zu Apple-Engineering: Feedback Assistant (FB-IDs im Repo referenzieren, wenn relevant),
  Developer Forums (Core Audio / PHASE / Spatial Computing), 2× DTS-TSI/Jahr, Tech-Talk-Office-Hours,
  künftig Apple Developer Center Berlin.
- Featuring-Nominierung in App Store Connect für größere Releases (3 Monate Vorlauf).
- **Wenn im Code ein API-Limit/Bug zu einer Apple-Framework-Frage führt:** als `// FBxxxxxxxx` markieren,
  damit offene Apple-Feedback-Tickets mit Code-Stellen verknüpft bleiben.

---

*Diese Datei ergänzt CLAUDE.md v7.0. Bei Widerspruch hat CLAUDE.md Vorrang.*
