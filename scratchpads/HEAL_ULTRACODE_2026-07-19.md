# Ultracode-Heal — AUv3 + Offene Dinge (2026-07-19)

*14-Agenten-Workflow (Host-Enum · Appex-Instanz · iOS-18-Anforderungen · Open-Code · Founder-Items), adversarial gegen das echte Symptom verifiziert. Vollständiger Plan:*

## AUv3 — die wahrscheinlichste Ursache + der kleinste Fix

**Kernbefund: kein einzelner Kandidat erklärt BEIDE Symptomhälften. Es sind zwei getrennte Defekte** — und keiner davon ist aus den vier gehosteten Host-Dateien code-fixbar-jetzt.

**Symptomhälfte A — „unser Prozess sieht 0 Third-Party (nur 101 Apple), AUM auf demselben Gerät sieht alles":**
Das ist ein **per-Prozess Out-of-Process-AudioComponent-Blackout**, kein Scan-Bug. `performScan` (AUv3Host.swift:779/832) fragt korrekt Wildcard + je Typ + `passingTest`, dedupt, und `rawMakers` (788/842) kommt bereits Apple-only vom OS zurück. Der Filter (832) rechnet `thirdPartyCount` VOR dem `compactMap` → die 0 ist ehrlich. Das Problem liegt upstream in dem, was iOS DIESEM Prozess ausliefert.

**Symptomhälfte B — „-3000 invalidComponentID auf unseren EIGENEN appex, und AUM listet EchoelBodyVibe, öffnet ihn aber auch nicht":**
Das ist der eigentliche appex-Defekt. Innerhalb unseres kaputten (leeren) Host-Registrys ist unser Self-Probe-`-3000` **überdeterminiert** — die Komponente fehlt schon in der Prozessliste, bevor irgendein appex-Ladecode läuft. Die verwertbare, appex-seitige Evidenz ist deshalb ausschließlich das AUM-Faktum: **AUM öffnet EchoelBodyVibe nicht.** Das ist ein host-unabhängiger Launch-Denied des appex-Prozesses.

### Rangliste der überlebenden Kandidaten

1. **(B, höchste) Appex Launch-Denied via App-Group-Entitlement-Mismatch** — `EchoelmusicAUv3.entitlements:6` fordert `group.com.echoelmusic` unbedingt bei jedem Archive. Wenn die App-ID `com.echoelmusic.app.auv3` diese Group im Portal NICHT wirklich grantet, registriert iOS die Komponente aus der Info.plist, verweigert aber den Extension-Prozess-Start → jeder Host bekommt `-3000`. Textbook-Signatur für „sichtbar, öffnet in JEDEM Host nicht", persistent über alle Builds.
   - **CODE-FIXBAR-JETZT (als Diagnose + wahrscheinlicher Fix):** `com.apple.security.application-groups` aus `EchoelmusicAUv3.entitlements` streichen + App-Group-Zugriff aus dem appex-Sources-Block in `project.yml:157` entfernen. Der AU braucht die Group zum Instanziieren NICHT — `pullSharedVitals()` degradiert sauber zu „Host setzte die Parameter" (`EchoelmusicAudioUnit.swift:367-377`). Öffnet der appex danach → Mismatch war das Tor. **Ein CI-grüner Commit, den ich jetzt machen kann.**
   - **BRAUCHT DICH parallel:** Portal-Check, ob App Groups für App-ID `com.echoelmusic.app.auv3` mit `group.com.echoelmusic` aktiviert ist (die Widget-App-ID hat es; die viel jüngere auv3-App-ID evtl. nicht).

2. **(B, mittel) Embedded appex trägt DEV- statt Distribution-Profil** — `testflight.yml:556` provisioniert per-Target DEV-Profile; wenn `-exportArchive` die App distribution-signt, der eingebettete appex aber ein geräte-limitiertes DEV-Profil behält, startet er nur auf UDIDs im Profil → auf dem Gründer-Gerät `-3000`, App läuft trotzdem.
   - **CODE-FIXBAR-JETZT (als CI-Gate):** Nach dem Export prüfen, dass `PlugIns/EchoelmusicAUv3.appex/embedded.mobileprovision` ein App-Store-Profil ist: `security cms -D -i .../embedded.mobileprovision | plutil -p -` und `get-task-allow=false` asserten. Fängt es künftig; beweist es nicht aus statischen Dateien.

