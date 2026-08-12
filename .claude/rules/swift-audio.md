# Swift & Audio Rules — Mandatory for All Code Changes

## Swift 6 Strict Concurrency
- `@MainActor` on ALL `@Observable` view models
- `nonisolated(unsafe)` for audio thread parameters
- `@Sendable` closures where required
- No `self` before `super.init()`
- `Task { @MainActor in }` for async UI updates from non-isolated context

## Audio Thread — ABSOLUTE RULES
These apply to ALL code in DSP kernels and render blocks:

### FORBIDDEN on Audio Thread
```
malloc, free, new, delete          — No heap allocation
Array.append, Array.init           — Allocates
String(), String interpolation     — Allocates
Dictionary operations              — Allocates
class instantiation                — Allocates
NSLog, print, os_log               — I/O (os_log OK in non-render paths)
@objc method calls                 — ObjC runtime
DispatchQueue, Task, async/await   — Thread management
NSLock, pthread_mutex, semaphore   — Blocking
fopen, fclose, read, write         — File I/O
```

### SAFE on Audio Thread
```
Pre-allocated Float arrays         — Index access only
vDSP_* functions                   — Accelerate framework
memcpy, memmove                    — C memory ops
Arithmetic (+, -, *, /)            — Direct computation
sin, cos, pow, sqrt, logf          — C math functions
Ring buffer read/write             — Lock-free patterns
nonisolated(unsafe) property access — Atomic-width reads
```

## Naming Conventions
- Types: `PascalCase` (`VocalDSPKernel`, `EchoelVoiceAudioUnit`)
- Functions/Properties: `camelCase` (`processBlock`, `detectedPitch`)
- Constants: `camelCase` (`defaultSampleRate`)
- Test methods: `test[Unit]_[Scenario]_[Expected]`
- Commit prefixes: `feat:`, `fix:`, `test:`, `refactor:`, `docs:`, `chore:`, `perf:`

## Logging
```swift
// CORRECT — os_log with OSLog instance
os_log(.info, log: Self.auLog, "Message: %{public}@", value)

// WRONG — print (banned)
print("Message")

// WRONG — calling logger as function
log(.info, ...)

// Math log — use logf() or Foundation.log()
let x = logf(frequency)  // NOT log(frequency) — shadows EchoelLogger
```

## Type Safety
```swift
// CORRECT — guard let
guard let format = AVAudioFormat(...) else { throw error }

// WRONG — force unwrap (banned)
let format = AVAudioFormat(...)!

// CORRECT — safe array access
guard index < array.count else { return }

// CORRECT — safe division
guard divisor != 0 else { return defaultValue }
```

## Platform Guards
```swift
// REQUIRED for UIKit code
#if canImport(UIKit)

// REQUIRED for AVFoundation code
#if canImport(AVFoundation)

// REQUIRED for Metal code
#if canImport(Metal)
```

## `DSP/` imports Foundation and Accelerate, nothing else

```
for f in Sources/Echoelmusic/DSP/*.swift; do grep -o '^import [A-Za-z]*' "$f"; done | sort -u
```

Measure, do not quote: today 38 files, set exactly `{Foundation, Accelerate}` (7 take
Accelerate). No control-plane type — `EngineBus`, `BioSampleFrame`, `MusicalFrame`,
`PatternEngine` — in **code** there; the four that appear are in comments. A DSP file that
reaches for a Core or Sequencer type has stopped being a pure processor.

⛔ A block of AUv3 patterns stood here for a target removed 2026-07-24; 3 of its 4 symbols now
occur zero times under `Sources/`. Dead law in the always-loaded set is worse than none —
it is prescriptive, so a session follows it.

⚠️ Reason = hygiene + one-way dependency, **not** portability and **not** AUv3; stated once, in
`FieldSoundSurvivesRelaunchTests` (#416). Do **not** write "Linux-testable": `EchoelWSOLA.swift`
imports Accelerate unguarded where the other 6 use `#if canImport`. Guard, with the long
version of all of this: `TheDSPLayerStaysFoundationOnlyTests`.
