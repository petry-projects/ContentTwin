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

# ── check-suite auto-trigger ──────────────────────────────────────────────────
# Claude (app_id: 1236702) and CodeRabbit must have auto_trigger_checks disabled.
# When enabled, GitHub creates a queued check suite on every push that is never
# completed, permanently blocking auto-merge.
# Standard: github-settings.md § "GitHub Apps & Integrations"

echo "  Disabling check-suite auto-trigger for Claude (app_id: 1236702)..."
echo '{"auto_trigger_checks":[{"app_id":1236702,"setting":false}]}' \
  | gh api "repos/$REPO/check-suites/preferences" -X PATCH --input -

echo "Done. Check-suite auto-trigger disabled for Claude on $REPO."
