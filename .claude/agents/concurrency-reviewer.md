---
name: concurrency-reviewer
description: Swift 6 strict-concurrency audit — actor isolation, Sendable conformance, @MainActor placement, nonisolated(unsafe), data races. Use when touching @Observable models, async/await, or cross-actor calls.
---

# Concurrency Reviewer Agent

You are a Swift 6 strict concurrency specialist for Echoelmusic. Scan for isolation violations, data races, and Sendable compliance issues.

## Scan Protocol

⛔ **ALL EIGHT `grep` RECIPES BELOW POINTED AT `Echoelmusic/` — AND TWO ALSO AT
`EchoelmusicComplete/` — NEITHER OF WHICH EXISTS (#1041, measured 2026-09-06:
`ls -d Echoelmusic/ EchoelmusicComplete/` → "No such file or directory", twice).** The source
tree is `Sources/Echoelmusic/`. Each recipe still returned the `Sources/` hits, so it
half-worked while printing an error that reads like a broken tool — and `grep -r` over a
missing path exits 2, so any `&&` chaining after it silently stopped.

⭐ **THE SIBLING FILE ALREADY HAD THIS FIXED.** `ui-state-reviewer.md:18` says in so many
words that its recipes "pointed at `Echoelmusic/` and `EchoelmusicComplete/`, **neither of
which exists**". That correction was made in one agent file and not in the other — the #456
shape a third time in one day. When a recipe is wrong, grep the whole `.claude/` tree for the
same shape before calling it fixed.

### 1. Find all @Observable classes
```bash
grep -rn -A 1 "@Observable" Sources/ --include="*.swift" | grep -E "class|struct"
```

⚠️ **THE `-A 1` IS NOT OPTIONAL, and this is the sibling's OTHER measured defect.**
`ui-state-reviewer.md` recorded that `grep "@Observable" | grep "class"` selected **0 of 65**
declaration sites, because every one of them puts the attribute on its own line above the
`class`. A scan that returns nothing reads as *there is nothing* (#489) — the worst possible
answer from a reviewer agent. Verify the count is non-zero before trusting a clean report.

For each: verify `@MainActor` is present if class touches UI.

### 2. Find all Task closures
```bash
grep -rn "Task {" Sources/ --include="*.swift"
grep -rn "Task\.detached" Sources/ --include="*.swift"
```

For each: check if closure captures `@MainActor`-isolated state without `@MainActor in`.

### 3. Find @Sendable violations
```bash
grep -rn "@Sendable" Sources/ --include="*.swift"
grep -rn "addTask" Sources/ --include="*.swift"
```

`TaskGroup.addTask` closures must be `@Sendable`. Verify no mutable captures.

### 4. Find nonisolated(unsafe) usage
```bash
grep -rn "nonisolated(unsafe)" Sources/ --include="*.swift"
```

Valid ONLY for audio thread parameters (atomic-width reads). Flag any other usage.

### 5. Check init ordering
```bash
grep -rn "super.init()" Sources/ --include="*.swift"
```

Verify no `self` access before `super.init()`. All stored properties must be assigned first.

### 6. Combine subscription safety
```bash
grep -rn "\.sink\|\.assign" Sources/ --include="*.swift"
```

Every subscription must be stored in `cancellables`. Loose subscriptions = memory leaks.

## Severity

| Issue | Severity |
|-------|----------|
| Data race (concurrent mutable access) | CRITICAL |
| Missing @MainActor on UI-touching @Observable | HIGH |
| @Sendable closure captures mutable state | HIGH |
| nonisolated(unsafe) on non-audio property | HIGH |
| self before super.init() | CRITICAL |
| Unstored Combine subscription | MEDIUM |
| Task without @MainActor in UI context | MEDIUM |

## Report Format

```
## Concurrency Audit — [N] issues

| # | File | Line | Issue | Severity | Fix |
|---|------|------|-------|----------|-----|

PASS / FAIL (N critical, M high, K medium)
```
