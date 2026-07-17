#!/usr/bin/env bats
# Tests for scripts/setup-rulesets.sh
# Verifies the script applies both required org rulesets and that the pr-quality
# ruleset payload sets require_code_owner_review=true, the parameter that drifted
# to false (compliance: issue #338). The codified source of truth is
# petry-projects/.github:standards/rulesets/pr-quality.json.

SCRIPT="scripts/setup-rulesets.sh"

setup() {
  MOCK_BIN="$BATS_TMPDIR/bin"
  mkdir -p "$MOCK_BIN"

  CALLS_FILE="$BATS_TMPDIR/calls"
  rm -f "$CALLS_FILE"
  PAYLOAD_DIR="$BATS_TMPDIR/payloads"
  rm -rf "$PAYLOAD_DIR"
  mkdir -p "$PAYLOAD_DIR"
  export CALLS_FILE PAYLOAD_DIR

  # Mock gh: record every invocation, capture each --input - body to its own file
  # (both rulesets POST to the same URL, so a URL-derived name would collide), and
  # return an empty id for the ruleset lookup so the script takes the create path.
  cat > "$MOCK_BIN/gh" << 'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$CALLS_FILE"

if [[ " $* " == *" --input - "* ]]; then
  body_file="$(mktemp "$PAYLOAD_DIR/payload.XXXXXX.json")"
  cat > "$body_file"
  echo '{}'
elif [[ "$*" == *"--jq"* ]]; then
  # Ruleset id lookup: report no existing ruleset.
  printf ''
else
  echo '{}'
fi
MOCK
  chmod +x "$MOCK_BIN/gh"

  export PATH="$MOCK_BIN:$PATH"
  export GITHUB_REPOSITORY="test-owner/test-repo"
}

# pr_quality_payload — echo the path of the captured pr-quality ruleset payload.
pr_quality_payload() {
  grep -rl '"pr-quality"' "$PAYLOAD_DIR" 2>/dev/null | head -1
}

# ── Execution tests ───────────────────────────────────────────────────────────

@test "script exits 0 with mocked gh" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script still applies the code-quality ruleset" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  payload_file=$(grep -rl '"code-quality"' "$PAYLOAD_DIR" 2>/dev/null | head -1)
  [ -n "$payload_file" ]
}

# ── pr-quality ruleset (compliance: issue #338) ───────────────────────────────

@test "script applies a pr-quality ruleset" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  payload_file=$(pr_quality_payload)
  [ -n "$payload_file" ] || {
    echo "No captured payload contained the pr-quality ruleset"
    return 1
  }
}

@test "pr-quality payload sets require_code_owner_review to true" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  payload_file=$(pr_quality_payload)
  [ -n "$payload_file" ] || {
    echo "No captured payload contained the pr-quality ruleset"
    return 1
  }

  run python3 - "$payload_file" << 'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
rule = next(r for r in d["rules"] if r["type"] == "pull_request")
val = rule["parameters"]["require_code_owner_review"]
assert val is True, f"expected require_code_owner_review true, got {val!r}"
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "pr-quality payload matches the codified standard parameters" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  payload_file=$(pr_quality_payload)
  [ -n "$payload_file" ]

  run python3 - "$payload_file" << 'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
assert d["name"] == "pr-quality", d["name"]
assert d["target"] == "branch", d["target"]
assert d["enforcement"] == "active", d["enforcement"]
assert d["conditions"]["ref_name"]["include"] == ["~DEFAULT_BRANCH"], d["conditions"]
rule = next(r for r in d["rules"] if r["type"] == "pull_request")
p = rule["parameters"]
assert p["required_approving_review_count"] == 1, p
assert p["require_code_owner_review"] is True, p
assert p["required_review_thread_resolution"] is True, p
assert p["dismiss_stale_reviews_on_push"] is True, p
assert p["require_last_push_approval"] is True, p
assert p["allowed_merge_methods"] == ["squash"], p
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}
