# EchoelBodyVibe Kamera-Modulator — Deep Audit + Deep Research (2026-07-17)

Founder-Direktive: Front-/Rückkamera erkennt Gesicht (Grimassen/Smile/Mimik) und
Körper (Arme/Körpersprache) als intelligenten Modulator der Komposition.
"Wir haben darüber im Laufe des letzten Jahres schon gesprochen." — Bestätigt.

## TEIL 1 — DEEP AUDIT (Repo-/Gesprächs-Historie; verifiziert read-only)

### Historie: es GAB lauffähigen Code
- SESSION_LOG.md:3844/3885-3888 (Feb 2026, Commit a29c8b2, PRE-REBUILD):
  handleFaceExpressionUpdate() fuhr Audio+Visual-Intensität (SMILE) + Licht-Wärme
  (browRaise); applyGestureAudioParameters() fuhr Filter-Cutoff aus Gesten.
  Input→Output-Matrix: (bio, gaze, face, hand) → (audio, visual, lighting).
  Im Rebuild ENTFERNT; als Salvage-Nugget notiert (SESSION_LOG:5273,
  memory/inspiration_intake.md:183/262-263/305 — "expression→modulation" = on-vision).

### Beschlüsse
- decisions.csv:48 (2026-06-01): Kamera = ONE shared input (CameraHub-Fan-out,
  NICHT GEBAUT); rPPG/face/video = wechselseitig exklusive Kamera-MODI
  (Rück+Torch vs. Front+ARKit). SPEC: scratchpads/archive/SPEC_CAMERA_PIPELINE.md.
- decisions.csv:226 (2026-07-17): heutige Direktive geloggt, Teil von Slice B.
- FeatureFlags.performerTracking = räumliches Stage-Tracking (Layer 4), NICHT Mimik
  → neuer Flag (z.B. feature.cameraExpression) sauberer, OFF-by-default-S0-Muster.

### Andockpunkte (alle vorbereitet, dreifach bewiesenes Publisher-Muster)
1. EngineBus.publish(bio:) — Vorbilder: CameraRPPG/PolarH10/HealthKit/BioSimulator.
2. **BioSampleFrame.motionEnergy [0..1] = der reservierte, heute LEERE Kanal** —
   JEDER Publisher schreibt 0. Körpersprache/Arme = natürlicher Füller.
   MotionActivityProvider (CoreMotion) wurde im Rebuild entfernt; kein import
   CoreMotion in Sources/ — "Motion" ist heute ein leeres Versprechen im Frame.
3. **ModSource.motion existiert bereits** (ModulationMatrix.swift:34-72, Range 0…1,
   liest frame.motionEnergy) — Body-Motion ist SCHON routbare Modulationsquelle,
   wird nur nie gefüttert. Mimik bräuchte neue Frame-Felder + ModSource-Cases
   (additiv; decodeIfPresent-Muster vorhanden).
4. BioEventGraph.MotionPeakDetector (protected, READ-ONLY, fertig): sobald
   motionEnergy echte Bewegung trägt, entstehen AUTOMATISCH .motionPeak-Events
   (Arm-Schlag→Akzent) — ohne die Triade anzufassen.
5. Fertige Konsumenten: PolySynthVoice.applyEntrainment (motion), OSC
   /echoelmusic/bio/motion, ADMOSCSender (motion→räumlicher Gain), BioSpaceMap.

### Kamera-Konflikt (harte Constraints)
- rPPG belegt: RÜCKkamera fest, Torch AN (Pflicht), .low, 15fps, EINZIGE
  AVCaptureSession im Projekt; automaticallyConfiguresApplicationAudioSession=false
  (Render-Crash-Schutz — jeder zweite Pfad braucht dieselbe Disziplin +
  avaudio-route-resilience-Skill).
- ✅ Front-Face/Body STATT rPPG (HR derweil via BLE-Gurt/Watch/HealthKit — gebaut):
  der saubere Weg, in SPEC/decisions explizit vorgesehen.
- ✅ Front+Rück PARALLEL nur via AVCaptureMultiCamSession (existiert nicht;
  thermisch heikel — rPPG stallt schon heute bei Hitze; Founder-Device-Gate).
- ❌ Eine Session, beide Linsen: unmöglich. ⚠️ Rück-Pose + rPPG: physisch unvereinbar
  (Finger verdeckt Linse).

### Lücken (Greenfield)
Kein ARKit/Vision-Import in Sources/ (0 Treffer), kein Front-Pfad, kein MultiCam,
kein CameraHub (nur Doku), keine Mimik-Felder/ModSources, keine Gesten→Audio-Bridge.

## TEIL 2 — DEEP RESEARCH (läuft; wird nach Abschluss ergänzt)

## TEIL 2 — DEEP RESEARCH (Web, Quellen im Agent-Bericht; Kernbefunde)

