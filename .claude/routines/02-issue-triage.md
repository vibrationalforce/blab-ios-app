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
   - "Sound doesn't react to heartbeat" → bio mapping range too narrow (see DEEP_RESEARCH doc)
   - "Camera pulse not working" → `isCameraActive` race condition (see BioSourceManager)
   - Build failure with `ITMS-90725` → iOS 26 SDK not used (Xcode < 26.2)
   - `log(.info,...)` compile error → logger called as function instead of method

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
