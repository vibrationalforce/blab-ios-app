# PLAN — Ultra-Audit Build-Board (Founder 2026-07-19 "bau alles richtig zusammen")

Source: workflow echoel-vision-audit (wf_6d5f3235-672), adversarially verified.
Autonomy granted, NO deploy until afternoon → CI-verifiable cycles first.

## Kernbefund
AUv3 ist end-to-end verdrahtet; einziger Bruch = Discovery liefert leere Liste
auf Gerät (registryColdForProcess), OS/Registrierungs-Grenze, keine kaputte
Swift-Zeile. → nur instrumentierbar, nicht "fixbar" im Code.

## Ralph-Zyklen (CI-verifizierbar zuerst)
- [ ] C1 [2]+[3] HIGH: toten showVisual-Cover + tote Zündung toolsSection/openTool
      aus EchoelStudioView entfernen. 1 Datei. Duplikat weg + Sheet-Kette kürzer.
      Reviewer: ui-state-reviewer + code-reviewer.
- [ ] C2 [1] HIGH (AUv3-Diagnose): Self-Probe INSTANTIATE OK/FAIL + Breadcrumb
      founder-sichtbar (AUv3Host:729/766-783 → AUv3BrowserView cold-state label).
      Ships nächster Build → diskriminiert stale-cache vs. appex-unregistered.
- [ ] C3 [4] MED (item 2): BioModulationReadout Leaf liest ModulationEngine
      .orderedOutputs im EIGENEN body (10-Hz-Gesetz), Slot-Reuse, Unit-Test ordering.
- [ ] C4 [5] MED (item 1 L2/L4): PerTrackAutomationResolver.resolve in Dispatch
      (TimelineRegionPlayer) + LaneVoiceRack per-slot setter. Test-first.
- [ ] C5 [6] MED: AutomationGestureRecorder an ImmersiveStage-Puck-Drag + write-back
      via ClipStore.setClipAutomation. Test-first capture.
- [ ] C6 docs: stale comments (VideoClipView:87, AudioLanePlayer:11-13) korrigieren.

## HALT (founder-gated, NICHT bauen)
- [7] Face-Cam-Modulator: braucht Info.plist camera-usage-Erweiterung → Founder-
      Entscheidung. CLAUDE.md: Info.plist nie ohne Ask. Nur als Notiz am Ende.
- CLOSE-OUT device-hörtest: #39/#23/#54/#55/#58 (verifiziert DONE, nur Gerät fehlt).
- NICHT anfassen: EchoelStore/ProUnlockView, SessionView, alte bottom-bar surfaces
  (documented-parked, delete/re-door nur auf Founder-Ask).
