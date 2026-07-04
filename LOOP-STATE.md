# LOOP-STATE — Build-Setup Bereinigung (XcodeGen + Fastlane)

Goal: `project.yml` sauber, tote Referenzen raus, `Fastfile` modernisiert,
alles baut fehlerfrei. **Validierungskette in dieser Umgebung:** kein lokales
macOS/Xcode (Linux-Container) → `xcodegen generate` + `xcodebuild` laufen als
CI-Gate `xcode-compile-check.yml`, Build+Tests als `ci.yml`. „Grün" heißt:
beide Gates grün auf dem gepushten Commit.

**VALIDIERT ✅ (2026-07-04):** Commit `828e17f` — beide CI-Gates grün
(`xcode-compile-check.yml` = xcodegen generate + xcodebuild auf macOS;
`ci.yml` = Build + Tests). Der Hygiene-Pass ist damit abgeschlossen.

## Durchlauf 1 — 2026-07-04 (Hygiene-Pass, ein Commit)

| Bereich | Status | Änderung | Validierung |
|---|---|---|---|
| project.yml: MARKETING_VERSION | done | Stale Fallback "10.76.1" → "10.79.66" + Kommentar, dass testflight.yml den Wert pro Deploy aus `.deploy/release` sedet (Zeilen 193/359/719/932/1146/1360). preflight-check.sh-Grep und CI-sed-Pattern verifiziert kompatibel. | CI-Push |
| project.yml: Widgets-Kommentar | done | Block behauptete „dependency intentionally OFF" — Widerspruch zur Zeile `- target: EchoelmusicWidgets` im App-Target (C3 ist längst geshippt). Kommentar auf Ist-Zustand korrigiert. | CI-Push |
| Fastfile: `mac build_only`/`mac test` | done | ENTFERNT — referenzierten Scheme `Echoelmusic-macOS`, das in project.yml nicht existiert; kein Workflow rief sie auf. `mac setup_signing`/`mac upload` BLEIBEN (testflight.yml ruft sie bei mac-Dispatch). | CI-Push |
| Pluginfile | done | War INERT: Gemfile evaluiert die Pluginfile nie (kein `plugins_path`-Block), kein Gemfile.lock — die 5 Plugins wurden nirgends installiert. 4 ohne jegliche Call-Sites entfernt (firebase_app_distribution, match_keychain, badge, versioning); frameit_chrome behalten (Framefile.json existiert, Screenshots-Reparatur braucht es + die Gemfile-Verdrahtung). | statisch (Datei war wirkungslos) |
| Appfile | done | Slop-Header raus („Phase 10000 ULTIMATE MODE", „Security Score 100/100 A+++"); `for_lane`-Blöcke für NICHT existierende Lanes entfernt (beta, beta_watchos, beta_tvos, beta_visionos); Bundle-ID-Referenz auf docs/dev/APP_STORE_CONNECT.md verwiesen. | statisch |
| Deliverfile | done | Slop-Header raus; widersprüchlichen `skip_metadata`-Kommentar korrigiert; WARNUNG dokumentiert: leeres `fastlane/metadata/` + `skip_metadata false` vor Wiederbelebung prüfen (Clobber-Risiko). | statisch |

## needs_decision / blocked (Founder)

1. **Screenshots-Pipeline ist zweifach gebrochen** (`screenshots.yml`):
   ruft `fastlane frame_screenshots` auf — die Lane existiert im Fastfile NICHT;
   und `capture_screenshots` zielt auf Scheme `EchoelmusicScreenshots`, das in
   project.yml nicht definiert ist (bräuchte ein UITest-Target + Scheme).
   Reparatur = eigener Zyklus (UITest-Target, Lane, Gemfile-Plugin-Verdrahtung).
   NICHT in diesem Pass angefasst — Workflow läuft nur auf manuellem Dispatch.
2. **testflight.yml Multi-Plattform-Jobs** (mac/tvOS/visionOS/watchOS-Upload):
   referenzieren Lanes, die existieren — aber es gibt keine solchen Targets in
   project.yml (iPhone-first v10). Die Jobs sind dispatch-gated und stören
   nicht; ein Rückbau wäre Kürzung von ~800 Zeilen PRIMARY-CI → nur mit
   expliziter Founder-Freigabe (CLAUDE.md: CI-Config founder-gated).
3. **fastlane/metadata/ + screenshots/ sind leer** — Deliverfile-Risiko oben
   dokumentiert; löschen oder befüllen erst mit der Screenshots-Reparatur.

## Nicht gefunden (geprüft, sauber)

- project.yml: keine verwaisten Datei-/Pfad-Referenzen (Verzeichnis-basierte
  Sources; alle `path:`-Einträge existieren), Targets alle real (App, AUv3,
  Widgets, Watch-Scaffold mit dokumentiertem C6b-Embed-Blocker), Schemes
  konsistent, SDKROOT/SUPPORTED_PLATFORMS-Pattern durchgängig.
- Gemfile: minimal + korrekt (fastlane ~2.225, xcode-install).
- `.xcodeproj` wird nie direkt angefasst (nicht eingecheckt; CI generiert frisch).
