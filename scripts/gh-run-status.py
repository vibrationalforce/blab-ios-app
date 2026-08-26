#!/usr/bin/env python3
"""gh-run-status.py — compact CI status from a GitHub MCP tool-result dump.

The `mcp__github__actions_list` / `actions_get` tools return ~400 KB of JSON that
overflows the tool-result budget and gets spilled to a file. Reading that file
back blows context. This helper parses the SAVED file (path printed in the
overflow message) and prints just what a deploy decision needs:

    <sha7>  <status>  <conclusion>  <run_id>  <workflow name>  <display_title>

The WORKFLOW NAME column is not decoration. For a push run GitHub sets `display_title`
to the commit-message headline, so a title-only listing can never answer "is Xcode
Compile Check green?" — and that is the question every one of our commands tells the
agent to ask. `name` is the workflow's own `name:` field, which is what to match on.

Usage:
    python3 scripts/gh-run-status.py <saved-tool-result.json> [--limit N]

Works on the shapes the tools emit:
  • a single run object (actions_get get_workflow_run)
  • {"workflow_runs": [...]} or a bare [...] (actions_list list_workflow_runs)
  • the MCP text envelope [{"type": "text", "text": "<json>"}] some persisted
    tool results wrap the payload in. ⛔ The first version did not know this
    shape: json.load SUCCEEDED (the envelope is valid JSON), _rows walked a
    list whose one dict has no head_sha, and the output was a single
    "?  -  ?  ?" row — wrong, but not silent. Same defect class as #738 in
    gh-test-verdict.py: a JSON parse that succeeds is not a decode that
    worked. The unwrap below re-parses the inner text.

Zero deps (stdlib only). Never touches the network — it only reads a local file
the MCP tool already wrote, so it composes with the tokenless / MCP-only setup.
"""
import json
import sys


def _unwrap_text_envelope(data):
    """Resolve the MCP persisted-output shape [{"type":"text","text":"<json>"}].

    Only unwraps when EVERY list item is such an envelope, so a bare list of
    run objects (which _rows handles) is never touched. The inner texts are
    each parsed; a single payload is returned as-is, several are merged by
    concatenating their run lists.
    """
    if not (isinstance(data, list) and data
            and all(isinstance(i, dict) and i.get("type") == "text"
                    and isinstance(i.get("text"), str) for i in data)):
        return data
    payloads = []
    for item in data:
        try:
            payloads.append(json.loads(item["text"]))
        except ValueError:
            return data  # inner text is not JSON — leave the caller's data alone
    if len(payloads) == 1:
        return payloads[0]
    merged = []
    for p in payloads:
        if isinstance(p, dict) and "workflow_runs" in p:
            merged.extend(p["workflow_runs"])
        elif isinstance(p, list):
            merged.extend(p)
        else:
            merged.append(p)
    return merged


def _rows(data):
    data = _unwrap_text_envelope(data)
    if isinstance(data, dict) and "workflow_runs" in data:
        runs = data["workflow_runs"]
    elif isinstance(data, list):
        runs = data
    else:
        runs = [data]  # a single run object
    for r in runs:
        if not isinstance(r, dict):
            continue
        sha = str(r.get("head_sha", ""))[:7]
        yield (
            sha,
            r.get("status", "?"),
            r.get("conclusion") or "-",
            r.get("id", "?"),
            (r.get("name") or "?")[:30],
            (r.get("display_title") or "")[:44],
        )


def main(argv):
    args = [a for a in argv[1:] if not a.startswith("--")]
    limit = None
    for a in argv[1:]:
        if a.startswith("--limit"):
            try:
                limit = int(a.split("=", 1)[1]) if "=" in a else int(argv[argv.index(a) + 1])
            except (ValueError, IndexError):
                limit = None
    if not args:
        print(__doc__)
        return 2
    try:
        with open(args[0], "r") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as exc:
        print(f"error: cannot read/parse {args[0]}: {exc}", file=sys.stderr)
        return 1

    rows = list(_rows(data))
    if limit:
        rows = rows[:limit]
    for sha, status, concl, rid, wf, title in rows:
        print(f"{sha}  {status:<12} {concl:<10} {rid}  {wf:<30} {title}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