3. **(A, ungeklärt, braucht Geräte-Faktum) Host-Enumeration-Blackout** — nicht code-fixbar. Zwei mögliche Ursachen, beide hier nicht beweisbar: (a) **iOS 26 AUv3-Hosting-Regression** (JUCE Dez-2025: nativer Scan liefert 0 Plugins trotz korrekter Entitlements) oder (b) **ungültige Signatur unseres eingebetteten appex**, die den audiocomponentd dazu bringt, unserem Prozess nur das sichere In-Process-Apple-Set zu servieren. Kandidat (b) ist plausibel dieselbe Wurzel wie #1/#2.

**Ausdrücklich NICHT die Ursache (nicht erneut behaupten):** `inter-app-audio` (Echoelmusic.entitlements:41) — iOS-AUv3-Hosting braucht kein Entitlement, AUM hat keins. Löschen ist reine Hygiene (App-Review 2.5.4), kein Fix. Das war der vorige Fehlschluss.

### Das eine billigste Geräte-Experiment, das disambiguiert

**Ein Clean-Delete + Reboot + Frisch-Install (v-Build mit korrigierter appex-Entitlement), dann die Self-Probe-Zeile lesen:**
- **`INSTANTIATE OK + leere Liste`** → reiner Registrierungs-/Cache-Pfad, Symptom A ist per-Prozess-Enumeration (iOS-26/Signatur), appex selbst ist gesund.
- **`INSTANTIATE FAILED (-3000)`** → echter appex-Instanziierungsdefekt → Kandidat #1/#2 (Entitlement/Signing) bestätigt.

Und **eine Zeile eines frischen Geräte-Logs würde A endgültig klären:** die iOS-Version + ob `rawMakers` je einen Non-Apple-Maker zeigt. Zeigt `rawMakers` NUR Apple → OS-seitiger Blackout (nicht unser Code). Zeigt es Non-Apple, aber die gehostete Liste 0 → dann erst wird der Filter verdächtig (heute ausgeschlossen).

**CI-Gate für AUv3-Discovery zurück auf WARNING** (nicht Blocker), damit Deploys nicht hängen, während dies device-verifiziert wird.

---

## Offene Dinge — priorisiert (Top 10)

