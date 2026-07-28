# Test — Incremental Test Runner

Run only affected tests based on what changed. Faster than full `swift test` during development.

## Steps

### 1. Identify Changed Files
```bash
git diff --name-only HEAD~1 | grep "\.swift$" | grep -v "Tests/"
```

If no changes in last commit, check working tree:
```bash
git diff --name-only | grep "\.swift$"
```

### 2. Map Source → Test Files

For each changed source file, find corresponding test:

| Source Pattern | Test Pattern |
|----------------|-------------|
| `Sources/**/Foo.swift` | `Tests/**/FooTests.swift` |
| `Echoelmusic/**/Foo.swift` | `Tests/**/FooTests.swift` |
| `CoherenceCore/**/Foo.swift` | `Tests/**/FooTests.swift` |

Use grep to find test files importing or referencing the changed types:
```bash
grep -rl "ClassName" Tests/ --include="*.swift" | head -10
```

### 3. Run Affected Tests (platform-aware)

**macOS:**
```bash
swift test --filter "TestClassName" 2>&1
```

If multiple test classes affected, chain filters:
```bash
swift test --filter "TestA|TestB|TestC" 2>&1
```

**Linux/web:**
Note which tests are affected and suggest running via CI:
```bash
echo "Affected tests: [list]. Run on macOS or trigger CI."
```

### 4. Full Suite Fallback

If changed file is a protocol, base class, or shared utility, the whole suite is in scope.

**On macOS with Xcode:**
```bash
swift test 2>&1
```

**Linux/web — which is every session here:** there is no toolchain, so the full suite is
reachable only through CI, and only through the NON-BLOCKING one. Push, then read its log
lines — not its checkmark, which `continue-on-error` keeps green even when nothing compiled:
```bash
python3 scripts/gh-run-status.py <saved-tool-result.json>
# then in the Echoel Full Test Suite (non-blocking) job summary:
#   - build-for-testing:      <-- must say success
#   - test-without-building:  <-- must say success
```
This section had no CI route at all until 2026-07-28 — it inherited the `**Linux/web:**` line
from section 3 above and looked covered. `/ship` was therefore told to "always run the full
suite" with an instruction that cannot execute here.

Always establish the full-suite result before `/ship`.

### 5. Report

```
## Test Results — [N] affected suites

| Suite | Tests | Passed | Failed | Time |
|-------|-------|--------|--------|------|

Total: N passed, M failed
Changed files: [list]
```

### Key Test Files (15 suites, 1060+ methods)

CoreSystemTests | CoreServicesTests | DSPTests | VDSPTests | AudioEngineTests | AdvancedEffectsTests | MIDITests | RecordingTests | BusinessTests | ExportTests | VideoTests | SoundTests | VocalAndNodesTests | HardwareThemeTests | IntegrationTests
