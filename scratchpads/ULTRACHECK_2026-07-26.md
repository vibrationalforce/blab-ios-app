# ULTRACHECK — Code · Design · Brand (Founder 2026-07-26: "ultracodecheck ultradesgincheck ultrabrandcheck")

Three sweeps. Findings land here; ONE slice ships per Ralph cycle. Everything below is
verified against the code/site at the cited path — no claim from memory.

---

## BRAND — verified 2026-07-26

### B-1 (SCHWERSTES) Die Website verkauft ein AUv3-Plugin, das seit 2026-07-24 nicht mehr existiert

Slice 1 des Reinen-Instrument-Epics (#122) hat das `EchoelmusicAUv3`-Target gelöscht
(`project.yml:160` trägt den Grabstein, `Sources/` enthält nur noch `Echoelmusic`,
`EchoelmusicWatch`, `EchoelmusicWidgets`). Die Website behauptet es weiter — **8 Dateien,
~25 Stellen**, darunter als **`LIVE`** getaggte Prosa und maschinenlesbares
schema.org-JSON (Google-sichtbar):

| Datei | Stelle | Claim |
|---|---|---|
| `docs/architecture.html` | 256 | `<h2>AUv3 Plugin <span class="tag">LIVE</span>` |
| `docs/architecture.html` | 257 | "ships a working **Audio Unit v3 instrument** (`aumu / echl / Echo`) that runs inside Logic Pro, GarageBand" |
| `docs/architecture.html` | 24, 27, 148, 376 | meta-description, og:description, Nav-Anker, Feature-Liste |
| `docs/index.html` | 102 | schema.org `description`: "Ships today: … AUv3 plugin" |
| `docs/index.html` | 110, 707, 796 | keywords, Capability-Kachel, "or run as an AUv3 plugin inside Logic Pro, GarageBand or AUM" |
| `docs/faq.html` | 44, 98 | FAQPage-JSON + Antwort: "At launch … an AUv3 plugin" |
| `docs/tools.html` | 24, 27, 37, 149, 204, 211 | meta ×3 + "Plugin & host-ready" + "Run Echoel as an AUv3 inside AUM, Cubasis, Drambo…" |
| `docs/overview.html` | 149, 200 | "plus an AUv3 plugin"; "AUv3 plugin **and host**" |
| `docs/press.html` | 102, 128 | Pressetext + Fact-Sheet |
| `docs/brainstorming.html` | 142 | "Pro connectivity: AUv3 plugin" |
| `docs/og-image.html` | 115 | Badge "AUv3" |

`docs/overview.html:200` ist doppelt falsch: AUv3-**Hosting** wurde mit #123 ebenfalls
entfernt. `fastlane/Deliverfile:11` warnt wörtlich vor genau diesem Fehler ("they claimed
an AUv3 plugin for a month") — die Store-Metadaten wurden korrigiert, die Website nicht.

### B-2 "Export to .wav and MIDI" — die MIDI-Hälfte hat keine Tür

`exportMIDI()` (`EchoelStudioView.swift:4235`) hat **keinen Aufrufer** — der einzige lag im
gelöschten Tools-Katalog (`:896` trägt den Grabstein). `MIDIFileExporter` ist intakt und
getestet, aber unerreichbar. Die Website verspricht MIDI-Export u. a. in
`docs/index.html:102` (schema.org), `docs/faq.html:44/98`, `docs/press.html:128`
("stamped MIDI export"), `docs/tools.html:204`.
→ Entweder die Tür zurückholen (ein Fall + ein Switch-Arm im EINEN `craftEditor`-Slot,
Modal-Decke bleibt unberührt) oder den Claim streichen. **Tür zurückholen ist richtig** —
der Exporter ist fertig, und "Body → DAW" ist die Positionierung.

### B-3 "stem export" ist nirgends gebaut

`docs/tools.html:24/27/204` versprechen "stem export"; es existiert keine
`exportStems`-Funktion (#105 ist offen/pending).

### B-4 OFFEN BEIM FOUNDER (gefragt, unbeantwortet): "a **safe** 3 Hz flash rate"

`OnboardingView.swift:128` / `BioSourceView.swift:175`. Der Aurora-Look landet formal auf
**exakt 3.00 Hz** (`FlashGuardTests`), es gibt nirgends einen Photosensitivitäts-Hinweis
und keinen In-App-Schalter, um das Helligkeits-Pulsieren abzuschalten (Reduce Motion wird
geehrt, ist aber eine System-Einstellung). Vorschlag: "safe" streichen, die Tatsache
nennen, eine Vorsichts-Zeile ergänzen, einen App-internen Aus-Schalter bauen.

### Sauber (geprüft, kein Befund)

Kein `BLAB` / `Vibrational Force` / Heilfrequenz / Chakra / Solfeggio / 432/528 Hz in
user-facing Copy. Alle `healing`-Treffer in `Sources/` sind interne Kommentare
(Arbeitspaket-Namen + der Self-Healing-Launch-Guard); alle `wellness`-Treffer sind
Negationen ("NOT wellness"); alle `therapeutic`-Treffer sind die von CLAUDE.md
**verlangten** Sicherheitshinweise. `vibrationalforce` erscheint nur als GitHub-Owner-Slug
in `communityIssueURL(...)` — eine echte Repo-Adresse, keine Marken-Copy.

---

## CODE — 3 Worker laufen (Live-Pfad-Crash/Stille · Audio-Thread+Swift-6 · Persistenz+lügende Controls)

### C-0 GESHIPPT `e1bb7f8` — Xcode-Gate war rot, seit `0f79a9e`

`MetalBioView:1044` las die gehoistete `Double`-Konstante neben `Float`-Uniforms →
`no exact matches in call to global function 'min'`. Fix: Cast an der Aufrufstelle.
(Ein `Float`-Zwilling in `FlashGuard` war mein erster Versuch — Review hat ihn zu Recht
gekillt: totes `.nextDown` bei jeder binärfreundlichen Obergrenze, Gewinn ~1e-7 Hz, und
ein zweites Symbol für eine Zahl baut genau die Drift-Fläche wieder auf, die der Hoist
beseitigen sollte.)

### C-1 GATE-INTEGRITÄT (aus dem Review, wichtiger als der Fix selbst)

Bei einem **Branch-Push** ist `xcode-compile-check.yml` der EINZIGE blockierende Gate,
der diese Datei überhaupt kompiliert:
- SwiftPM (Linux) schließt sie aus — `canImport(MetalKit) && canImport(UIKit) && canImport(SwiftUI)`.
- `ci.yml:147-166` baut/testet zwar für den iOS-Simulator (UIKit vorhanden), pipet aber
  durch `| xcpretty || cat build.log` bzw. `|| cat test.log` und **schluckt den
  Exit-Code** → meldet grün auf einem kaputten Build. Das ist #139, hier sichtbar geworden.
- `pr-check.yml` bricht hart ab (`exit 1`), läuft aber nur `on: pull_request` nach
  main/develop — auf diesem Branch also nie.

Konsequenz für die Ehrlichkeit der Status-Deltas: „CI/CD Pipeline grün" beweist auf einem
Branch-Push **nicht**, dass der iOS-Build kompiliert, und **nie**, dass Tests gelaufen sind.
Nur „Xcode Compile Check grün" ist eine Aussage. #139 hochziehen.

## DESIGN — offen (Material aus den Audits vom 2026-07-26 wiederverwenden, nicht neu herleiten)
