# docs/ — the published website

Loads only when work touches this directory. Everything here is **PIPELINE**: it ships to
`echoelmusic.com`, never into the app, and never touches `Sources/`.

Measured 2026-08-12. Every number below has its command next to it — re-derive rather than
trust (`.claude/rules/context.md` §2).

```
git ls-files docs/ | wc -l                       → 66 files
git ls-files docs/ | xargs wc -c | tail -1       → 779,910 B
git ls-files 'docs/*.html' 'docs/**/*.html' …    → 24 pages, 395,873 B
```

---

## 1. Two halves in one directory

**The artist page is one file and has no media.** `artist.html` — 204 lines, 15,730 B — is
Echoel (Michael Terbuyken), Hamburg: bio, labels (Tropical Drones ×3, Slow Punch), venues
(Hafenklang, Astra Stube), links. Measured: `grep -c '<audio\|<video\|<iframe\|\.mp3\|\.wav\|\.m4a'`
returns **0**. There is **no player, no embed, no release area, no discography feed**.

⛔ **Do not build one on your own initiative.** A player is a product decision with hosting,
rights and bandwidth attached, and nothing in the repo asks for it. It is linked from 16 other
files (`git grep -ln 'artist\.html' -- docs/ | grep -v docs/artist.html | wc -l`), so it is not
orphaned — it is deliberately thin.

**The other 23 pages are the app site**, plus `docs/dev/` (14 internal markdown files, biggest
`FEATURE_MATRIX.md` at 43,843 B) and `docs/adr/` (1 file). `docs/dev/` is committed to a public
repo — **no tokens, keys or passwords, ever.**

## 2. How the site actually deploys — and the sentence that says otherwise

Two deploy paths exist. **One works, one has been dead for eleven weeks, and a workflow prints
the dead one's name.**

