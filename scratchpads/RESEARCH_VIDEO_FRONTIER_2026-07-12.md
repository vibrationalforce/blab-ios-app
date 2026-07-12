# Deep-Research-Report: Video-Software-Stand 2025/2026 → Echoel P3 Video-Säule

(Deep-Research-Agent, 2026-07-12, Founder-Auftrag: "alle großen Video Softwares …
abklappern aber gründlich". Methode: WebSearch-Snippets — WebFetch meist 403 via
Agent-Proxy; Unverifizierbares am Ende als Lücke gelistet.)

## 1. DaVinci Resolve 19/20 (Blackmagic)

- Einzige echte All-in-One-Suite (Edit/Color/Fusion/Fairlight, eine Datenbank).
- Resolve 20 (Mai 2025): IntelliCut (Fairlight: Stille/Speaker-Split/ADR),
  **Fairlight Animator (Audio-Analyse treibt Fusion-Parameter — konzeptionell
  Echoels nächster Verwandter: Signal → Animation)**, Magic Mask 2, USD/Hydra.
- 20.2/20.3: Magic Mask/Depth Map/SuperScale bis 4× schneller; SuperScale 2,5×
  via Apple Neural Engine.
- Performance: voll GPU-zentriert (CUDA/Metal/OpenCL); Speed Warp = Optical-Flow
  auf GPU; Proxy-Workflow Half/Quarter-ProRes mit Auto-Relink; 64 GB RAM als
  Profi-Minimum → Desktop-Klasse, nicht Mobile.
- Farbe = Branchenreferenz: RCM + DaVinci Wide Gamut/Intermediate, node-basiert,
  HDR-Zonen-Räder, Dolby Vision/HDR10+, 5 Scopes (+ HDR-Scopes in Nits).
- Fairlight = echte DAW in der Video-App (Maßstab "Audio gehört rein").
- Studio einmalig ~295 $, Free-Version voll nutzbar → Preisdruck auf alle.

## 2. Adobe Premiere Pro 2025/2026 (+ After Effects kurz)

- 25.x: neues Premiere Color Management (Log/RAW→SDR/HDR ohne LUTs, ACEScct,
  32-bit), Enhance Speech, Text-Based Editing.
- Premiere 26 (Jan 2026, Rebranding): On-Device AI Object Mask (1-Klick-Objekt-
  Isolation+Tracking), Shape-Mask-Tracking 20×, 90+ Echtzeit-Effekte, "Color
  Mode" (RTX, 6 Luminanz-Zonen; NAB 2026 — Primärbestätigung fehlt, s. Lücken).
- Performance: HW-Decode-Fokus (H.264 bis 4× auf Apple Silicon, 10-bit-4:2:2-
  Decode, Canon RAW Light 4×/9×). Kein Mobile-Editor.
- Audio: Essential Sound (Tagging → Auto-Ducking mit generierten Keyframes).
- AE 26: Multi-Frame-Rendering, 3D-Preview 4×, parametrische Meshes — bleibt
  separate App (Kontrast zu Fusion-in-Resolve).

## 3. Final Cut Pro 11 (Mac + iPad) — die relevanteste Referenz für Echoel

- FCP 11: Magnetic Mask (on-device ML-Roto), Transcribe-to-Captions, Spatial
  Video; 11.1: Adjustment Clips, Quantec-QRS-Raumsimulator, Image Playground.
- Performance-Muster für Mobile: ProRes + Metal + Neural Engine = mehrere
  4K/8K-Streams ohne Proxy; **iPad Live Multicam (4 iPhones via Final Cut
  Camera 2.0): Proxy-first — editierbare Preview sofort, Full-Res-Nachzug im
  Hintergrund. EXAKT das Muster für Mobile-Thermik/Bandbreite.**
- Farbe: automatisches Wide-Gamut-HDR-Management, bewusst "gut genug" (kein
  Node-Grading, kein Dolby-Vision-Mastering).
- Export: ProRes nativ, HEVC/H.264 via VideoToolbox — **genau Echoels
  verfügbarer Zero-Deps-Stack (AVFoundation/VideoToolbox).**

## 4. CapCut (ByteDance)

- Gewann Consumer über: TikTok-Vertikalintegration + Template-Ökonomie
  (Trend → 1-Tap-Nachbau), mobil-first-Featureset, anfangs gratis inkl. 4K.
