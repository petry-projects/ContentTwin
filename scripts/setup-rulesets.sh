#!/usr/bin/env bash
# setup-rulesets.sh — Create required GitHub repository rulesets
#
# Usage:
#   gh auth login        # if not already authenticated with admin access
#   bash scripts/setup-rulesets.sh
#
# Requires: gh CLI with repository administration permissions
# Standard: https://github.com/petry-projects/.github/blob/main/standards/github-settings.md
set -euo pipefail

REPO="${GITHUB_REPOSITORY:-petry-projects/ContentTwin}"

echo "Applying rulesets for: $REPO"

# ── code-quality ─────────────────────────────────────────────────────────────
# Requires the SonarCloud quality gate to pass on the default branch before
# any commit can be merged.  Mirrors the org standard:
#   standards/github-settings.md#code-quality--required-checks-ruleset-all-repositories
#
# Status check context format for GitHub Actions: "<workflow_name> / <job_name>"
# (with matrix values appended in parentheses).  Non-Actions checks use the
# bare external status context name (e.g. "SonarCloud").
#
# strict_required_status_checks_policy=true: all branches must be up-to-date
# with the base branch before merging.  This is intentional hardening that goes
# slightly beyond the scope of issue #81 but aligns with the org standard.

RULESET_NAME="code-quality"

EXISTING_ID=$(gh api "repos/$REPO/rulesets" \
  --jq ".[] | select(.name == \"$RULESET_NAME\") | .id" 2>/dev/null || true)

PAYLOAD='{
  "name": "code-quality",
  "target": "branch",
  "enforcement": "active",
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "required_status_checks",
      "parameters": {
        "required_status_checks": [
          { "context": "SonarCloud" },
          { "context": "CodeQL / Analyze (actions)" },
          { "context": "CI / Lint" },
          { "context": "CI / Format" }
        ],
        "strict_required_status_checks_policy": true,
        "do_not_enforce_on_create": false
      }
    }
  ]
}'

if [ -n "$EXISTING_ID" ]; then
  echo "  Updating existing '$RULESET_NAME' ruleset (id: $EXISTING_ID)..."
  # Log live contexts before overwriting to surface any drift between
  # the in-repo payload and the live ruleset configuration.
  gh api "repos/$REPO/rulesets/$EXISTING_ID" \
    --jq '"  Live contexts: " + ([.rules[].parameters.required_status_checks[].context] | join(", "))' \
    2>/dev/null || true
  echo "$PAYLOAD" | gh api "repos/$REPO/rulesets/$EXISTING_ID" -X PUT --input -
else
  echo "  Creating '$RULESET_NAME' ruleset..."
  echo "$PAYLOAD" | gh api "repos/$REPO/rulesets" -X POST --input -
fi

echo "Done. Ruleset '$RULESET_NAME' is active."
