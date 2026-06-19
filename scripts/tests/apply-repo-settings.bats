#!/usr/bin/env bats
# Tests for scripts/apply-repo-settings.sh
# Verifies the GitHub API payload includes all required security settings,
# including secret_scanning_non_provider_patterns (compliance: issue #204).

SCRIPT="scripts/apply-repo-settings.sh"

setup() {
  MOCK_BIN="$BATS_TMPDIR/bin"
  mkdir -p "$MOCK_BIN"

  CALLS_FILE="$BATS_TMPDIR/calls"
  rm -f "$CALLS_FILE"
  PAYLOAD_DIR="$BATS_TMPDIR/payloads"
  rm -rf "$PAYLOAD_DIR"
  mkdir -p "$PAYLOAD_DIR"
  export CALLS_FILE PAYLOAD_DIR

  cat > "$MOCK_BIN/gh" << 'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$CALLS_FILE"

# Capture JSON body for PATCH requests that read from stdin (--input -)
if [[ " $* " == *" --input - "* ]]; then
  # Derive a safe filename from the URL argument (first repos/* path in argv)
  url_arg=""
  for arg in "$@"; do
    if [[ "$arg" == repos/* ]]; then
      url_arg="$arg"
      break
    fi
  done
  url_slug=$(printf '%s' "$url_arg" | tr -cs 'a-zA-Z0-9_-' '_' | head -c 60)
  cat > "$PAYLOAD_DIR/${url_slug}.json"
  if [[ "$url_arg" == *check-suites/preferences* ]]; then
    # Echo the applied preferences the way the real check-suites/preferences
    # PATCH endpoint does, so the script can read back and verify them.
    printf '{"preferences":{"auto_trigger_checks":[{"app_id":1236702,"setting":false}]},"repository":{"id":1,"name":"test-repo"}}'
  else
    echo '{}'
  fi
elif [[ "$*" == *--jq* && "$*" == *security_and_analysis* ]]; then
  printf '{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"},"secret_scanning_non_provider_patterns":{"status":"enabled"},"secret_scanning_ai_detection":{"status":"enabled"},"dependabot_security_updates":{"status":"enabled"}}'
elif [[ "$*" == *fork-pr-contributor-approval* ]]; then
  printf 'first_time_contributors_new_to_github\n'
else
  echo '{}'
fi
MOCK
  chmod +x "$MOCK_BIN/gh"

  export PATH="$MOCK_BIN:$PATH"
  export GITHUB_REPOSITORY="test-owner/test-repo"
}

# ── Execution tests ───────────────────────────────────────────────────────────

@test "script exits 0 with mocked gh" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script calls gh api PATCH for security_and_analysis" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  grep -q -- "-X PATCH" "$CALLS_FILE"
}

# ── Payload content tests ─────────────────────────────────────────────────────

@test "PATCH payload enables secret_scanning_non_provider_patterns" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  # Find the captured payload file for the security_and_analysis PATCH
  payload_file=$(grep -rl '"secret_scanning_non_provider_patterns"' "$PAYLOAD_DIR" 2>/dev/null | head -1)
  [ -n "$payload_file" ] || {
    echo "No payload file captured containing secret_scanning_non_provider_patterns"
    return 1
  }

  run python3 - "$payload_file" << 'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
status = d["security_and_analysis"]["secret_scanning_non_provider_patterns"]["status"]
assert status == "enabled", f"expected 'enabled', got '{status}'"
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "PATCH payload enables secret_scanning" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  payload_file=$(grep -rl '"secret_scanning"' "$PAYLOAD_DIR" 2>/dev/null | head -1)
  [ -n "$payload_file" ]

  run python3 - "$payload_file" << 'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
status = d["security_and_analysis"]["secret_scanning"]["status"]
assert status == "enabled", f"expected 'enabled', got '{status}'"
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "PATCH payload enables secret_scanning_push_protection" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  payload_file=$(grep -rl '"secret_scanning_push_protection"' "$PAYLOAD_DIR" 2>/dev/null | head -1)
  [ -n "$payload_file" ]

  run python3 - "$payload_file" << 'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
status = d["security_and_analysis"]["secret_scanning_push_protection"]["status"]
assert status == "enabled", f"expected 'enabled', got '{status}'"
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "PATCH payload enables secret_scanning_ai_detection" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  payload_file=$(grep -rl '"secret_scanning_ai_detection"' "$PAYLOAD_DIR" 2>/dev/null | head -1)
  [ -n "$payload_file" ]

  run python3 - "$payload_file" << 'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
status = d["security_and_analysis"]["secret_scanning_ai_detection"]["status"]
assert status == "enabled", f"expected 'enabled', got '{status}'"
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

# ── Verification output tests ─────────────────────────────────────────────────

@test "script reports verification result for secret_scanning_non_provider_patterns" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"secret_scanning_non_provider_patterns"* ]]
}

# ── Check-suite preferences tests (compliance: issue #286) ────────────────────

@test "check-suite PATCH payload disables auto-trigger for Claude app 1236702" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  payload_file=$(grep -rl '"auto_trigger_checks"' "$PAYLOAD_DIR" 2>/dev/null | head -1)
  [ -n "$payload_file" ] || {
    echo "No payload file captured containing auto_trigger_checks"
    return 1
  }

  run python3 - "$payload_file" << 'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
checks = {c["app_id"]: c["setting"] for c in d["auto_trigger_checks"]}
assert checks.get(1236702) is False, f"expected app 1236702 disabled, got {checks}"
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "script reads back and reports check-suite preferences as readable" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"check-suite preferences readable"* ]]
}

@test "script warns when check-suite preferences cannot be read back" {
  # Override the mock so the check-suites PATCH returns an empty body,
  # simulating the unreadable-preferences condition from the finding.
  cat > "$MOCK_BIN/gh" << 'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$CALLS_FILE"
if [[ " $* " == *" --input - "* ]]; then
  cat >/dev/null
  echo '{}'
elif [[ "$*" == *--jq* && "$*" == *security_and_analysis* ]]; then
  printf '{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"},"secret_scanning_non_provider_patterns":{"status":"enabled"},"secret_scanning_ai_detection":{"status":"enabled"},"dependabot_security_updates":{"status":"enabled"}}'
else
  echo '{}'
fi
MOCK
  chmod +x "$MOCK_BIN/gh"

  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"check-suite preferences could not be read back"* ]]
}
