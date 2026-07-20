# AUv3 Registration — Team deep-dive synthesis (workflow wf_25a17d9e-cf0, 2026-07-20)

Founder confirmed **Inter-App Audio IS enabled** → entitlement theory dead (IAA is deprecated
since iOS 13 and irrelevant to AUv3 discovery — the founder was right to rule it out, wrong reason).
Real goal: dead-simple in-app loading of EXTERNAL AUv3 effects+instruments; our own AU appearing
is the proof.

## Ranked root causes (senior-Apple-audio synthesis)
1. **[HIGH] Device AudioComponentRegistrar cold/stale.** Strongest fact: founder has MANY
   third-party AUv3 installed yet the log shows **0 third-party**. No manifest bug of OURS can
   cause that. Classic registrar-not-rescanning (DevForums 89762): iOS doesn't re-scan on a
   same-version reinstall. → DEVICE action, not code: delete app → **REBOOT iPhone** → reinstall
   via TestFlight → open AUM/GarageBand plugin list ONCE (warms shared registrar) → reopen Echoel
   → Rescan.
2. **[HIGH] Our own component's stale registration survives because `version` stayed 10000**
   across the 2026-07-16 manifest-STRUCTURE fix (array moved under NSExtensionAttributes). iOS keys
   the registry on type/subtype/manufacturer/**version**; unchanged version → the old failed/no-op
   registration is de-duped and re-served, corrected manifest never re-read. → **CHEAPEST CODE FIX
   (SHIPPED this cycle): bump version 10000→10001** in project.yml:189 + Resources/EchoelmusicAUv3/
   Info.plist:57. Fixes ONLY our own unit; does NOT fix the 0-external (that's cause 1, device-side).
3. **[MED] Appex launch-denial via stale/mismatched provisioning** for com.echoelmusic.app.auv3 →
   registers from plist but -3000 on instantiate in EVERY host. Bisect: if AUM also can't LOAD
   EchoelBodyVibe after reboot-install → confirmed → check archived appex profile in CI.
4. **[MED] Host AVAudioUnitComponentManager.shared() snapshot never refreshes in-launch** (no
   cache-invalidation API on iOS 18). Follow-on option: `AUAudioUnit.registerSubclass(...)` at host
   startup so OUR AU appears regardless of extension-registrar state (does NOT help external).
5. **[MED, product not invisibility] type=augn (Generator) not aumu (MusicDevice).** For an
   instrument, DAWs populate instrument slots from aumu. Deliberate later change; MUST bump version
   again when changed. Do NOT bundle with the discovery fix.

## Device test for founder (discriminates 1/3/4 in ONE reboot cycle)
Prep: install AUM (free) + one free 3rd-party AUv3 effect. Then: (1) delete Echoel; (2) REBOOT
iPhone; (3) reinstall version-bumped build via TestFlight; (4) BEFORE opening Echoel, open AUM/
GarageBand plugin list once, close; (5) open Echoel → AUv3 browser → Rescan.
- (A) external AUs now appear → registry was cold (cause 1); check if EchoelBodyVibe also appears
  (version bump worked).
- (B) external appear but EchoelBodyVibe missing / -3000 → try LOAD it in AUM: AUM also fails →
  launch-denial (cause 3, check CI appex profile); AUM succeeds → Echoel host-process fault (4).
- (C) external still 0 in Echoel but AUM sees them → Echoel in-process snapshot blind (cause 4).
Report which of A/B/C + whether a reboot happened + whether every failing build was genuine
TestFlight (not dev/sideload).

## FOLLOW-ON UX slice (the founder's real goal — ship AFTER discovery proven)
Machinery already exists+solid (AUv3Host scan/retry/diagnostic + AUv3BrowserView + AUPluginRef +
LaneAUInstrumentHost capped/format-preflighted per-lane load). ONLY missing = one-tap lane
assignment (today it's Browse-global → dismiss → reopen lane menu → 'Assign loaded'). Smallest slice
(no new sheet, no new engine, honors laws):
- (a) `enum AUAssignTarget { case global; case lane(UUID, name: String) }` + `var assignTarget =
  .global` on AUv3BrowserView (default = byte-identical today).
- (b) ArrangeTimelineView existing `.sheet(item:)` case `.plugins` → `.plugins(TimelineLane?)`,
  pass invoking lane through the SAME builder (no new modifier — sheet-chain law).
- (c) row() tap: when target is a lane, write directly — instrument via
  `timeline.setLaneInstrument(id:, AUPluginRef(au))`, effect appended via `setLaneEffects`
  respecting maxEffectsPerLane → LaneAUInstrumentHost.syncAssignments instantiates → brief
  'Assigned to <lane>' badge; when .global, unchanged.
- (d) lane-head menu's two entries → one 'Instrument / effect for this track…' opening the browser
  with the lane target.

## STOP rule
No more AUv3 CI entitlement diagnostics (3 automated reads exhausted; see HARNESS_LEDGER dead-end).
Next AUv3 code move after the device test result routes to cause 3 (CI appex-profile check) or 4
(registerSubclass / UX slice).