| path | runs | newest | event |
|---|---|---|---|
| `pages-build-deployment` (GitHub's built-in branch builder, `dynamic/pages/…`, id `221917431`) | **3,405** | **2026-08-12T11:27:34Z**, `main` @ `4123728` | `dynamic` |
| `.github/workflows/pages.yml` "Deploy Website" (hand-written, Actions-source) | 363 | **2026-05-28T13:50:26Z** | `push` |

Both re-measured today via `mcp__github__actions_list` → `list_workflow_runs`.

**Why `pages.yml` stopped:** it triggers on `push` to `main`. `auto-merge-docs.yml` merges
`claude/**` → `main` with `GITHUB_TOKEN`, and GitHub raises no workflow-triggering event for
such a push. Measured, not assumed: `list_commits(sha=main, path=docs, since=2026-05-28T14:00Z)`
returns a **full page of 40** docs commits on `main` — and `pages.yml` fired for none of them.

**It does not currently matter, and that is the trap.** The built-in builder runs on every push
to `main` regardless of who pushed, so the site is current. `pages.yml` is a redundant second
path that only becomes load-bearing the day someone flips the Pages source from *branch* to
*GitHub Actions* — at which point the site freezes at the 2026-05-28 artifact. `.nojekyll` is
committed, which is consistent with the branch builder being the live one.

⛔ **`auto-merge-docs.yml:171` prints** *"Website deployment will follow automatically via
pages.yml workflow."* The deployment does follow; **not via `pages.yml`.** The sentence is
wrong about the mechanism, which is exactly the thing you need to be right when debugging.
Founder-gated (`.github/workflows/**`): **report, do not edit.**

**Cloudflare is not in the loop.** `git grep -c wrangler -- .github/workflows/` → **zero**.
`_headers` and `_redirects` are Cloudflare-Pages files sitting on a GitHub-Pages host, so they
are almost certainly inert — GitHub Pages honours neither. **UNVERIFIED from this container**
(the agent proxy 403s `echoelmusic.com`); one command settles it:
`curl -sI https://echoelmusic.com/hilfe` — a `301` means something honours them, a `404` means
they are decoration.

⚠️ **`git log -- docs/` lies here.** This is a shallow clone grafted onto `545b19e`
(`.git/shallow` exists; `git rev-list --count origin/main` → **3**). Local history reaches back
one commit. I ran that query this session and read "1 docs commit since May" — the real number
is ≥40. **Any history question about `docs/` goes to `mcp__github__list_commits`, not to `git log`.**

## 3. A retraction I owe

I told the founder twice that **"8 of 10 `_redirects` aliases have no backing file."** Measured:
there are **8** aliases and **all 8 targets exist** (`/app`, `/download` → `overview.html`;
`/datenschutz`, `/agb`, `/hilfe`, `/barrierefreiheit`, `/gesundheit`, `/sicherheit` → their
`.html`). Neither half of that pair was right. Recorded here so the wrong pair is not re-quoted.

## 4. `version.json` is stale, and it is one of four version numbers

`docs/version.json` says `"version": "10.21.0"`, `"build": "2026-06-17"`. The shipped app is
**v10.79.385**. Four numbers currently disagree:

- `version.json` → `10.21.0`
- `sw.js` → `10.21.0`
- `shared.css?v=` / `shared.js?v=` → `10.14`, in all 16 pages that load them
- `index.html` → carries **both** `10.11.2` and `10.21.0`

`version.json`'s own changelog documents a bug caused by exactly this drift ("the inline
cache-guardian version was stale … forcing a nuke+reload once per session for every visitor").
The drift is back, one field wider.

The `features` block is honest where it matters — `12UnifiedTools`, `3Editions`, `8Personas`,
`generativeWorlds`, `arWorlds` all read `false`. **The `changelog` array is not**: it narrates
AUv3, EchoelBeat, RTMP, "12 unified tools" and `EchoelCreativeWorkspace` as shipped history.
The last of those is a type that has never existed in this repo
(`git ls-files "*EchoelCreativeWorkspace*"` → 0) and it is the same phantom two reviewer agents
carried until 2026-08-12. **A changelog is a claim surface too.**

## 5. Do NOT "fix" the AUv3 and RTMP mentions

`git grep -ci AUv3 -- 'docs/*.html'` sums to **9** hits across 6 pages; RTMP to **10**. Every
single one is a **denial**, not a claim — *"not an AUv3 plugin and not an AUv3 host … both were
built and then deliberately removed"*, *"RTMP was never built — the publisher is a
compile-guarded scaffold and HaishinKit is not linked"*.

#158 and #192 each spent a whole cycle removing the AUv3 **claim** from this site; #184 removed
twelve from the App Store text. What is left is the correction. **A grep hit is not a finding**
— read the sentence before touching it, or you will delete the work those cycles paid for and
reopen a 2.3 rejection risk.

The one list of what is true today is **`ContentPipeline/CLAIMS.md`**. Read it before writing any
page copy, meta description, OG text or press line. Never claim: AUv3 (host or plugin) · RTMP /
live streaming · video **editing** (capture and MP4 export are real; the cut went with #121
Slice 3) · beat maker / drums · MPE out · multitrack recording · motion as a bio input.

## 6. `index.html` is the odd one out

16 of 24 pages load `shared.css` + `shared.js`. Eight do not: three directory-index redirect
stubs (`privacy/`, `terms/`, `support/`, ~450 B each), three screenshot demos, `og-image.html`
— and **`index.html`**, the largest page in the directory at **63,899 B**, which instead carries
one inline `<style>` block of **21,942 chars** and no `shared.js` at all.

That is not automatically a defect (the homepage may want to inline its critical CSS), but it
means **a change to `shared.css` does not reach the homepage**. Any site-wide visual or a11y
change has to be made twice, and the second place is easy to miss. State which one you edited.

## 7. Before you commit a change here

- [ ] Copy checked against `ContentPipeline/CLAIMS.md`. No wellness / healing / esoteric framing,
      no "AUv3", no RTMP, no feature that is not in the app today.
- [ ] If you touched anything cache-versioned, say which of the four numbers you moved — and
      whether the other three now disagree by more than they did.
- [ ] If you touched a site-wide style or a11y rule, confirm whether `index.html` needs the same
      edit inline.
- [ ] German legal pages (`impressum.html`, `privacy.html`, `terms.html`) are legal text, not
      marketing copy. Do not rewrite them for tone.
- [ ] Neither CI gate runs for a docs-only commit — both are `paths:`-filtered to `Sources/**`,
      `Tests/**`, `Package.swift`, `project.yml`. The state is **NOT TRIGGERED**, which is
      neither green nor red. Never report it as green.
- [ ] `.github/workflows/**` stays founder-gated. Findings about `pages.yml` or
      `auto-merge-docs.yml` go in the status delta, not in a diff.
