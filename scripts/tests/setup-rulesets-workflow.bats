#!/usr/bin/env bats
# Tests for scripts/setup-rulesets.sh
# Verifies the pr-quality ruleset payload codifies require_last_push_approval=true
# and the rest of the pull_request rule (compliance: issue #340), matching the
# org source-of-truth standards/rulesets/pr-quality.json.

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

  # Mock gh:
  #   * ruleset-lookup calls (--jq over repos/*/rulesets) return empty so the
  #     script takes the create (POST) path.
  #   * any request reading a body from stdin (--input -) is captured to a
  #     uniquely numbered file so multiple ruleset payloads don't clobber each
  #     other (code-quality and pr-quality POST to the same URL).
  cat > "$MOCK_BIN/gh" << 'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$CALLS_FILE"

if [[ " $* " == *" --input - "* ]]; then
  seq_file="$PAYLOAD_DIR/.seq"
  n=$(( $(cat "$seq_file" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$seq_file"
  cat > "$PAYLOAD_DIR/payload_${n}.json"
  echo '{}'
elif [[ "$*" == *rulesets* && "$*" == *--jq* ]]; then
  # No existing ruleset -> empty id -> script creates via POST.
  printf ''
else
  echo '{}'
fi
MOCK
  chmod +x "$MOCK_BIN/gh"

  export PATH="$MOCK_BIN:$PATH"
  export GITHUB_REPOSITORY="test-owner/test-repo"
}

# Locate the captured payload file whose JSON contains a rule of the given name.
pr_quality_payload() {
  grep -rl '"pr-quality"' "$PAYLOAD_DIR" 2>/dev/null | head -1
}

# ── Execution tests ───────────────────────────────────────────────────────────

@test "script exits 0 with mocked gh" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "script creates a pr-quality ruleset" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]
  payload_file="$(pr_quality_payload)"
  [ -n "$payload_file" ] || {
    echo "No captured payload contained the pr-quality ruleset"
    return 1
  }
}

# ── Payload content tests (compliance: issue #340) ────────────────────────────

@test "pr-quality payload sets require_last_push_approval to true" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  payload_file="$(pr_quality_payload)"
  [ -n "$payload_file" ] || {
    echo "No captured payload contained the pr-quality ruleset"
    return 1
  }

  run python3 - "$payload_file" << 'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
rule = next((r for r in d.get("rules", []) if r.get("type") == "pull_request"), None)
assert rule is not None, "No pull_request rule found in ruleset"
parameters = rule.get("parameters") or {}
val = parameters.get("require_last_push_approval")
assert val is True, f"expected require_last_push_approval true, got {val!r}"
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "pr-quality payload targets the default branch" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  payload_file="$(pr_quality_payload)"
  [ -n "$payload_file" ]

  run python3 - "$payload_file" << 'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
assert d.get("target") == "branch", f"expected target 'branch', got {d.get('target')!r}"
assert d.get("enforcement") == "active", f"expected enforcement 'active', got {d.get('enforcement')!r}"
includes = ((d.get("conditions") or {}).get("ref_name") or {}).get("include")
assert includes == ["~DEFAULT_BRANCH"], f"expected include ['~DEFAULT_BRANCH'], got {includes!r}"
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "pr-quality payload codifies the required pull_request parameters" {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ]

  payload_file="$(pr_quality_payload)"
  [ -n "$payload_file" ]

  run python3 - "$payload_file" << 'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
rule = next((r for r in d.get("rules", []) if r.get("type") == "pull_request"), None)
assert rule is not None, "No pull_request rule found in ruleset"
p = rule.get("parameters") or {}
expected = {
    "required_approving_review_count": 1,
    "require_code_owner_review": True,
    "required_review_thread_resolution": True,
    "dismiss_stale_reviews_on_push": True,
    "require_last_push_approval": True,
    "allowed_merge_methods": ["squash"],
}
for k, v in expected.items():
    assert p.get(k) == v, f"{k}: expected {v!r}, got {p.get(k)!r}"
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}
