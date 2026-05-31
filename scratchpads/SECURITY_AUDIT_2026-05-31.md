# Security Audit — Echoelmusic (2026-05-31)

Scope-aware: Echoelmusic is a **native iOS app with no backend, no auth
server, no HTTP API, and no database**. So classic web risks (SQL/NoSQL
injection, broken authn/authz, server SSRF) **do not apply** — there is no
server-side attack surface. The real surface is: secrets/CI, on-device
sensitive (health) data, and the LAN I/O (OSC/MIDI/RTMP-roadmap).

Severity scale: 🔴 Critical · 🟠 High · 🟡 Medium · 🟢 Low/Info.

---

## 🔴 C1 — GitHub PAT exposed in the chat transcript
**Finding:** a `github_pat_…` (name `claude-code`) with push/admin scope to
`vibrationalforce/Echoelmusic` was pasted into the chat multiple times (this
session and prior). Transcripts are logged and may be retained/indexed.
**Attack scenario:** anyone who can read a transcript/log can push to the repo,
rewrite CI workflows, and thereby exfiltrate the App Store Connect signing
secrets (the workflow can echo/encode secrets it has access to) — i.e. a path
from "leaked PAT" to "leaked signing key" to malicious TestFlight builds.
**Fix (do now):**
1. Revoke/rotate at github.com/settings/tokens.
2. Replace with a **fine-grained** PAT scoped to this repo only, minimal
   permissions (Contents: RW, Actions: RW), short expiry. Better: a GitHub App
   or Actions OIDC for CI, so no long-lived PAT exists.
3. This session never wrote the token to disk (env-var only); the
   `.claude/settings.local.json` path that prior sessions used is gitignored,
   but on-disk tokens should still be avoided.

## 🟠 H1 — Blast radius of CI signing secrets
`APP_STORE_CONNECT_KEY_ID/ISSUER_ID/PRIVATE_KEY` + `APPLE_TEAM_ID` live in
Actions secrets (correct). Risk is concentration: a compromised PAT (C1) or a
malicious workflow edit can read them. **Recommendations:** enable repo
**Secret Scanning + Push Protection**; require PR review for changes under
`.github/workflows/`; consider environment protection rules so the signing job
needs approval. (A `run_secret_scanning` capability exists via the GitHub MCP —
worth running.)

## 🟡 M1 — Sensitive (health) data at rest is unprotected
`SessionRecorder` persists bio averages (HR/HRV/coherence) as plaintext JSON in
`UserDefaults`; HealthKit-derived values are health data. Low sensitivity
(aggregates, on-device), but **recommend**: store under
`FileProtectionType.complete`, or Keychain for anything identifying, and never
log raw values. Confirm HealthKit usage strings + that no health data leaves
the device except where the user explicitly enables it.

## 🟡 M2 — OSC streams bio data in plaintext over the LAN (UDP)
`OSCSender` broadcasts `/echoelmusic/bio/*`, `/bio/event/*`, `/mod/*` as
unauthenticated, unencrypted UDP to a user-set host:port. By design (TouchDesigner/
Resolume interop), but it is **physiological data on the wire**. **Recommendations:**
keep it **off by default** (it is — explicit start), scope to LAN, document the
exposure, and make the destination clearly user-confirmed. Do not auto-broadcast.

## 🟢 L1 — Network entitlements are broad-but-justified
`NSLocalNetworkUsageDescription` + Bonjour `_artnet._udp`/`_osc` are declared
for OSC/Art-Net. Fine, but Art-Net (EchoelLux) is ROADMAP with no code — keep
the entitlement only if shipping it soon, else trim to reduce surface.

## 🟢 L2 — RTMP (roadmap) will introduce credential handling
When `RTMPPublisher`/HaishinKit lands, stream keys are secrets: store in
Keychain (never UserDefaults/plist), never log, and use RTMPS where the target
supports it.

## 🟢 L3 — Memory-safety / crash-as-DoS hygiene (good)
No force-unwraps/`try!`/`as!` in shipping code (verified); audio thread is
alloc/lock-free; divisions guarded in the new modulation code (NaN/degenerate
range clamped). This closes the most common native crash → local-DoS vectors.

---

## Priority
1. **C1 — rotate the PAT now** (owner action; nothing else matters until done).
2. H1 — turn on Secret Scanning + Push Protection + workflow PR review.
3. M1/M2 — health-data-at-rest protection + document/keep-off OSC bio egress.
4. L2 — Keychain for stream keys when RTMP lands.

No injection, authn, or server-infrastructure findings — because there is no
server. The dominant risk is **secret handling**, not application code.
