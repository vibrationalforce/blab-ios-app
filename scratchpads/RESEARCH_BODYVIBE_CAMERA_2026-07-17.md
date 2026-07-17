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
