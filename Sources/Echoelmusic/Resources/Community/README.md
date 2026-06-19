# Community library (bundled)

Open, version-controlled store for community-submitted Echoel presets — no
backend, no lock-in. The repo *is* the community store, and these files ship
**in-app** (loaded by `CommunityLibrary` via `Bundle.module`).

- `fx/*.json` — `FXPreset` JSON (effects chains) → appended to the FX library
- `patches/*.json` — `SynthPatch` JSON (synth sounds) → "Community" in the Sound editor

Submissions arrive via the app's **Submit to community** action, which opens a
GitHub issue with the preset embedded. The `community-triage` workflow validates
it and opens a PR adding the file here. **Merging a PR ships it** on the next build.
