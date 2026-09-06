# Routine #2 — Issue Triage

**Triggers:** `issues.opened` on `vibrationalforce/Echoelmusic`
**Runs on:** Anthropic cloud (Linux, no iOS SDK)
**Status:** Active

When pasting into claude.ai: prepend `_golden-goal.md` verbatim, then this file.

---

## Your job

First responder on new GitHub issues. Classify, label, acknowledge, and route.
Never close an issue. Never commit a fix directly. Draft only.

### Step-by-step

1. **Read the issue:**
   ```bash
   gh issue view <n> --repo vibrationalforce/Echoelmusic --json title,body,author,labels,createdAt
   ```

2. **Classify by type:**

   | Type | Label | Description |
   |------|-------|-------------|
   | App crash | `bug/crash` | Force unwrap, nil access, audio thread violation |
   | Wrong sound | `bug/audio` | DSP output incorrect, mappings inverted |
   | Bio data wrong | `bug/bio` | HR/HRV/coherence reads incorrect |
   | TestFlight feedback | `feedback/testflight` | From internal testers |
   | Feature request | `enhancement` | New capability |
   | Build failure | `bug/build` | CI failing, compile error |
   | Science concern | `science/review` | Wellness claim needs citation |
   | Design concern | `design` | UI violates constraints |
   | Docs update | `docs` | CLAUDE.md, README, scratchpads |

3. **Assess priority:**

   | Priority | Label | Criteria |
   |----------|-------|----------|
   | 🔴 Critical | `priority/critical` | Crash, TestFlight rejection risk, audio thread violation |
   | 🟡 High | `priority/high` | Bio data wrong, key feature broken |
   | 🟢 Normal | `priority/normal` | Enhancement, minor bug |
   | ⚪ Low | `priority/low` | Docs, cosmetic |

4. **Check for known patterns:**
   - Crash with `EXC_BAD_ACCESS` → likely audio thread violation (malloc/ObjC in render block)
   - Build failure with `ITMS-90725` → iOS 26 SDK not used (Xcode < 26.2)
   - `log(.info,...)` compile error → logger called as function instead of method
   - Black screen at launch, nothing renders → the `.sheet`-chain metadata ceiling
     (`swiftui-render-safety`; 14 presentation modifiers on `EchoelStudioView.body`)
   - Picker/menu freezes ONLY while biofeedback runs → a ~10 Hz `@Observable` read in an
     ANCESTOR body, not in the obvious view (`swiftui-render-safety`, the 10.76.50 law)

   ⛔ **TWO ROUTES STOOD HERE AND POINTED AT THINGS THAT NO LONGER EXIST (#1041, measured
   2026-09-06).** Both were replaced rather than deleted, because the SYMPTOMS are real and a
   triage list with a hole sends the reporter nowhere:
   - ⛔ `"Sound doesn't react to heartbeat" → see DEEP_RESEARCH doc`. There is no such
     document anywhere in the repo. **The live map is CLAUDE.md's "DDSP Bio-Mappings" table**,
     which also names the channels that have NO producer — the far likelier cause of "it does
     not react": `breathDepth` and `lfHf` are pinned constants at both construction sites.
   - ⛔ `"Camera pulse not working" → isCameraActive race condition (see BioSourceManager)`.
     `isCameraActive` and `BioSourceManager` are both **0 hits** in `Sources/`; the manager was
     deleted in the 2026-06-19 cleanup. **The live path is `CameraRPPGBioPublisher`**, and the
     known causes are the torch/exposure lock (fixed 2026-06-18) and the frame-stall watchdog.

5. **Apply labels:**
   ```bash
   gh issue edit <n> --repo vibrationalforce/Echoelmusic --add-label "<label>"
   ```

6. **Post triage comment:**
   ```bash
   gh issue comment <n> --repo vibrationalforce/Echoelmusic --body "..."
   ```

### Comment template

```markdown
Thanks for the report. Here's my initial triage:

**Type:** <bug/crash | bug/audio | enhancement | ...>
**Priority:** <critical | high | normal | low>

**Initial assessment:**
<2-3 sentences: what the issue likely is, which file/system is involved>

**Relevant code:**
`Sources/Echoelmusic/<path>:<line>` — <why this is relevant>

**Suggested next step:**
<One specific action: "Check render block for Array allocation" / "Verify Watch HR latency compensation" / etc.>

---
*Automated triage — @vibrationalforce please verify and assign.*
```
