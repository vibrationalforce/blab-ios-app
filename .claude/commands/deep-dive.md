# Deep Dive — Functional Audit

Run a deep functional audit of ALL systems. Find stubs, broken connections, and fake data.

## Strategy
Launch 3 parallel agents for maximum coverage:

### Agent 1: Audio/Sound/MIDI
Scan all files in:
- `Sources/Echoelmusic/Audio/`
- `Sources/Echoelmusic/DSP/`
- `Sources/Echoelmusic/Sequencer/`
- `Sources/Echoelmusic/Tools/`
- `Sources/Echoelmusic/Sync/`

(`Sound/` and `MIDI/` do not exist as directories — MIDI lives in `Audio/MIDIInput.swift`,
`Sequencer/MIDIFile*.swift` and `Sync/`. Scanning a path that is not there returns "clean" for
work nobody looked at — and so does naming a real path in prose without putting it in the scan
list, which is why `Sync/` is now a line above and not a parenthesis: `MIDIBusPublisher`,
`UMPEncoder` and `MPEExpression` live there.)

For each file: verify methods have real implementations, not stubs.
Flag: empty bodies, hardcoded returns, TODO/FIXME, `[Float](repeating: 0, ...)`.

### Agent 2: Video/Recording/Export
Scan all files in:
- `Sources/Echoelmusic/Video/`

(There is no `Recording/` directory; capture lives in `Audio/` and `Video/`. `RetroCapture`,
`LoopExporter` and `SingleExport` are not listed separately — they are all in `Audio/`, which
Agent 1 already scans in full.)

Same stub detection as Agent 1.

### Agent 3: Visual/Bio/Stage/Net
Scan for implementations of:
- EchoelVis (visualization, Metal rendering)
- EchoelBio (HealthKit, bio-reactive)
- EchoelStage (external displays, projection)
- EchoelLux (DMX, Art-Net, lighting)
- EchoelNet (OSC, Dante, cloud sync)

Check if these exist as real code or only as CLAUDE.md documentation.

## Output
Table per system:
| Component | File | Status | Key Issue |

Status: WORKS / PARTIAL / STUB / MISSING
