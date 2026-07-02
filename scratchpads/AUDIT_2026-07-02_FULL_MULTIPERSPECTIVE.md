# Full Multi-Perspective Audit — 2026-07-02

8 parallele Fach-Agenten über das gesamte Projekt (Repo + Website `docs/`),
Branch `claude/piano-roll-clip-view-wozlie`. Read-only. Perspektiven:
Architektur/Code · Audio-Thread · Bio/DSP · Bio-Safety · Concurrency · Security ·
SwiftUI-Render-Safety · Website+Marke/Vision.

## Gesamturteil

**Gesund, ungewöhnlich diszipliniert, ship-safe.** Keine Crash- oder Security-Blocker
im Code. Geschützte Rausch-Triade (BioEventGraph/HilbertSensorMapper/BioSignalDeconvolver)
**byte-genau intakt**. Verbote (kein `print`/`ObservableObject`/`UIScreen.main`/force-try)
effektiv 100% eingehalten. Die realen Themen sind: 1 DSP-Korrektheits-Defekt (rPPG),
1 Audio-Thread-Race (DrumSynth), strukturelle Fragilität (ein Riesen-View), und
Marken-/Website-Claim-Konsistenz.

---

## P0 — vor dem nächsten Ship (objektiv, großteils ohne Geschmacksfrage)

### P0.1 rPPG-BPM-Runaway — `Video/CameraAnalyzer.swift:436–568`
Der 60→140-Sprung aus deinen Logs. Wenn Autokorrelation ausfällt (`acf=0`) fallen ALLE
Guards gleichzeitig weg (Refraktärzeit, Oktav-Korrektur, autoTrust), Peak-Counting läuft
ungebremst, die EMA folgt. Die Agreement-Metrik (`1−|bpm−est|/12`) belohnt Selbst-
Konsistenz → hält Confidence künstlich hoch. **Fix (korrekt + sicher):** physiologischer
Slew-Limiter (±6–8 bpm/s über echte `signalTimestamps`-Zeit) + *weiches* Confidence-Decay
bei anhaltendem `autoStrength==0`. KEIN hartes Autokorrelations-Muss (blockiert legitime
Fingerkuppen-Locks). Beweisbasiert, verifizierbar per Log.

### P0.2 DrumSynthVoice Cross-Thread-Race — `Sequencer/DrumSynthVoice.swift:44–60`
`fire()`/`configure()` schreiben `EchoelModalBank`-Mode-Arrays auf dem Main-Thread,
während der Audio-Thread dieselben Arrays liest/RMW-t. Gleiche Klasse wie die absichtlich
abgeschaltete DDSP-Convolution-Race. Worst Case: torn values / glitchy Hit. **Fix:**
Strikes über `SPSCQueue` routen (wie SamplerVoice/SubBassVoice).

### P0.3 HealthKit-Disclosure ↔ OSC/LAN — `Resources/iOS/Info.plist` + `Sync/OSCSender.swift`
Berechtigungstext sagt „stays on your device", aber bei aktivem OSC/ADM-Out gehen HR/HRV/
RMSSD/Atmung/Kohärenz per Plaintext-UDP ins LAN. Widerspruch = App-Store-Ehrlichkeit.
**Fix:** HealthShare- und/oder LocalNetwork-Beschreibung ergänzen (Bio kann bei aktivem
OSC/ADM übers lokale Netz gesendet werden). Reine Copy-/Manifest-Änderung.

### P0.4 Website↔FEATURE_MATRIX Claim-Konsistenz — `docs/*`
Art-Net/sACN + Metal-Bio-Visual sind LIVE, werden aber auf einigen Seiten „Planned/ROADMAP"
gezeigt (auf anderen LIVE) — gleiche Features, gegensätzlicher Status. Dazu Overclaims:
„Research Edition — clinical/validated protocols/API access", „Bio-Reactive SDK Unity/
Unreal", `health.html` Accessibility-Toggles (No Strobing/Low Contrast/Audio-Only) die es
NICHT gibt, „DMX & Laser"-Sektion (kein Laser-Output). `architecture.html` referenziert
entfernte Module (`BioSourceManager`, `GenerativeEngine`) + falsches Signal-Diagramm
(bio läuft über `latestBio`-Snapshot, nicht `bioFrames`). **Fix:** LIVE einheitlich,
Overclaims taggen/entfernen, „clinical/validated/laser" streichen.

