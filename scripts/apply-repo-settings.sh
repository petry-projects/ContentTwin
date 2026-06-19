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

# Honour GH_PAT early so every gh api call in this script uses it.
if [ -n "${GH_PAT:-}" ]; then
  export GH_TOKEN="$GH_PAT"
fi

echo "Applying security and analysis settings for: $REPO"

# ── Required security_and_analysis settings ───────────────────────────────────
# Per push-protection.md#required-repo-level-settings, every repository MUST
# have these features enabled.  The compliance audit checks these flags via
# GET /repos/{owner}/{repo} and reports failures as GitHub Issues.
#
# NOTE: `secret_scanning_ai_detection` and `secret_scanning_non_provider_patterns`
# are both GitHub Advanced Security (GHAS) gated features.  When the org has
# `advanced_security_enabled_for_new_repositories=false`, the PATCH above
# succeeds with HTTP 200, but the follow-up verification GET
# (`gh api "repos/$REPO"`, see "Verifying applied settings…" below) silently
# omits these keys from the `security_and_analysis` object — `check_setting`
# will therefore report `unknown` for them, and the compliance audit reads the
# same omitted state as `null`.  The corresponding findings cannot clear from
# this script alone; an org admin must enable GHAS at the org level before
# these settings can take effect.
# See: https://github.com/petry-projects/ContentTwin/issues/203 (secret_scanning_ai_detection)
#      https://github.com/petry-projects/ContentTwin/issues/287 (secret_scanning_non_provider_patterns)

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
# NOTE: This endpoint requires a GitHub App token or a fine-grained PAT with
# Checks: write permission — classic PATs and OAuth app tokens are rejected.
# Because the repo PATCH above also runs when GH_PAT is set, a re-run via
# GH_PAT requires Administration: write as well as Checks: write.
# Set GH_PAT to a supported token; on failure the script warns and exits 1.

echo "Disabling check-suite auto-trigger for Claude app (id: 1236702)..."

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
  echo "  [WARN] check-suite preferences require a fine-grained PAT (Administration: write + Checks: write) or GitHub App token."
  echo "         Re-run with: GH_PAT=<fine-grained-pat> bash scripts/apply-repo-settings.sh"
  exit 1
fi

echo "Done."