- Kippt seit 2024/25: Kern-Features hinter Pro-Paywall (~21 $/Monat); Juni-2025-
  ToS gibt ByteDance unbefristete Weltlizenz an Nutzer-Content → Vertrauensbruch.
- Lehre: Templates + sofortiges Ergebnis schlagen Feature-Tiefe; **Einmalkauf +
  "deine Daten bleiben deine" ist 2026 ein aktives Verkaufsargument.**

## 5. LumaFusion (iOS-Profi-Referenz)

- v5.2 (2025): 12 Video-/Audio-Tracks (Add-on), Multicam Studio (6 Quellen),
  externes SSD-Editing am iPhone-USB-C, Apple Log, ProRes-Timeline, Keyframing,
  Speed-Ramps. Einmalkauf + Add-ons.
- Beweis: kleines Team + AVFoundation/Metal = tragfähiger iOS-Profi-Editor.
- Schwächen: kein Farbmanagement/Scopes auf Resolve-Niveau, kein Compositing.

## 6. InShot

- Quick-Edit: Trim/Musik/Filter/Text in Sekunden, Social-Formate als Kern,
  Single-Track-Timeline, Watermark im Free-Tier.
- Lehre: Der 80 %-Use-Case ist "ein Clip, Trim, Format, Export" — UI-Messlatte.

---

## Echoel-Video-Säule: Profi-Minimal-Set + Alleinstellung

**Minimal-Set (FCP/iPad-Muster, KEIN Resolve-Nachbau):**
1. Capture: AVCaptureSession 1080p/4K, HEVC/ProRes wo Gerät kann; Apple Log
   (ab 15 Pro) als Pro-Häkchen.
2. Trim/Cut: ein Clip, In/Out, max. 2 Spuren (A-Roll + Overlay). Keine
   12-Track-Timeline (LumaFusions Markt).
3. Preview-Architektur: Proxy/Preview sofort, Full-Res asynchron; AVPlayer +
   eigener Metal-Compositor (AVVideoComposition Custom Compositor).
4. Farbe minimal: EIN gemanagter Pfad (Rec.709 + optional HLG), LUT via Metal,
   Waveform/Histogramm als Scope (science-first). Kein ACES/Dolby Vision.
5. Audio: bestehender AutoMix-Stack (EQ→Comp→Limiter→LUFS) IST das Essential-
   Sound-Äquivalent — nur Mux in den Export nötig.
6. Export: AVAssetWriter H.264/HEVC + AAC, Social-Presets (9:16/1:1/16:9),
   LUFS-normalisiert.

**Ballast (bewusst weglassen):** Multicam, Node-Grading, KI-Masken/Roto,
Template-Marktplatz, Compositing-Suite, Optical-Flow-Retiming, Dolby Vision.

**Alleinstellung (kann keiner der sechs):**
- Bio-reaktive Video-FX: bioFrames-Snapshot moduliert Metal-Shader-Parameter
  (Muster existiert: MetalBioView/ChromaKey.metal) — Resolve braucht dafür
  Fusion+Fairlight Animator am Desktop; Echoel hat es live am Körper.
- **Puls-synchroner Schnitt: BioEventGraph-Heartbeat/Breath-Onsets als
  Marker-Spur → Auto-Cut/Beat-Sync beim Export (deterministisch, offline).
  Kein Wettbewerber hat physiologische Schnittmarken.**
- Generative Visuals als Video-Quelle: MetalBioView-Output via AVAssetWriter-
  Pixelbuffer-Feed als aufzeichnbare Spur — die Performance IST das Footage.
- Positionierung: Einmalkauf + On-Device (Anti-CapCut-ToS-Moment aktiv nutzen).

## Lückenliste (nicht verifizierbar, Proxy-403)

- Preview-Latenz-/Thermik-Messwerte der Mobile-Editoren (nur anekdotisch).
- CapCut-Engine-Interna (proprietär).
- "Neural Engine 3.0 / 8K-Inferenz" Resolve 20.3.2 = Low-Quality-Blog,
  unbestätigt (verifiziert für 20.3.2: Trim-Editor, F-Log2 C, 2,5× SuperScale).
- Premiere "Color Mode" (NAB 2026): Sekundärquellen ja, Adobe-Primärquelle 403.
- LumaFusion-Roadmap nach v5.2 unklar.
