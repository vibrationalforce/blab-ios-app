# NIGHT REPORT — EchoelAI Night Session 2026-07-12

Branch: `claude/piano-roll-clip-view-wozlie` · TestFlight-FREEZE aktiv (kein Deploy).
ADR: `scratchpads/ECHOELAI_ADR_2026-07-12.md` (ab jetzt Referenz).

## 1. Cycle-Status

| Cycle | Status | Kern |
|---|---|---|
| N0 Lagebild + ADR | **DONE** | ADR geschrieben; zwei der genannten Referenzdokumente existieren nicht mehr (Mai-Stand) — durch die aktuellen Audits ersetzt, im ADR dokumentiert. |
| N1 EngineBus-Subscriber | **DONE-BY-EXISTING** (kein Code) | Die Briefing-Prämisse „nichts subscribed auf bioFrames" ist überholt: `BioReactiveSynthVoice.start(subscribing:)` + `PolySynthVoice.start(subscribing:)` pollen `bus.latestBio` @10 Hz → `applyBioReactive(...)`. Der Architektur-Audit 2026-06-09 erklärt den SNAPSHOT-Pfad bewusst zum Bio-Pfad (Queue bleibt absichtlich undrainiert). Die geforderte Test-Assertion existiert: `BioIntegrationTests` (Frame→DDSP-Zielparameter über alle Mappings). Ein neuer Queue-Drainer hätte die auditierte Architektur VERLETZT → nicht gebaut (CLAUDE.md > Briefing, Regel des Briefings selbst). |
| N2 EchoelParameterRegistry | **DONE** | `Core/EchoelParameterRegistry.swift`: ParameterDescriptor (keyPath-Identität, clamped normalize/denormalize) + Registry (@MainActor, replace-by-keyPath, Token-Suche, Ranking-Hook dokumentiert) + 15 echte DDSP-Deskriptoren; AUParameterTree-KVO-Design als Kommentar. 11 Tests. |
| N3 EchoelAIKit-Skelett | **DONE** | `EchoelAI/BrainBackend.swift` (Protokoll + EchoelAIError) + `EchoelAI/FoundationModelsBrain.swift` (vollständig hinter `#if canImport(FoundationModels)` + `#available(iOS 26/macOS 26)`; sonst unavailable, kein Crash) + `FeatureFlags.echoelAI` (Default OFF). Availability-Smoke-Test + Flag-Contract-Test. |
| N4 Stretch | **TEIL-DONE / TEIL-SKIPPED** | DONE: `EchoelAI/ParameterToolCore.swift` (list/set-Tool-LOGIK modell-frei, Clamp + injizierte Control-Plane-Apply, korrigierbarer unknown-keyPath-Fehler; 5 Tests) + `Resources/EchoelAI/echoelai-vocabulary.json` (Seed-Vokabular v1, Daten ohne Konsument). SKIPPED mit Grund: (a) FoundationModels-`Tool`/`@Generable`-Wrapper — exakte Macro-Signaturen ohne lokal kompilierbare iOS-26-SDK-Umgebung = hohes Red-Gate-Risiko (Regel 7: nie rot committen; Wrapper sind dünn und kommen im ersten Device-Zyklus); (b) typisierte Parameter-Änderungs-Nachricht auf dem EngineBus — die Briefing-Annahme („der N1-Subscriber wendet sie an") passt nicht auf den realen Bus (3 feste Topics, Snapshot-Architektur); braucht einen eigenen Design-Pass gegen den echten Bus statt einer Nacht-Improvisation. Interim: die injizierte Apply-Closure in ParameterToolCore hält den Write-Pfad abstrakt. |

## 2. Commits (chronologisch, diese Night-Session)

- `794da35` docs(adr): EchoelAI tier architecture (N0)
- `fb876f6` feat(echoelai): N2 EchoelParameterRegistry — queryable keyPath registry, DDSP first inventory
- `65c1f1d` feat(echoelai): N3 brain-backend skeleton — BrainBackend + guarded Foundation Models Tier 1
- `7f074c5` feat(echoelai): N4 (safe subset) — model-free tool core + semantic vocabulary data

Davor im selben Fenster (Tages-Batch, bereits alle Gates grün): `c21e423` B2 Pan pro Spur · `c24654a` W1 LyricsModel · plus Doku-Ticks.

## 3. Build-/Test-Status am Session-Ende

- Gates bis einschließlich `c24654a` (W1): **alle grün** (⚡ Quick Test · Xcode Compile Check · CI/CD · Auto-Merge).
- `794da35`–`7f074c5`: Gates laufen bei Report-Erstellung noch (Xcode-Compile ~20 min); Wakeup ist gestellt — bei Rot wird gefixt oder revertiert, das Ergebnis landet als Nachtrag hier.
- Kein lokaler Swift-Build in der Sandbox (bekannt) → CI ist Ground Truth.
- Statische Prüfungen pro Commit: Brace/Paren-Balance, JSON-Validierung, Handsimulation der Syllabifier-/Registry-Logik.

## 4. Entdeckte, NICHT gefixte Probleme (nur dokumentiert)

1. Die Night-Briefing-Referenzen `PLAN_FOUNDATION_SEQUENCE.md` und `DEEP_AUDIT_CONNECTION_MAP_2026-05-22.md` existieren nicht (mehr) im Repo — künftige Prompts sollten auf `ARCHITECTURE_AUDIT_2026-06-09.md` + `DEEP_AUDIT_2026-07-12.md` zeigen.
2. Es gibt KEINEN typisierten Control-Plane-Write-Pfad über den EngineBus (UI/Stores schreiben direkt in Voices). Für EchoelAI-Tools brauchbar, aber als Architektur-Entscheid council-würdig (neuer Bus-Topic vs. Command-Registry).
3. `EchoelStore` bleibt dormant/widersprüchlich zur Pricing-Lage (bekannt aus Masterplan §2, unverändert).
4. FoundationModels-Fehler-Mapping läuft übergangsweise über die Fehler-BESCHREIBUNG (guardrail-Substring) — im ersten Device-Zyklus auf typisierte `GenerationError`-Cases härten (im Code markiert).

## 5. Empfohlene nächste 3 Cycles

1. **Registry-Ausbau: EchoelFX + PolySynth/SubBass-Parameter registrieren** — die Registry wird erst als BREITER Bestand tool-tauglich; FX-Stages (Bitcrush/Widener/Delay/Reverb) und die Patch-Parameter sind die musikalisch wirksamsten Hebel, und alles ist heute schon control-plane-erreichbar (kein Render-Risiko).
2. **Control-Plane-Write-Design (Council)**: typisierte Parameter-Änderung — neuer Bus-Topic `controlWrites` vs. @MainActor-Command-Registry, Entscheidung gegen den realen Bus + 10.76er-Gesetze; danach ParameterToolCore.apply darauf umstellen. Voraussetzung für `applyParameterSet` und `createBioMapping`.
3. **Device-Zyklus FoundationModels** (sobald ein Apple-Intelligence-Gerät testet): `Tool`/`@Generable`-Wrapper um ParameterToolCore, typisiertes Error-Mapping, erster End-to-End-Trace „dunkler" → searchParameters → setParameter(ddsp.filter.cutoff↓) — hinter `FeatureFlags.echoelAI`.

## 6. Offene Fragen an den Owner (priorisiert, max. 5)

1. **iOS-26-Verfügbarkeit im Testpark:** Hat dein Test-iPhone Apple Intelligence (iPhone 15 Pro+/16+, iOS 26)? Ohne Gerät bleibt Tier 1 unverifizierbar (CI kann nur den unavailable-Pfad beweisen).
2. **EchoelAI-Einstieg später:** Chat-Panel im Dropdown-Host (Slot-Reuse, Render-Safety-konform) oder zuerst UNSICHTBAR (nur Tools hinter Flag, Founder-DevMenü)? Betrifft die Modal-Decke.
3. **Control-Plane-Write (Empfehlung 2):** Bus-Topic oder Command-Registry — magst du das im Council-Verdikt absegnen, bevor Tools echte Writes bekommen?
4. **Vokabular:** Soll das Seed-Vokabular deutsch UND englisch gepflegt werden (aktuell deutsch mit Alias-Feld)?
5. **Tier 2 (MLX/Qwen):** bleibt komplett auf Eis bis Founder-Go für die Dependency — bestätigt so?
