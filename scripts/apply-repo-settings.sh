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
# NOTE: `secret_scanning_ai_detection` is a GitHub Advanced Security (GHAS)
# gated feature.  When the org has
# `advanced_security_enabled_for_new_repositories=false`, the PATCH above
# succeeds with HTTP 200, but the follow-up verification GET
# (`gh api "repos/$REPO"`, see "Verifying applied settings…" below) silently
# omits this key from the `security_and_analysis` object — `check_setting`
# will therefore report `unknown` for it, and the compliance audit reads the
# same omitted state as `null`.  The corresponding finding cannot clear from
# this script alone; an org admin must enable GHAS at the org level before
# this setting can take effect.  See: https://github.com/petry-projects/ContentTwin/issues/203

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

# Read back the check-suite preferences PATCH response and confirm the Claude
# app auto-trigger setting is present and disabled. Reports readability so a
# `check-suite-prefs-unreadable` finding can be cleared with confidence.
verify_check_suite_pref() {
  local file="$1"
  local setting
  setting=$(
    python3 - "$file" <<'PY' 2>/dev/null || true
import json, sys
try:
    with open(sys.argv[1]) as f:
        d = json.load(f)
    checks = d.get("preferences", {}).get("auto_trigger_checks")
    if not isinstance(checks, list):
        raise ValueError
    by_app = {c.get("app_id"): c.get("setting") for c in checks if isinstance(c, dict)}
    print(str(by_app.get(1236702, "missing")).lower())
except Exception:
    print("unreadable")
PY
  )
  if [ "$setting" = "false" ]; then
    echo "  [OK] check-suite preferences readable; auto-trigger for app 1236702 is disabled"
  else
    echo "  [WARN] check-suite preferences could not be read back (got: ${setting:-unreadable})"
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

# The PATCH response echoes the resulting preferences object. Capture it so we
# can read back and confirm the auto-trigger setting was applied — this is the
# same state the compliance audit reports as `check-suite-prefs-unreadable`
# when its token cannot read the preferences.
CS_RESPONSE_FILE="$(mktemp)"
trap 'rm -f "$CS_RESPONSE_FILE"' EXIT

if gh api -X PATCH "repos/$REPO/check-suites/preferences" \
  --input - >"$CS_RESPONSE_FILE" 2>/dev/null <<'JSON'; then
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
  verify_check_suite_pref "$CS_RESPONSE_FILE"
else
  echo "  [WARN] check-suite preferences require a fine-grained PAT (Administration: write + Checks: write) or GitHub App token."
  echo "         Re-run with: GH_PAT=<fine-grained-pat> bash scripts/apply-repo-settings.sh"
  exit 1
fi

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

readonly EXPECTED_APPROVAL_POLICY="first_time_contributors_new_to_github"

echo "Setting fork-PR contributor approval policy..."

gh api -X PUT "repos/$REPO/actions/permissions/fork-pr-contributor-approval" --input - <<JSON
{
  "approval_policy": "${EXPECTED_APPROVAL_POLICY}"
}
JSON

POLICY="$(gh api "repos/$REPO/actions/permissions/fork-pr-contributor-approval" \
  --jq '.approval_policy')" || {
  echo "Failed to read fork-PR contributor approval policy" >&2
  exit 1
}
if [[ "$POLICY" == "$EXPECTED_APPROVAL_POLICY" ]]; then
  echo "  [OK] approval_policy: $POLICY"
else
  echo "  [ERROR] approval_policy: $POLICY (expected: $EXPECTED_APPROVAL_POLICY)" >&2
  exit 1
fi

echo "Done."
