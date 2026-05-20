#!/usr/bin/env bash
# apply-repo-settings.sh — Apply GitHub repository-level settings
#
# Usage:
#   gh auth login        # if not already authenticated with admin access
#   bash scripts/apply-repo-settings.sh [REPO_NAME]
#
# REPO_NAME defaults to ContentTwin (used as petry-projects/REPO_NAME).
#
# Requires: gh CLI with repository administration permissions
# Standard: https://github.com/petry-projects/.github/blob/main/standards/github-settings.md
set -euo pipefail

REPO_NAME="${1:-ContentTwin}"
REPO="petry-projects/${REPO_NAME}"

echo "Applying repo settings for: $REPO"

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
check_setting "dependabot_security_updates"

# ── check-suite auto-trigger ──────────────────────────────────────────────────
# Claude (app_id: 1236702) and CodeRabbit must have auto_trigger_checks disabled.
# When enabled, GitHub creates a queued check suite on every push that is never
# completed, permanently blocking auto-merge.
# Standard: github-settings.md § "GitHub Apps & Integrations"

echo "  Disabling check-suite auto-trigger for Claude (app_id: 1236702)..."
echo '{"auto_trigger_checks":[{"app_id":1236702,"setting":false}]}' \
  | gh api "repos/$REPO/check-suites/preferences" -X PATCH --input -

echo "Done. All repo settings applied for $REPO."
