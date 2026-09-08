# /multi-plan — Multi-Agent Architecture Planning

Decompose a large task into parallel workstreams executed by specialized agents.

## Usage
`/multi-plan [task description]`

## Protocol

### 1. Task Decomposition
Break the task into independent workstreams that can run in parallel:

```
Agent 1: [Domain] — [Responsibility]
Agent 2: [Domain] — [Responsibility]
Agent 3: [Domain] — [Responsibility]
```

### 2. Default Echoelmusic Decomposition

For feature work:
```
Agent 1: DSP Kernel    — Lock-free audio processing implementation (DSP/, Foundation+Accelerate only)
Agent 2: Control plane — EngineBus subscriber, *Store/Codable persistence, EchoelParameterRegistry
                         + ParameterApplyRouter (the keyPath→live-setter seam), FeatureFlags
Agent 3: UI/Visual     — SwiftUI leaf view (no hot @Observable read in an ancestor), output-stage subscriber
```
⛔ "Agent 2: AUv3 Shell — AudioUnit, parameter tree, state, presets" stood here until #1112
(and Agent 3 said "ViewController"). The AUv3 extension target went 2026-07-24 (#121 Slice 2);
`AUParameterGroup` / `fullState` occur zero times in `Sources/`. A decomposition with an AUv3
agent hands one third of every feature to a product that does not exist. The ONE `AUAudioUnit`
in the tree is the in-process `MonitorInsertAudioUnit` (`Audio/MonitorInsertAU.swift`) — a
graph node on the mic rail, owned by the DSP/audio agent when a feature touches it, not a shell.

For audits:
```
Agent 1: Core Systems  — App init, data flow, engine wiring
Agent 2: UI Layer      — Views, environment objects, navigation
Agent 3: Domain Logic  — Audio, bio, visual, lighting pipelines
```

For bug investigation:
```
Agent 1: Error Source   — Trace the error to its origin
Agent 2: Impact Scan    — Find all code affected by the issue
Agent 3: Fix + Test     — Implement fix and write regression test
```

### 3. Dependency Graph
Before launching agents, identify:
- Which agents are truly independent (can run in parallel)
- Which agents depend on outputs of others (must be sequential)
- Shared resources (files both agents might modify)

### 4. Launch Template
```
Launch Agent 1: [description]
  - Focus: [files/directories]
  - Output: [what to return]
  - Constraints: [don't modify X, read-only, etc.]

Launch Agent 2: [description]
  - Focus: [files/directories]
  - Output: [what to return]
  - Constraints: [...]

Launch Agent 3: [description]
  - Focus: [files/directories]
  - Output: [what to return]
  - Constraints: [...]
```

### 5. Synthesis
After all agents complete:
1. Merge findings/code from all agents
2. Resolve any conflicts
3. Run `/verify` to validate the combined result
4. Commit with clear description of what each agent contributed

## Rules
- Maximum 3 parallel agents (diminishing returns beyond that)
- Each agent gets a clear, non-overlapping scope
- Agents should NOT modify the same files
- If conflicts arise, human decides
- Always run `/verify` after merging agent outputs
