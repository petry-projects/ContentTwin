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
# NOTE: "claude-code / claude" is intentionally excluded from required checks.
# claude-code-action refuses to mint a token for PRs that touch workflow files,
# which would deadlock every workflow-modifying PR. The check still runs for
# review feedback on normal PRs but must not be a merge gate.
# See: https://github.com/petry-projects/ContentTwin/issues/81

if [[ -n "$EXISTING_ID" ]]; then
  echo "  Updating existing '$RULESET_NAME' ruleset (id: $EXISTING_ID)..."
  printf '%s\n' "$PAYLOAD" | gh api "repos/$REPO/rulesets/$EXISTING_ID" -X PUT --input -
else
  echo "  Creating '$RULESET_NAME' ruleset..."
  printf '%s\n' "$PAYLOAD" | gh api "repos/$REPO/rulesets" -X POST --input -
fi

echo "Done. Ruleset '$RULESET_NAME' is active."

# ── pr-quality ───────────────────────────────────────────────────────────────
# Pull-request review requirements for the default branch. Mirrors the codified
# org source of truth so `setup-rulesets.sh` converges this repo's live ruleset:
#   petry-projects/.github:standards/rulesets/pr-quality.json
#   standards/github-settings.md#pr-quality--standard-ruleset-all-repositories
#
# dismiss_stale_reviews_on_push MUST be true: it re-requests review after any
# push so approvals cannot be inherited by unreviewed code (compliance: #339).
#
# require_last_push_approval MUST be true: it forces the most recent push to be
# approved by someone other than its author, so a PR cannot be self-approved
# after new commits are added (compliance: #340).
#
# Bypass actors match every ruleset targeting main (see the bypass-actors
# standard): OrganizationAdmin plus the dependabot-automerge-petry GitHub App
# (Integration actor_id 3167543) whose rebase workflow re-approves updated PRs.

PR_QUALITY_NAME="pr-quality"

PR_QUALITY_EXISTING_ID=$(gh api "repos/$REPO/rulesets" \
  --jq ".[] | select(.name == \"$PR_QUALITY_NAME\") | .id" 2>/dev/null || true)

PR_QUALITY_PAYLOAD='{
  "name": "pr-quality",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [
    { "actor_type": "OrganizationAdmin", "bypass_mode": "always" },
    { "actor_id": 3167543, "actor_type": "Integration", "bypass_mode": "always" }
  ],
  "conditions": {
    "ref_name": {
      "include": ["~DEFAULT_BRANCH"],
      "exclude": []
    }
  },
  "rules": [
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 1,
        "require_code_owner_review": true,
        "required_review_thread_resolution": true,
        "dismiss_stale_reviews_on_push": true,
        "require_last_push_approval": true,
        "allowed_merge_methods": ["squash"]
      }
    }
  ]
}'

if [[ -n "$PR_QUALITY_EXISTING_ID" ]]; then
  echo "  Updating existing '$PR_QUALITY_NAME' ruleset (id: $PR_QUALITY_EXISTING_ID)..."
  printf '%s\n' "$PR_QUALITY_PAYLOAD" | gh api "repos/$REPO/rulesets/$PR_QUALITY_EXISTING_ID" -X PUT --input -
else
  echo "  Creating '$PR_QUALITY_NAME' ruleset..."
  printf '%s\n' "$PR_QUALITY_PAYLOAD" | gh api "repos/$REPO/rulesets" -X POST --input -
fi

echo "Done. Ruleset '$PR_QUALITY_NAME' is active."

# ── dependabot security updates ──────────────────────────────────────────────
# Enables Dependabot security updates so GitHub automatically opens PRs to
# fix known vulnerabilities in dependencies.
# Standard: https://github.com/petry-projects/.github/blob/main/standards/push-protection.md#required-repo-level-settings

echo "Enabling Dependabot security updates for: $REPO"

gh api "repos/$REPO" -X PATCH \
  --field 'security_and_analysis[dependabot_security_updates][status]=enabled'

echo "Done. Dependabot security updates enabled."
