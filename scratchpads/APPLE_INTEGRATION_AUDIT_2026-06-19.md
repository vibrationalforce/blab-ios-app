# Apple Integration — Repo-Abgleich (Audit 2026-06-19)

Antworten auf die 14 offenen Fragen aus `APPLE_INTEGRATION_NOTES.md` §3, basierend
auf dem tatsächlichen Code-Stand. Faktisch, mit Datei-Belegen.

## Audio / Spatial

1. **PHASE vs. AVAudioEngine spatial mixer?** — **Weder noch.** `Audio/AudioEngine.swift`
   ist ein reiner Stereo-Graph (`masterPlayerNode → masterMixer → AutoMixChain →
   mainMixerNode → output`, Format auf max. 2 Kanäle). Kein `AVAudioEnvironmentNode`,
   kein `AVAudio3DMixing`, kein PHASE, kein `SpatialAudioEngine`. Einziger Rest: ein
   ungenutztes `spatialAudioEnabled = false`. **Spatialisierung läuft extern über
   ADM-OSC**, nicht in-app.
2. **Bio→Audio-Render-Sync ohne Glitches?** — Snapshot-Poll + lock-freie SPSC-Queue.
   `EngineBus` hält `@MainActor latestBio`; `Tools/BioReactiveSynthVoice.swift` pollt
   mit 10 Hz auf dem MainActor, enqueued in eine eigene `nonisolated(unsafe)
   SPSCQueue<BioParams>`, der `AVAudioSourceNodeRenderBlock` drained selbst. Keine
   Locks/Allocs auf dem Audio-Thread → keine Priority-Inversion.
3. **Höhere Ambisonics / dynamische Quell-Repositionierung?** — **Objekt-Repositionierung ja,
   Ambisonics nein.** `Sync/ADMOSCSender.swift` streamt Bio live als ADM-OSC
   (`/adm/obj/{n}/position/azimuth|elevation|distance` + `/gain`) → Body steuert in
   Echtzeit die Objektposition in jedem ADM-Renderer (L-ISA, d&b Soundscape, Spat,
   Nuendo). Kein in-app Ambisonics-Encoding/Decoding.
4. **AUv3-Target für Logic/GarageBand?** — **Ja, existiert.** `Project.swift` definiert
   `EchoelmusicAUv3` (`product: .appExtension`, `com.echoelmusic.app.auv3`,
   `NSExtensionPointIdentifier = com.apple.AudioUnit-UI`), Quellen unter
   `Sources/EchoelmusicAUv3/`. Nur Tuist/Xcode, nicht im SPM-Build.
5. **Head-Tracking (`CMHeadphoneMotionManager`)?** — **Nicht vorhanden.** Kein
   CoreMotion/CMHeadphoneMotionManager/headTracking irgendwo in `Sources/`. Weder
   integriert noch Stub.

## Sensorik / Hardware

6. **Core Bluetooth oder AccessorySetupKit?** — **Klassisches Core Bluetooth.**
   `Bio/PolarH10BioPublisher.swift` nutzt `CBCentralManager`/`CBPeripheral` und den
   Standard-SIG-Dienst Heart Rate `0x180D` (jeder konforme Gurt, nicht nur Polar).
   Kein AccessorySetupKit. *(Migration wäre datenschutzfreundlicher — siehe Empfehlung.)*
7. **HealthKit Write oder app-intern?** — **Nur Read, kein Write.** `Bio/EchoelBioEngine.swift`
   ruft `requestAuthorization(toShare: Set(), read: readTypes)` (leeres Share-Set),
   liest HR / HRV SDNN / Atemrate. Kein `HKQuantitySample`/`save(...)`. Also **kein**
   "Works with Apple Health"-Write-Pfad — nur Konsum.
8. **Fallback ohne Sensor?** — **Ja, `Bio/BioSimulator.swift`** erzeugt synthetische
   Bio-Frames (Demo-Quelle in `EngineBus`). Deckt Simulator + TestFlight-Reviewer ohne
   Gurt/HealthKit ab. Live-Quellen: Camera-rPPG + HealthKit; Demo = BioSimulator.

## visionOS / immersiv

9. **visionOS-Target?** — **Nein, späterer Meilenstein.** `Package.swift` nur `.iOS(.v18)`,
   `Platforms/visionOS` + `VisionOS` explizit excluded und nicht vorhanden. Kein
   RealityKit-Import. RealityKit-Audio vs. PHASE im Code noch nicht entschieden.
10. **Metal-Visuals visionOS-portierbar?** — **Teilweise.** `Views/MetalBioView.swift` +
    `BioVisualRenderer` + `.metal`-Shader laufen über `MTKView` (UIKit-gebunden). Shader
    portieren, aber die View-Schicht bräuchte Rework für eine visionOS-Immersive-Scene.

## Installation / Multi-Device (EchoelSync)

11. **Reicht OSC für Multi-Device?** — OSC reich, aber **Single-Target.** `OSCSender`,
    `ADMOSCSender`, `ArtNetSender`, `SACNSender`, `MIDIBusPublisher` senden UDP an je
    einen Host/Port. Für echtes Fan-out fehlt eine Multicast-/AirPlay-/Discovery-Schicht.
12. **Geräte-Sync/Latenz?** — **Kein Device-to-Device-Clock-Sync.** Kein NTP/PTP/Shared-
    Clock. Sender tragen nur lokalen `timestamp` zur Frame-Dedupe. Cross-Device-Latenz in
    Live-Installation aktuell ungelöst.

## Schutz & Struktur

13. **Geschützte Triade unverändert?** — **Ja.** `Bio/BioEventGraph.swift`,
    `HilbertSensorMapper.swift`, `BioSignalDeconvolver.swift` vorhanden, zuletzt 2026-06-03
    (2c85bb4) — seither unangetastet.
14. **Science-only Copy?** — **Ja, sauber.** Keine esoterischen User-Strings. Treffer sind
    nur Disclaimer (`VocoderCore.swift:15` "NOT esoteric 'frequency healing'"), faktische
    Stimmton-Referenzen (432/440/442 Hz), ein Preset-Name "Cosmic Drift" und "Comparison to
    binaural beats" — alle legitim/wissenschaftlich.

---

## Abgeleitete Empfehlungen (priorisiert, vision-konform)

1. **AccessorySetupKit** als optionaler Pairing-Flow für BLE-Sensoren (Privacy + Featuring-Achse) —
   additiv neben Core Bluetooth, kein Bruch.
2. **HealthKit-Write** (HR/HRV/Atem als `HKQuantitySample`, opt-in) → "Works with Apple Health"
   Badge + Persistenz. Niedriges Risiko, klare Featuring-Story.
3. **Head-Tracking** (`CMHeadphoneMotionManager`) als neue Bio-/Modulationsquelle auf dem einen
   Instrument — passt zu "Body is the controller", AirPods als Sensor.
4. **PHASE/Spatial-Entscheidung** bewusst treffen: in-app PHASE für Kopfhörer-Spatial vs. weiter
   rein extern via ADM-OSC. Vorschlag: ADM-OSC bleibt der Profi-Pfad; PHASE nur für die
   Kopfhörer-Vorschau, falls überhaupt.
5. **visionOS** bleibt Meilenstein; Metal-Shader bereits portabel halten.

*Alle Empfehlungen additiv; geschützte Triade & CLAUDE.md-Regeln bleiben Vorrang.*