### Apple-native Bausteine
- **ARKit ARFaceAnchor.blendShapes = Mimik-Goldstandard:** 52 kontinuierliche
  Koeffizienten 0…1 (mouthSmileLeft/Right, browInnerUp, jawOpen, eyeBlink,
  cheekPuff …), ~60 Hz, von Apple gefiltert. Seit iOS 14 reicht die NORMALE
  Frontkamera (Neural Engine A12+, TrueDepth NICHT mehr Pflicht) → läuft auf der
  GESAMTEN iOS-18-Flotte. Laufzeit-Check ARFaceTrackingConfiguration.isSupported.
  ABER: ARSession besitzt die Kamera exklusiv → schließt Kamera-rPPG zeitgleich aus.
- **Vision (front+rück, auf bestehenden CMSampleBuffern via Buffer-Tap — KEINE
  zweite Session nötig):** VNDetectFaceLandmarksRequest (Geometrie; Smile/Brauen
  SELBST ableiten, jittert → EMA/One-Euro-Filter); VNDetectHumanBodyPoseRequest 2D
  (19 Joints, ~40 ms auf iPhone 11, deutlich schneller auf A17/A18; 2D reicht für
  Armhöhe/Spreizung/Bewegungsenergie); 3D-Variante (iOS 17+) nur 1 Person, teurer;
  VNDetectHumanHandPoseRequest (21 Landmarks) als Bonus.
- **KEIN Apple-Emotionsmodell** — und das ist ein Feature: blendShapes sind bessere
  Modulatoren als Emotionslabels UND halten uns aus der EU-AI-Act-Emotionszone.

### Recht/Store (2026)
- 5.1.2: Face-Mapping-Daten nie für Marketing/Mining, nie übertragen → Echoel-Design
  (flüchtige Koeffizienten in den Bus) ist per Konstruktion konform. Purpose-String
  erweitern. 2.5.13 irrelevant (keine Auth).
- **EU AI Act Recital 18 explizit:** "mere detection of readily apparent
  expressions, gestures or movements" — wörtlich "a frown or a smile", "movement of
  hands, arms or head" — ist KEINE Emotionserkennung, solange keine Emotionen
  abgeleitet werden. PRODUKTREGEL: immer "Expression/Bewegung als Steuerung",
  NIEMALS "Emotion/Stimmungserkennung" claimen.

### Performance
10–15 Hz Erkennung reicht für Musik-Modulation (Bio-Snapshot läuft eh bei 10 Hz).
Kamera 30 fps, Vision jeden 2.–3. Frame (Frame-Skip wie rPPG), NIE per-Frame auf
@MainActor (10.76.48-Gesetz), Degradation an AdaptiveQuality-Tier koppeln.

### Präzedenz (musikalische Lehre)
FaceOSC, Google Body Synth, EyeHarp (peer-reviewed), AUMI: kontinuierliche
Koeffizienten → Klangfarbe/Ausdruck (Smile→Harmonizität/Brightness, Armhöhe→
Filter — passt exakt auf die DDSP-Bio-Mapping-Tabelle); diskrete Events nur mit
Schwelle+Hysterese (Blinzeln/Arm-Schlag → BioEventGraph-Onsets). Rohe Koeffizienten
auf Tonhöhe = Chaos; Glättung/Quantisierung ist der Kern aller Vorbilder.

## SYNTHESE — 3 Stufen (billigste hörbare zuerst)
1. **FaceExpressionBioPublisher (Vision, Frontkamera):** CameraRPPG-Muster 1:1
   (Background-Queue → Lock-Queue → 10-Hz-Drain → bus.publish); selbst berechnete
   smile/jawOpen/browRaise/headTilt-Koeffizienten, EMA-geglättet, Confidence-Gate.
   Kein neues Permission-Moment. Neue BioSampleFrame-Felder + ModSource-Cases
   (additiv, decodeIfPresent). Flag feature.cameraExpression OFF→Registration-ON
   nach Founder-Test (KEIN unerreichbares Verify-Gate — Modus-Lehre 2026-07-17!).
2. **ARKit blendShapes (exklusiver BodyVibe-Modus):** 52 echte Mimik-Regler;
   Puls kommt derweil vom BLE-Gurt/Watch/HealthKit (verdrahtet). Patchbay-Port
   face.in nach blehrs.in-Muster. Kamera-Arbitrierung rPPG↔Face sequenzieren.
3. **Body-Pose Bühne (Rückkamera/Stativ):** 2D-Pose → Armhöhe/Spreizung/
   Bewegungsenergie → motionEnergy-Kanal (füllt ModSource.motion + MotionPeak-
   Events + 4 fertige Konsumenten GRATIS); optional MultiCam Front+Rück als
   Performance-Modus (Thermik-Budget, Laufzeit-Check).

Einstieg: Stufe 1 als Slice B2 nach dem EchoelBodyVibe-Instrument-Grundbau (B1).
