# Community library

Open, version-controlled store for community-submitted Echoel presets — no
backend, no lock-in. The repo *is* the community store.

- `fx/*.json` — `FXPreset` JSON (effects chains)
- `patches/*.json` — `SynthPatch` JSON (synth sounds)

Submissions arrive via the app's **Submit to community** action, which opens a
GitHub issue with the preset embedded. The `community-triage` workflow validates
it and opens a PR adding the file here. **Merging a PR curates it** — the in-app
loader bundles everything under `curated/` into the community libraries.
