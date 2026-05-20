#!/usr/bin/env bash
# apply-repo-settings.sh — Apply required GitHub repository security settings.
#
# Usage:
#   gh auth login        # if not already authenticated with admin access
#   bash scripts/apply-repo-settings.sh
#
# Requires: gh CLI with repository administration permissions
# Standard: https://github.com/petry-projects/.github/blob/main/standards/push-protection.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/push-protection.sh
source "${SCRIPT_DIR}/lib/push-protection.sh"

REPO="${GITHUB_REPOSITORY:-petry-projects/ContentTwin}"

echo "Applying repository settings for: ${REPO}"

pp_apply_security_and_analysis "${REPO}"

echo "Done. All required security_and_analysis settings applied to ${REPO}."
