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

echo "Disabling check-suite auto-trigger for Claude app (id: 1236702)..."

gh api -X PATCH "repos/$REPO/check-suites/preferences" --input - <<'JSON'
{
  "auto_trigger_checks": [
    {
      "app_id": 1236702,
      "setting": false
    }
  ]
}
JSON

# ── Loosen first-time contributor approval policy ─────────────────────────────
# The default `first_time_contributors` policy sends every workflow run
# triggered by the Copilot Pull Request Reviewer's `pull_request_review`
# events to `action_required` purgatory, because the Copilot bot is treated
# as a first-time contributor on each PR. fleet_monitor.sh counts
# `action_required` as a failure, which pushed `pr-auto-review.yml` above the
# 10% warning threshold (issue #216). Narrowing the policy to
# `first_time_contributors_new_to_github` only gates accounts that have
# never contributed to anything on GitHub — established bots and external
# reviewers are no longer affected, while genuine drive-by contributors
# from public forks still require approval.

echo "Setting fork-PR contributor approval policy..."

gh api -X PUT "repos/$REPO/actions/permissions/fork-pr-contributor-approval" --input - <<'JSON'
{
  "approval_policy": "first_time_contributors_new_to_github"
}
JSON

POLICY=$(gh api "repos/$REPO/actions/permissions/fork-pr-contributor-approval" \
  --jq '.approval_policy' 2>/dev/null || echo "unknown")
if [ "$POLICY" = "first_time_contributors_new_to_github" ]; then
  echo "  [OK] approval_policy: $POLICY"
else
  echo "  [WARN] approval_policy: $POLICY (expected: first_time_contributors_new_to_github)"
fi

echo "Done."
