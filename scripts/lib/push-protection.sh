#!/usr/bin/env bash
# Library: push-protection settings helpers.
# Standard: https://github.com/petry-projects/.github/blob/main/standards/push-protection.md#required-repo-level-settings
#
# Sourced by scripts/apply-repo-settings.sh and scripts/compliance-audit.sh.
# Adding a required flag here propagates to both the apply and audit scripts.

# All security_and_analysis settings required on every repo, as "key:value" pairs.
PP_REQUIRED_SA_SETTINGS=(
  "secret_scanning:enabled"
  "secret_scanning_push_protection:enabled"
  "secret_scanning_ai_detection:enabled"
  "secret_scanning_non_provider_patterns:enabled"
  "dependabot_security_updates:enabled"
)

# Apply all PP_REQUIRED_SA_SETTINGS to a repository via the GitHub API.
# Arguments:
#   $1 — owner/repo slug (e.g. petry-projects/ContentTwin)
pp_apply_security_and_analysis() {
  local repo="${1:?repo argument required (owner/repo)}"
  local payload='{"security_and_analysis":{'
  local sep=''
  for entry in "${PP_REQUIRED_SA_SETTINGS[@]}"; do
    local key="${entry%%:*}"
    local val="${entry##*:}"
    payload+="${sep}\"${key}\":{\"status\":\"${val}\"}"
    sep=','
  done
  payload+='}}'
  echo "  Applying security_and_analysis settings to ${repo}..."
  echo "${payload}" | gh api -X PATCH "repos/${repo}" --input -
}
