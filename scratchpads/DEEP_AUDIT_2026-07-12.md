# DEEP AUDIT 2026-07-12 — Gesamtprojekt (Founder-Auftrag)

**Auftrag:** "Mache Deep Audit zu allem was wir bisher haben und was noch
ansteht… ob es Dinge gibt, die wir bisher schon erarbeitet haben und aus den
Augen verloren haben." — 3 parallele Auditoren (Audio/DSP/Core · UI ·
Bio/Sync/Video/Tests), 245 Source-Dateien, 168 Test-Dateien.

## Executive Summary

Der Code-Bestand ist **deutlich reicher als die sichtbare App**. Qualität ist
exzellent (0 print, 0 fatalError, 0 riskante Force-Unwraps, 1 TODO in fünf
Verzeichnissen, nichts geskippt). Aber der Founder-Instinkt war richtig:
**Der "Alles weg außer Visuals"-Pivot (2026-07-02) hat das Tools-Grid aus dem
Body genommen — und damit ~8 FERTIGE Screens still türlos gemacht** (ihre
Sheet-Slots existieren, der einzige Trigger `openTool` lebt nur im nie
referenzierten `toolsSection`-Builder). Dazu: der BLE-Herzgurt-Pfad ist
komplett gebaut, aber wird **nie gestartet**, und ~14 getestete Kerne haben
null Konsumenten.

## FUND 1 — Der Tote-Türen-Cluster (Ursache: Tools-Grid-Removal 07-02)

Sheet-Slots existieren in EchoelStudioView, `isPresented` wird aber NUR im
toten `toolsSection` (≈:843) gesetzt → unerreichbar:

| Screen | Wert | Ehemalige Tür |
|---|---|---|
| **AudioInputPickerView** | ⚠️ **die FeedbackGuard-Tür!** Mic-Monitoring-Toggle + Duck-Anzeige | openTool "input" |
| **PatchbayView** | ⚠️ **die Routing-Tür!** OSC/ADM/Art-Net/sACN/RTMP-Routen schalten | openTool "routing" |
| MeditationView | fertiger 13-KB-Screen, Cover verdrahtet | openTool |
| PatchEditorView | Synth-Patch-Editor (apply-Callback intakt) | openTool "sound" |
| SampleBrowserView | Per-Drum-Track-Sample-Tausch (.sheet(item:) intakt) | toolsSection:874 |
| AutomationView | Automations-Lanes | openTool |
| BroadcastView | Broadcast-UI (ehrliches Scaffold dahinter) | openTool |
| SpectralDonutView | Spektral-Donut-Visual (einzige Tür = totes showVisual-Cover) | openTool |

**Konsequenz A:** FeedbackGuard (Engine LIVE in AudioEngine:679-689, Tests
grün) ist im Shipping-UI NICHT einschaltbar — Monitoring-Toggle unerreichbar.
**Konsequenz B:** OSC/ADM/Art-Net/sACN sind app-seitig verdrahtet
(applyRouting, app:262-279), aber der USER kann die Routen nirgends
schalten — die Sync-Ausgänge sind faktisch unerreichbar (Defaults aus).
**Konsequenz C (Chance):** showInput/showRouting/showAutomation/showBroadcast/
showPatchEditor/showMeditation/sampleBrowserTrack/showVisual + redundante
showPianoRoll/showPlugins/showAudioClip = **wiederverwendbare Modal-Slots**
an der ~18-Modal-Metadata-Decke — neue Modals via SLOT-REUSE statt Anbau.

**Re-Door-Richtung = Shell v3 (Founder-Direktive "alles auf die Spuren"):**
Sound/Sample/Automation → Spur-Türen (ArrangeModal, E2a/E2b); Input/Routing →
Chrome/Master-Tür-Bereich; Meditation → Founder-Frage (Session-Erbe!);
SpectralDonut → Toggle im FloatingVisualWindow.

## FUND 2 — BLE-Herzfrequenz ist DUNKEL (CLAUDE.md-Claim falsch)

`PolarH10BioPublisher` (Bio/…:32) IST der universelle 0x180D-Empfänger
(Service 180D/Char 2A37, jeder SIG-Gurt) — gebaut, Parser getestet,
app:191 konstruiert, app:302 injiziert, **aber nirgends `.start()`** und
keine View liest ihn. `applyRouting()` hat keinen `bleHRS`-Hook. Der
EINZIGE externe Gurt-Pfad ist aus. Fix = 1 Start-Hook + 1 Tür (BioStrip-
Source oder Patchbay). CLAUDE.md "universal BLE LIVE" korrigiert.

## FUND 3 — Lost Treasures (fertig + getestet, 0 Konsumenten), gerankt

1. **BioModulation** (Studio/) — die universelle Bio-Bindungs-Matrix (jeder
   Parameter ↔ Bio-Quelle oder manuell; Herzschlag als Clock). DAS
   Kernprinzip als fertige Abstraktion.
2. **VocoderCore + VoiceAnalyzer** (Studio/) — BEIDE Hälften des
   audiovisuellen Vocoders (Analyse → VoiceFrame → Mapping Klang+Bild+Licht).
   Schließt direkt an PLAN_VOICE_LIVE VL4 an.
3. **BioTempoDirector** (Core/) — "BPM both"-Modell (locked vs. bioFollow).
4. **BioMusicDirector** (Sequencer/) + OnDeviceModelGate — Bio→Genre/Mood.
5. **EchoelLanguageModel + SoundPrompt** — on-device Prompt→SynthPatch,
   deterministisch, fertig. (= EchoelAI-Baustein!)
