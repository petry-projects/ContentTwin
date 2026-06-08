#!/usr/bin/env bash
# apply-repo-settings.sh — Apply required repository security and analysis settings
#
# Usage:
#   gh auth login        # if not already authenticated with admin access
#   bash scripts/apply-repo-settings.sh
#
# Requires: gh CLI with repository administration permissions
# Standard: https://github.com/petry-projects/.github/blob/main/standards/push-protection.md#required-repo-level-settings
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-petry-projects/ContentTwin}"

echo "Applying security and analysis settings for: $REPO"

# ── Required security_and_analysis settings ───────────────────────────────────
# Per push-protection.md#required-repo-level-settings, every repository MUST
# have these features enabled.  The compliance audit checks these flags via
# GET /repos/{owner}/{repo} and reports failures as GitHub Issues.

gh api -X PATCH "repos/$REPO" --input - <<'JSON'
{
  "security_and_analysis": {
    "secret_scanning": {"status": "enabled"},
    "secret_scanning_push_protection": {"status": "enabled"},
    "secret_scanning_non_provider_patterns": {"status": "enabled"},
    "secret_scanning_ai_detection": {"status": "enabled"},
    "dependabot_security_updates": {"status": "enabled"}
  }
}
JSON

echo "Verifying applied settings..."

RESULT=$(gh api "repos/$REPO" --jq '.security_and_analysis')

check_setting() {
  local key="$1"
  local status
  status=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('$key', {}).get('status', 'unknown'))")
  if [ "$status" = "enabled" ]; then
    echo "  [OK] $key: enabled"
  else
    echo "  [WARN] $key: $status (expected: enabled)"
  fi
}

check_setting "secret_scanning"
check_setting "secret_scanning_push_protection"
check_setting "secret_scanning_non_provider_patterns"
check_setting "secret_scanning_ai_detection"
check_setting "dependabot_security_updates"

# ── Disable Claude app check-suite auto-trigger ───────────────────────────────
# The Claude GitHub App (id: 1236702) auto-trigger creates a queued check suite
# on every push that is never completed, permanently blocking auto-merge.
# Disabling it prevents GitHub from opening orphaned check suites for this app.
# Standard: https://github.com/petry-projects/.github/blob/main/standards/github-settings.md
#
# NOTE: GitHub only accepts a classic PAT, basic auth, or GitHub App token for
# this endpoint — OAuth app tokens are rejected with 403.  Set GH_PAT to a
# classic PAT with repo scope to apply this step; on failure the script warns
# and exits 0 so security_and_analysis settings above are not rolled back.

echo "Disabling check-suite auto-trigger for Claude app (id: 1236702)..."

# Prefer GH_PAT (classic PAT) for this step; fall back to GH_TOKEN.
_cs_token="${GH_PAT:-${GH_TOKEN:-}}"
if [ -n "$_cs_token" ]; then
  export GH_TOKEN="$_cs_token"
fi
if gh api -X PATCH "repos/$REPO/check-suites/preferences" \
  --input - >/dev/null 2>&1 <<'JSON'; then
{
  "auto_trigger_checks": [
    {
      "app_id": 1236702,
      "setting": false
    }
  ]
}
JSON
  echo "  [OK] check-suite auto-trigger disabled for Claude app (1236702)"
else
  echo "  [WARN] check-suite preferences require a classic PAT or GitHub App token."
  echo "         Re-run with: GH_PAT=<classic-pat> bash scripts/apply-repo-settings.sh"
fi

echo "Done."
