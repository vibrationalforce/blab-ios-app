#!/usr/bin/env python3
"""Community submission triage.

Runs on submission issues filed by the in-app "Submit to community" flow.
Extracts the embedded JSON, validates it, and — if valid — opens a PR adding
it to the bundled community library (the PR review IS the curation gate). On
failure it comments the reason on the issue. Defensive by design: any error is
reported as an issue comment rather than failing the job.
"""
import json
import os
import re
import subprocess
import sys


def sh(*args, check=True):
    """Run a command, returning stdout (text)."""
    return subprocess.run(args, check=check, capture_output=True, text=True).stdout.strip()


def comment(issue, body):
    try:
        sh("gh", "issue", "comment", str(issue), "--body", body)
    except Exception as exc:  # never fail the job over a comment
        print(f"comment failed: {exc}", file=sys.stderr)


def slugify(name):
    s = re.sub(r"[^a-zA-Z0-9]+", "-", name.strip().lower()).strip("-")
    return s[:48] or "preset"


def extract_json(body):
    m = re.search(r"```json\s*(.*?)```", body or "", re.DOTALL)
    if not m:
        return None
    return m.group(1).strip()


def main():
    title = os.environ.get("ISSUE_TITLE", "")
    body = os.environ.get("ISSUE_BODY", "")
    issue = os.environ.get("ISSUE_NUMBER", "")

    if title.startswith("Preset submission:"):
        kind, subdir, required = "FX preset", "fx", ("name", "schema")
    elif title.startswith("Patch submission:"):
        kind, subdir, required = "sound patch", "patches", ("id", "name")
    elif title.startswith("Mood submission:"):
        kind, subdir, required = "mood", "moods", ("id", "name")
    else:
        print("not a submission issue; skipping")
        return

    raw = extract_json(body)
    if raw is None:
        comment(issue, "❌ Couldn't find a ```json``` block in this submission. "
                       "Please submit via the app's **Submit to community** action.")
        return
    try:
        obj = json.loads(raw)
    except json.JSONDecodeError as exc:
        comment(issue, f"❌ The {kind} JSON didn't parse: `{exc}`.")
        return

    missing = [k for k in required if k not in obj]
    if missing:
        comment(issue, f"❌ The {kind} JSON is missing required field(s): "
                       f"`{', '.join(missing)}`.")
        return

    name = str(obj.get("name", "preset"))
    slug = slugify(name)
    # Write under the SwiftPM/Xcode resource root so a merged PR ships in-app
    # (CommunityLibrary loads Resources/Community/{fx,patches}/*.json).
    rel = f"Sources/Echoelmusic/Resources/Community/{subdir}/{slug}.json"
    os.makedirs(os.path.dirname(rel), exist_ok=True)
    with open(rel, "w") as f:
        json.dump(obj, f, indent=2, sort_keys=True)

    branch = f"community/submission-{issue}"
    sh("git", "config", "user.name", "echoel-triage")
    sh("git", "config", "user.email", "noreply@echoelmusic.com")
    sh("git", "checkout", "-b", branch)
    sh("git", "add", rel)
    # Nothing changed (resubmit of an identical preset) → just acknowledge.
    if sh("git", "status", "--porcelain"):
        sh("git", "commit", "-m", f"community: add {kind} '{name}' (#{issue})")
        sh("git", "push", "-u", "origin", branch, "--force")
        try:
            pr = sh("gh", "pr", "create",
                    "--title", f"Community {kind}: {name}",
                    "--body", f"Automated from #{issue}. Adds `{rel}`.\n\n"
                              f"Merging curates this into the bundled library.",
                    "--head", branch)
            comment(issue, f"✅ Validated and staged a PR: {pr}\n\n"
                           f"A maintainer will review it for the community library.")
        except Exception as exc:
            comment(issue, f"✅ Validated, but opening the PR failed: `{exc}`. "
                           f"A maintainer can open it from branch `{branch}`.")
    else:
        comment(issue, f"✅ Validated. This {kind} already exists in the library "
                       f"(`{rel}`) — nothing to add.")


if __name__ == "__main__":
    main()