1. **AUv3 External Hosting (Phase 0 Blocker)** — 3rd-Party unsichtbar + eigener appex `-3000`. Nächster Schritt: appex-App-Group streichen (Commit jetzt) + Clean-Reinstall/Reboot-Experiment oben; Portal-App-Group prüfen. *Alles andere Phase-2 wartet hierauf.*
2. **Import MIDI unerreichbar (built-but-doorless)** — `fileImporter` + `importMIDI()` funktionieren, einziger Setter hängt am toten `toolsSection`. Nächster Schritt: EINE Live-Tür — Master/Track-Menü-Button `midiImportPresented = true` (Slot wiederverwenden). *Höchster billiger Nutzen.*
3. **Automation-in-Spur fertig (C4/C5)** — Resolver+Recorder gebaut, Dispatch device-gated. Nächster Schritt: C4 `PerTrackAutomationResolver.resolve` in `TimelineRegionPlayer` + per-Slot-Setter (test-first; Achtung Einheiten-Mismatch `setCutoffScale` skalar vs. Registry-Hz), dann C5 Puck-Drag → `ClipStore.setClipAutomation`.
4. **Bio-Modulation live sichtbar (Leaf)** — `ModulationEngine` wired aber leer-by-default, `BioSourceView` doorless. Nächster Schritt: `BioModulationReadout`-Leaf liest `orderedOutputs` in EIGENEM body (10-Hz-Freeze-Gesetz), Slot wiederverwenden, Ordering-Unit-Test; erreichbares Zuhause entscheiden.
5. **AUv3-Belegung pro Spur** — per-Lane-Hosting bestätigt funktional, blockiert nur auf #1. Kein eigener Nächstschritt; entsperrt automatisch, sobald Discovery on-device nicht-leer liefert.
6. **MIDI/MPE-Station aus rudimentär heben** — `PLAN_58` Slices; inkl. B6 BLE-MIDI-Tür (`CABTMIDICentralViewController`) via bestehenden Slot. Auch: `MIDIBusPublisher` aftertouch/channel-pressure absichtlich ungesendet — im FEATURE_MATRIX vermerken, nicht als volles MPE-out claimen.
7. **toolsSection Tools-Grid = totes Duplikat** — `toolsSection/toolItems/openTool/gridChip` nirgends gemountet, `openTool` hat nicht mal Cases für pianoroll/sound/automation. Nächster Schritt: löschen ODER als intendierte Tür-Fläche re-mounten — nicht halb-tot liegen lassen (lädt „restore navigation" ein, die nie ging).
8. **Dead-Surface-Cut (1 pro Ralph-Cycle)** — `BroadcastView` (0 refs, RTMP nicht gelinkt) + `ArrangementView` (0 refs, Timeline ersetzt sie) zuerst, nach 0-ref-Verify. C1 (showVisual-Cover) PARKED. Meditation/Session bewusst behalten.
9. **Founder-Entscheid Monetarisierung** — `EchoelStore` dormant, Legacy-Subscription-IDs widersprechen One-Time-Unlock. Braucht DICH: One-Time-Unlock jetzt wiren ODER bis v1.1 cutten. Kein Store-Objekt ohne Produkte shippen.
10. **FaceExpressionBioPublisher gebaut, nirgends konstruiert** (EchoelBodyVibe Kamera-Modulator, Task #68) — trägt keinen Puls, Selektion-Wiring deferred. Nächster Schritt: Source-Port + start/stop via `applyRouting` wie die BLE-Strap-Tür, ODER klar flaggen.

*Niedrig / Housekeeping (nicht Top 10):* stale „Not yet wired"-Kommentar auf `HapticEngine` löschen (ist tatsächlich wired); `BioTempoDirector` als Foundation belassen; Audio/Video/Visual-Clip-Lanes sind ehrlich-gelabeltes Scaffold (`isPlayable`-Gate halten); CloudKit/Push-Gate-Flip erst v1.1 nach Schema-Deploy.

---

## Was ich JETZT ohne dich fixen kann vs. was ich von dir brauche

**Ich JETZT (CI-grüne Commits, keine Geräte-/Portal-Aktion nötig):**
- **AUv3-Kandidat #1:** App-Group aus `EchoelmusicAUv3.entitlements` + `project.yml:157` streichen (Diagnose + wahrscheinlicher Fix, `pullSharedVitals` degradiert sauber).
- **AUv3-Kandidat #2:** CI-Gate im `testflight.yml`-Export, das das embedded appex-Profil als Distribution asserted.
- **AUv3-Gate zurück auf WARNING**, damit Discovery keine Deploys blockt.
- **Import-MIDI-Tür** (#2 oben): ein Menü-Button, bestehenden Slot wiederverwenden.
- **Totes `toolsSection`-Grid löschen** (#7).
- **`inter-app-audio`-Key streichen** (reine Hygiene, NICHT als Fix framen).
- **Stale `HapticEngine`-Kommentar** löschen; `MIDIBusPublisher`-Lücke im FEATURE_MATRIX dokumentieren.

**Von DIR (kann ich hier nicht — kein Build, kein Device-Log, kein Portal):**
- **Das eine disambiguierende Geräte-Experiment:** Clean-Delete + **Reboot** + Frisch-Install der nächsten v-Build, dann die Self-Probe-Zeile ablesen (`INSTANTIATE OK` vs `FAILED`) — das teilt Registrierungs-Pfad von echtem appex-Defekt.
- **Eine Zeile eines frischen Geräte-Logs:** iOS-Version + ob `rawMakers` je einen Non-Apple-Maker zeigt (klärt Symptom A: OS-Blackout vs. unser Filter).
- **Portal-Check:** App Groups für App-ID `com.echoelmusic.app.auv3` mit `group.com.echoelmusic` aktiviert? (bestätigt/widerlegt Kandidat #1 hart).
- **Founder-Entscheide, die Arbeit gaten:** Monetarisierung (Store wiren vs. cutten) und RTMP/Broadcast-Roadmap-Status (dann BroadcastView cut-or-stub).