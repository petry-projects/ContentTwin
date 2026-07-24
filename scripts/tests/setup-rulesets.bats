#!/usr/bin/env bats
# Tests for scripts/setup-rulesets.sh
# Verifies the sanctioned rulesets are codified in-repo so `setup-rulesets.sh`
# converges each repo's live ruleset to the org standard. In particular the
# `pr-quality` ruleset must set `dismiss_stale_reviews_on_push: true` and
# `require_last_push_approval: true`, matching the codified source of truth
# standards/rulesets/pr-quality.json (compliance: issue #339, drift finding
# ruleset-drift-pr-quality-dismiss_stale_reviews_on_push; issue #340, drift
# finding ruleset-drift-pr-quality-require_last_push_approval).

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

  # Mock gh: capture every JSON body sent via `--input -` to a unique file so
  # multiple ruleset payloads (code-quality + pr-quality) don't clobber each
  # other, and return an empty body for the ruleset-existence lookup so the
  # script takes the create (POST) path.
  cat > "$MOCK_BIN/gh" << 'MOCK'
#!/usr/bin/env bash
set -euo pipefail
echo "$*" >> "$CALLS_FILE"

if [[ " $* " == *" --input - "* ]]; then
  payload_file="$(mktemp "$PAYLOAD_DIR/payload.XXXXXX")"
  cat > "$payload_file"
  echo '{}'
elif [[ "$*" == *--jq* ]]; then
  # Ruleset lookup (`.[] | select(.name==...) | .id`) — emit nothing so
  # EXISTING_ID is empty and the script creates the ruleset.
  printf ''
else
  echo '{}'
fi
MOCK
  chmod +x "$MOCK_BIN/gh"

  export PATH="$MOCK_BIN:$PATH"
  export GITHUB_REPOSITORY="test-owner/test-repo"
}

# Locate the captured payload whose ruleset name matches the given argument.
pr_quality_payload() {
  grep -rl '"pr-quality"' "$PAYLOAD_DIR" 2>/dev/null | head -n 1
}

# ── Execution tests ───────────────────────────────────────────────────────────

@test "script exits 0 with mocked gh" {
  run bash "$BATS_TEST_DIRNAME/../setup-rulesets.sh"
  [ "$status" -eq 0 ]
}

@test "script applies a pr-quality ruleset" {
  run bash "$BATS_TEST_DIRNAME/../setup-rulesets.sh"
  [ "$status" -eq 0 ]
  payload_file="$(pr_quality_payload)"
  [ -n "$payload_file" ] || {
    echo "No payload file captured for the pr-quality ruleset"
    return 1
  }
}

# ── Drifted-parameter test (the finding in issue #339) ─────────────────────────

@test "pr-quality payload sets dismiss_stale_reviews_on_push to true" {
  run bash "$BATS_TEST_DIRNAME/../setup-rulesets.sh"
  [ "$status" -eq 0 ]

  payload_file="$(pr_quality_payload)"
  [ -n "$payload_file" ] || {
    echo "No payload file captured for the pr-quality ruleset"
    return 1
  }

  run python3 - "$payload_file" << 'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
pr_rule = next(r for r in d["rules"] if r["type"] == "pull_request")
val = pr_rule["parameters"]["dismiss_stale_reviews_on_push"]
assert val is True, f"expected dismiss_stale_reviews_on_push true, got {val!r}"
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

# ── Drifted-parameter test (the finding in issue #340) ─────────────────────────

@test "pr-quality payload sets require_last_push_approval to true" {
  run bash "$BATS_TEST_DIRNAME/../setup-rulesets.sh"
  [ "$status" -eq 0 ]

  payload_file="$(pr_quality_payload)"
  [ -n "$payload_file" ] || {
    echo "No payload file captured for the pr-quality ruleset"
    return 1
  }

  run python3 - "$payload_file" << 'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
pr_rule = next(r for r in d["rules"] if r["type"] == "pull_request")
val = pr_rule["parameters"]["require_last_push_approval"]
assert val is True, f"expected require_last_push_approval true, got {val!r}"
print("ok")
PY
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

# ── Full codified-parameter coverage ──────────────────────────────────────────

@test "pr-quality payload matches all codified pull_request parameters" {
  run bash "$BATS_TEST_DIRNAME/../setup-rulesets.sh"
  [ "$status" -eq 0 ]

  payload_file="$(pr_quality_payload)"
  [ -n "$payload_file" ]

  run python3 - "$payload_file" << 'PY'
import json, sys
with open(sys.argv[1]) as f:
    d = json.load(f)
assert d["name"] == "pr-quality", d.get("name")
assert d["target"] == "branch", d.get("target")
assert d["enforcement"] == "active", d.get("enforcement")
pr_rule = next(r for r in d["rules"] if r["type"] == "pull_request")
p = pr_rule["parameters"]
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
