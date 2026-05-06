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
# Required status checks for the default branch before any commit can be merged.
# Mirrors the org standard:
#   standards/github-settings.md#code-quality--required-checks-ruleset-all-repositories
#
# NOTE: claude-code / claude is intentionally NOT included. claude-code-action's
# GitHub App refuses to mint a token for PRs that touch workflow files, which
# would deadlock every workflow-modifying PR. The Claude review check still runs
# on all PRs for feedback, but must not be a merge gate.
# See: petry-projects/.github:scripts/apply-rulesets.sh

RULESET_NAME="code-quality"

EXISTING_ID=$(gh api "repos/$REPO/rulesets" \
  --jq ".[] | select(.name == \"$RULESET_NAME\") | .id" 2>/dev/null || true)

# Context strings must match exactly what GitHub reports for each check run.
# To audit the current context names on any commit:
#   gh api repos/$REPO/commits/$(git rev-parse HEAD)/check-runs --jq '[.check_runs[].name] | unique'
#
# Contexts used here:
#   SonarCloud                       – SonarCloud quality gate
#   Analyze (actions)                – CodeQL security analysis (github/codeql-action)
#   Lint                             – ESLint / code style
#   Format                           – Prettier / formatting
#   agent-shield / AgentShield       – AgentShield AI security check
#   dependency-audit / Detect ecosystems – Dependency vulnerability audit

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
          { "context": "Analyze (actions)" },
          { "context": "Lint" },
          { "context": "Format" },
          { "context": "agent-shield / AgentShield" },
          { "context": "dependency-audit / Detect ecosystems" }
        ],
        "strict_required_status_checks_policy": true,
        "do_not_enforce_on_create": false
      }
    }
  ],
  "bypass_actors": []
}'

if [ -n "$EXISTING_ID" ]; then
  echo "  Updating existing '$RULESET_NAME' ruleset (id: $EXISTING_ID)..."
  echo "$PAYLOAD" | gh api "repos/$REPO/rulesets/$EXISTING_ID" -X PUT --input -
else
  echo "  Creating '$RULESET_NAME' ruleset..."
  echo "$PAYLOAD" | gh api "repos/$REPO/rulesets" -X POST --input -
fi

echo "Done. Ruleset '$RULESET_NAME' is active."