---

## P1 — strukturell / Marke (Founder-/Council-Entscheidung)

### P1.1 EchoelStudioView Modal-Kette am Limit — `Studio/EchoelStudioView.swift` (2409 Z., ~20 Modals)
Von UI- UND Architektur-Agent als HIGH markiert. Sitzt exakt am SwiftUI-Metadata-Decoder-
Limit (der 10.76.34-Black-Screen). **Null Spielraum.** Nächstes Modal MUSS die Kette zu
EINEM `.sheet(item:)`-Enum konsolidieren, nicht anhängen. Höchster struktureller Hebel.

### P1.2 Marken-/Wellness-Sprache (Council) — mehrere
- „Meditation"-Surface (`Studio/MeditationView.swift`) + Tools-Menü-Eintrag
- Visual-Preset **„Aura"** (`Studio/VisualPreset.swift:47`) — Esoterik user-facing
- **432 Hz** Tuning-Preset (`DSP/TuningReference.swift:19`) — Healing-Frequency-Trope
- Website „Your energy shapes visuals" (`docs/index.html:862`)
`memory/preferences.md` bannt Wellness/Esoterik user-facing; zugleich gibt es die
„Create·Meditate·Songs"-USP-Spannung. → The Council + Founder-Call, kein Silent-Edit.

### P1.3 FEATURE_MATRIX als Single Source of Truth reparieren — `docs/dev/FEATURE_MATRIX.md`
- EchoelVis-Zeile widersprüchlich (LIVE vs „dormant") → speist die Website-Verwirrung
- Vibration/Haptik (SubBassVoice + HapticController sind gewired) fehlt in der Matrix
- README `Clips/Arrangement` steht als roadmap, ist aber gewired

---

## P2 — Härtung / Hygiene

- **RTMP streamKey → Keychain** vor Broadcast-Ship (`Stream/BroadcastPublisher.swift`, aktuell UserDefaults; Scaffold, noch inert).
- **EngineBus.bioFrames** SPSC mit 4 Produzenten (sicher NUR weil alle auf Main) + **CameraCapture**-Closure-ARC-Race (LOW-MED, latent).
- **EchoelDDSP Denormal-Schutz** (`679–759`) — idle CPU-Spikes, kein Korrektheitsfehler.
- **`Studio/` 56-Datei-Sammelbecken** — Nicht-View-Logik (BioModulation/VocoderCore/FeedbackGuard…) nach Core/DSP/Bio verschieben (owner-run: Target-Membership).
- **1 force-unwrap** (`Sequencer/TempoMatch.swift:65`); stale Kommentar (`Audio/MIDIInput.swift:18` SoundscapeEngine); `appendBass` Walk-in feuert nicht in die Tonika (kosmetisch, in-key); Bonjour `_http/_rtsp` evtl. unnötig; `docs/` Hosting-Mismatch (`_headers`/CSP inert auf GitHub Pages, de-hreflang 404).

---

## Was sauber ist (nicht neu auditieren)
Audio-Render-Pfade lock-free mit pre-allocated scratch + SPSC + nonisolated-Mirror
(0 malloc/lock/GCD/ObjC/os_log im Render). Neue Lead-Stimme + Moving-Bass: clean.
Alle 5 Pflicht-Safety-Warnungen im Onboarding hinter „I understand". 3-Hz-Blitz per
Konstruktion (FlashGuard/MetalBioView/Art-Net slew). Secrets sauber (Tree+History).
ATS ok, PrivacyInfo konsistent, Entitlements minimal. Jede @Environment injiziert,
keine NavigationLink-Fallen, EchoelValueField überall. Musik-Mathe in-key, div-by-zero
komplett guarded. Concurrency der Diff-Änderungen race-free.
