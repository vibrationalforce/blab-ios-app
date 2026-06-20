# PLAN — EchoelUI Design System + IA (pro-suite pivot)
Date: 2026-06-20 · Branch: claude/piano-roll-clip-view-wozlie
Source: parallel planning agent (design-system + usability/IA). Companion to
`PLAN_PRO_PRODUCTION_SUITE.md` (engine) + `PLAN_TRANSPORT_CLOCK.md` (clock).

## Why
Today everything is one `EchoelStudioView.swift` (~1561 lines) whose tokens, panel
chrome (`panel`/`labeledRow`/`groupHeader`), buttons and preset bars are PRIVATE
helpers inlined in the root view. The Clips/Arrangement/FX sheets reuse the look
only by copy-pasting `RoundedRectangle(...).fill(.fill).strokeBorder(.border)` —
drift guaranteed once Video + Broadcast land. Extract a real design system so
off-brand UI becomes hard to *write*; then an IA that adds pro depth without a
tab-explosion or a god-view.

Anchors (confirmed in code): monochrome CI (`accent`=bio-green is SIGNAL ONLY;
primary fill = `.text` off-white + black label), radii ≤12, `EchoelValueField` =
sole parameter control, Atkinson Hyperlegible + Dynamic Type + pinch-zoom, WCAG
≤3 Hz flash.

## Part 1 — `EchoelUI` module (new `Studio/UI/`, main app only; AUv3 stays exempt)
1. **Tokens** — promote `EchoelTheme` to the single source; add a SEMANTIC layer so
   surfaces never touch raw colors: `Role.primaryFill = text`, `Role.signal = accent`
   (bio only), `Role.destructive = danger`, `Role.chromeBorder = border`. Add spacing
   scale + `maxShadowBlur = 8`. (Wrap, do NOT fork EchoelTheme.)
2. **Parameter control** — `EchoelValueField` FROZEN as-is; add only `EchoelUI.parameterRow`
   convenience so Video (trim secs) + Broadcast (bitrate kbps) get the identical
   vertical-fader-drag / tap-to-type for free. No raw Slider/Stepper anywhere.
3. **`EchoelButton`** — `.primary` (`.text` fill, black label, 48–56pt), `.secondary`
   (`.fill` + 1px border), `.ghost` (label only). `signal` bool swaps active stroke to
   accent only for live-bio controls. 44pt min hit target.
4. **`EchoelPanel`** — extract the private `panel(...)` verbatim; **hard rule: a panel
   refuses to nest in a panel** (no card-in-card) — deep editors get their own sheet.
5. **`EchoelRow`** — label-above-value, color-only hover/selection (no scale), 1px sep.
6. **`EchoelSheet`** — NavigationStack wrapper (inline title, confirm/cancel slots, Done)
   so every deep editor opens/closes identically.
7. **`EchoelEmptyState`** — icon + one honest line + one primary action (the device-video
   "dead strip" finding generalized). Never decorative.
8. **Accessibility primitives** — `accessibilityAdjustableAction` helper, `tapToLearn`
   (BioStrip metric-info pattern), reduce-motion gate, `flashSafe(maxHz:)` wrapping
   FlashGuard so EVERY visual surface is WCAG-bounded by construction.

## Part 2 — IA: one home, depth on demand
Keep the single `EchoelStudioView` as permanent home; pro depth = full-screen
workspaces from ONE explicit switcher (never new permanent tabs). Bio strip stays
the always-on front door.

| Arc stage | Surface | Level |
|---|---|---|
| **Create from within** | Today's home — BioStrip gateway + one button + collapsible panels | 0 (always) |
| **Produce professional** | Workspace switcher → full-screen: Clips · Arrangement · Mix · Sound Editor · Video/NLE · Broadcast | 1 (one tap, returns home) |
| **Bring it live (wings)** | Live/Performance mode — eyes-free: big bio readout, transport, scene/clip launch, stream-armed; editing chrome locked away | 2 (explicit arm) |

Avoids: tab-explosion (one switcher ≤6 entries, grouped Produce/Live; dead `StudioRoot`
stays dead) · god-view (home never grows; workspaces couple via `EngineBus`, not shared
view state) · card-in-card (`EchoelPanel` no-nest). Tools menu graduates: navigation →
switcher; toggles → Settings sheet; version/diag → Settings footer.

## Part 3 — Usability principles
1. One-tap to life (BioStrip "Read pulse" + "Create from Within" sacrosanct; Live = one arm).
2. Eyes-free Live mode: targets ≥56pt, oversized bio numbers, accent=live/amber=acquiring/
   neutral=idle, haptic transport, no text-entry, no destructive controls.
3. Accessibility-first everywhere (EchoelValueField VoiceOver template; Dynamic Type +
   pinch-zoom in Video/Broadcast too; flash-safe by construction).
4. One control everywhere (bitrate, trim, sends, crossfades = all EchoelValueField).
5. Undo-everywhere readiness: a single `EchoelEdit` command seam through one store so
   Arrangement/Clip/Video edits are undoable from day one (plan-only; Council gate).
6. Honest state, never fake data (green only on fresh real signal; empty states say
   "none yet + how to make one").

## Part 4 — Bounded CI-green cycles (one per Ralph cycle, ≤3 files)
1. Extract tokens (`Studio/UI/EchoelUITokens.swift`) wrapping EchoelTheme + Role/spacing.
2. Extract chrome (`EchoelButton/Panel/Row/Sheet/EmptyState`); EchoelValueField untouched.
3. Adopt in home (delete private helpers) — byte-identical UI.
4. Adopt in existing sheets (Clip/Arrangement/FX/Patch) — kill copy-paste chrome.
5. IA seam: split Tools menu → Workspace switcher + Settings sheet (reversible).
6. New Video/Broadcast surfaces built ON EchoelUI from first commit.

## Risks / gates
Mechanical-refactor visual regression → one surface per cycle, screenshot diff, never
batch · token wrapper must wrap not fork · EchoelValueField frozen (Council to change) ·
undo seam touches multiple stores → Council before implementing · AUv3 must NOT import
EchoelUI (keep exemption; `Studio/UI/` = main target only). Gate each cycle on the REAL
xcode-compile-check job, not a build_only dryrun.

## Files
EXTRACT FROM: EchoelStudioView.swift (panel/labeledRow/groupHeader/button + preset-bar,
~289–907, 958–1021) · WRAP: EchoelTheme.swift · FROZEN: EchoelValueField.swift ·
GENERALIZE: BioStripView.swift (front door, honest-state, tap-to-learn), FlashGuard.swift
→ flashSafe · ADOPT: ClipView/ArrangementView/EchoelFXView/PatchEditorView · NEW:
Studio/UI/{EchoelUITokens,EchoelButton,EchoelPanel,EchoelRow,EchoelSheet,EchoelEmptyState}.swift
