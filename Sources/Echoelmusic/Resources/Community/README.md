# Community library (bundled)

Open, version-controlled store for community-submitted Echoel presets — no
backend, no lock-in. The repo *is* the community store, and these files ship
**in-app** (loaded by `CommunityLibrary` via `Bundle.module`).

- `fx/*.json` — `FXPreset` JSON (effects chains) → appended to the FX library
- `patches/*.json` — `SynthPatch` JSON (synth sounds) → "Community" in the Sound editor

Submissions arrive via the app's **Submit to community** action, which composes a
pre-addressed email to the curator with the preset JSON embedded (no GitHub
account or app needed — works on any device with Mail). The curator drops the
JSON into the matching folder here and commits it; **shipping the file ships the
preset** on the next build. (The legacy GitHub-issue path + `community-triage`
workflow remain available but are no longer the in-app default.)