6. **PitchTracker + TuningDetector** — YIN cents-genau; MicrophoneManager
   nutzt stattdessen eigenes grobes 43-Hz/bin-FFT. VL3 verdrahtet das.
7. **VoicePitchCorrector** (neu, VL1/VL2) — wartet planmäßig auf VL3.
8. **EchoelSpaceReverb** (DSP/) — "4D depth" Raum-in-Raum-Reverb → Spatial S4!
9. **BinauralPanner** (DSP/) — ITD/ILD → Spatial S5 (Kopfhörer-Renderer).
10. **CloudSyncEngine** (Core/) — Phase-0-Sync, getestet, nie instanziert.
11. **VisualModulation** (Core/) — Visual-Param-Routing (Layer 3-Baustein).
12. Kleinere: PatchLibrary, SkillLevel, TempoMatch, FeatureFlags (S0, wartet
    planmäßig), GenreFXPreset-Subtyp, VDSPKit SpectralAnalyzer/Biquad/Decimator.
13. **Ungetestet + unverdrahtet (vor Wiring prüfen):** CrashSafeStatePersistence,
    EchoelCellular.
14. **MultiTrackRecorder** (Audio/) — auf AudioEngine:111 instanziert, KEINE
    Tür, KEIN Test. **AutoMixChain** — läuft im Master-Bus (:114/325/460),
    kein UI-Toggle, kein Test. **LatencyCompensation** — hängt am dormanten
    Recorder.
15. **ChromaKey.metal** — 12 fertige Kernel, kein Swift bindet sie
    (Greenscreen-Kompositor verwaist; P3-Video-Baustein).
16. **BioSignalDeconvolver + HilbertSensorMapper** (Rausch-Triade, READ-ONLY)
    — getestet, aber nicht im Live-Signalweg (nur "would use"-Kommentar
    EchoelBioEngine:407). Wiring = Founder-/DSP-Review-Entscheid.

## Sauber & lebendig (bestätigt)

FeedbackGuard-ENGINE · rPPG-Pipeline (Trust-Gate, Resilienz) · HealthKit
(start app:535) · EngineBus/Transport/PatternEngine/BioComposer · Per-Track-FX
(Bass/Melodic/Drums) · TimelineRegionPlayer/AudioClipPlayer/ArrangementPlayer ·
LoopCutter · MIDI I/O + AUv3Host · Art-Net/sACN/OSC/ADM-Sender (code-seitig) ·
MultipeerSession + LiveColaboView · Visual-Stack (MetalBioView/Floating/
AdaptiveQuality/FlashGuard) · VisualRecorder→VideoMuxer→Documents/Videos ·
Session-Erbe kompiliert unpräsentiert (per Founder-Regel). ChannelRackView IST
erreichbar (Mix-Panel, embedded). ClipView/ArrangementView/BrowserView/
SurfaceSwitcherBar = Legacy, durch ArrangeTimelineView/SurfaceHost ersetzt →
Kandidaten für Entfernen (Founder-Ask nötig, Reversibilitäts-Regel).

## Test-Lücken (Top)

BroadcastPublisher (ganzer Pfeiler) · VisualRecorder/VideoMuxer/CameraCapture ·
HealthKitBioPublisher/Writer/BioEvent+BioFeedbackPublisher/BioSimulator ·
MultipeerSession/MIDIBusPublisher · MultiTrackRecorder/AutoMixChain ·
CrashSafeStatePersistence/EchoelCellular.

## Empfehlungen

**Sofort (Zyklen, je klein):**
1. BLE-Start-Hook + Tür (Fund 2) — der Gurt-Pfad ans Licht.
2. Input/Routing re-dooren (FeedbackGuard + Sync-Ausgänge erreichbar) —
   Platzierung gem. Shell v3 (Chrome/Spur), NICHT Tools-Grid zurück.
3. Slot-Reuse-Regel dokumentiert (dieses Audit): neue Modals nutzen die toten
   Slots.

**Kurzfristig (in laufende Pläne gemappt):**
- VL3 verdrahtet PitchTracker/TuningDetector/VoicePitchCorrector + FeedbackGuard.
- Spatial S4/S5 verdrahten EchoelSpaceReverb/BinauralPanner (statt Neubau!).
- E2a/E2b re-dooren PatchEditor/SampleBrowser/Automation auf Spur-Türen.
- MeditationView: Founder fragen (Session-Erbe-Regel berührt).
- EchoelAI-Grundstein existiert (EchoelLanguageModel+SoundPrompt) — bei
  EchoelAI-Zyklus NICHT neu bauen.

**Langfristig:** BioModulation als Matrix-UI (Q7-Erbe) · MultiTrackRecorder
+ AutoMixChain testen + Tür (P1-Multitrack) · ChromaKey für P3-Video ·
CloudSync bei v1.1-Live · Deconvolver-Wiring nur mit DSP-Review.

## CLAUDE.md-Korrekturen (in diesem Commit)

- "universal BLE Heart Rate (any 0x180D device)" aus der LIVE-Pipeline-Zeile
  → als GEBAUT-ABER-NIE-GESTARTET markiert.
- FeedbackGuard "wired" → Engine wired, UI-Tür seit Tools-Grid-Removal tot.
