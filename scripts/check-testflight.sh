#!/usr/bin/env bash
# =============================================================================
# scripts/check-testflight.sh
# =============================================================================
# Local helper for diagnosing TestFlight workflow failures from the Echoelmusic
# repo. Reads the GitHub token from .claude/settings.local.json (gitignored,
# per project CLAUDE.md §"GitHub API Access"), queries recent testflight.yml
# runs via GitHub REST API, and prints the failed-job logs.
#
# Why this exists: the remote Claude Code container does not have `gh` CLI or
# direct GitHub API access — its GitHub access is routed through the MCP
# server which does not expose workflow_runs / workflow_run_logs endpoints.
# This script bridges that gap with one local invocation. The token never
# leaves the local machine.
#
# Usage:
#   bash scripts/check-testflight.sh            # latest 5 runs + last failed log
#   bash scripts/check-testflight.sh runs       # just list recent runs
#   bash scripts/check-testflight.sh dispatch   # dispatch a new build_only run
#
# Requires: jq, curl. (Both ship with macOS Xcode CLT or are one `brew install`
# away.)
# =============================================================================

set -euo pipefail

OWNER="vibrationalforce"
REPO="Echoelmusic"
WORKFLOW="testflight.yml"
BRANCH="claude/echoelmusic-audit-testflight-2bYik"

SETTINGS_FILE=".claude/settings.local.json"

# ---------------------------------------------------------------------------
# Token resolution — read from .claude/settings.local.json (gitignored).
# ---------------------------------------------------------------------------
if [[ ! -f "$SETTINGS_FILE" ]]; then
  echo "ERROR: $SETTINGS_FILE not found." >&2
  echo "       Create it per CLAUDE.md §\"GitHub API Access\":" >&2
  echo '       { "github": { "token": "ghp_..." } }' >&2
  exit 1
fi

TOKEN=$(jq -r '.github.token // empty' "$SETTINGS_FILE")
if [[ -z "$TOKEN" ]]; then
  echo "ERROR: .github.token missing or empty in $SETTINGS_FILE" >&2
  exit 1
fi

api() {
  curl -fsS \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@"
}

# ---------------------------------------------------------------------------
# Sub-command: dispatch
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "dispatch" ]]; then
  echo "Dispatching $WORKFLOW (platform=ios, build_only=true) on $BRANCH..."
  api -X POST \
    "https://api.github.com/repos/$OWNER/$REPO/actions/workflows/$WORKFLOW/dispatches" \
    -d "{\"ref\":\"$BRANCH\",\"inputs\":{\"platform\":\"ios\",\"build_only\":\"true\"}}"
  echo "Dispatched. Run \`bash $0\` in 30 seconds to see status."
  exit 0
fi

# ---------------------------------------------------------------------------
# List recent runs
# ---------------------------------------------------------------------------
echo "=== Last 5 $WORKFLOW runs ==="
RUNS=$(api "https://api.github.com/repos/$OWNER/$REPO/actions/workflows/$WORKFLOW/runs?per_page=5")

echo "$RUNS" | jq -r '.workflow_runs[] | "\(.run_number)\t\(.status)\t\(.conclusion // "—")\t\(.head_branch)\t\(.head_sha[0:7])\t\(.created_at)"' \
  | awk -F'\t' 'BEGIN{printf "%-6s %-12s %-12s %-50s %-10s %s\n","RUN","STATUS","CONCLUSION","BRANCH","SHA","CREATED"} {printf "%-6s %-12s %-12s %-50s %-10s %s\n",$1,$2,$3,$4,$5,$6}'

if [[ "${1:-}" == "runs" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Find most recent failed run, fetch failed-job logs
# ---------------------------------------------------------------------------
echo
echo "=== Latest FAILED run — failed-job log ==="

FAILED_RUN_ID=$(echo "$RUNS" | jq -r '[.workflow_runs[] | select(.conclusion == "failure")][0].id // empty')

if [[ -z "$FAILED_RUN_ID" ]]; then
  echo "(no failed runs in the last 5)"
  exit 0
fi

echo "Run ID: $FAILED_RUN_ID"
echo

JOBS=$(api "https://api.github.com/repos/$OWNER/$REPO/actions/runs/$FAILED_RUN_ID/jobs")
echo "Jobs in this run:"
echo "$JOBS" | jq -r '.jobs[] | "  \(.conclusion // .status)\t\(.name)"'
echo

FAILED_JOB_ID=$(echo "$JOBS" | jq -r '[.jobs[] | select(.conclusion == "failure")][0].id // empty')

if [[ -z "$FAILED_JOB_ID" ]]; then
  echo "(no individual job marked failure — run may have been cancelled)"
  exit 0
fi

FAILED_JOB_NAME=$(echo "$JOBS" | jq -r ".jobs[] | select(.id == $FAILED_JOB_ID) | .name")
echo "=== Failed job: $FAILED_JOB_NAME ==="
echo "=== Last 80 lines of log ==="
echo
api "https://api.github.com/repos/$OWNER/$REPO/actions/jobs/$FAILED_JOB_ID/logs" | tail -80
