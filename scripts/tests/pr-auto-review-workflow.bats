#!/usr/bin/env bats
# Tests for .github/workflows/pr-auto-review.yml
# This caller stub is a thin wrapper around the org reusable workflow. Its
# `on:` triggers, `permissions:` grants, and `concurrency:` surface are owned
# centrally by standards/workflows/pr-auto-review.yml and are not repo-adjustable
# (compliance check `stub-surface-drift-pr-auto-review.yml-concurrency`, #348).
# The canonical stub declares NO top-level `concurrency:` block, so this repo's
# stub must not declare one either — the local #274 block was drift and has been
# re-synced away.

WORKFLOW=".github/workflows/pr-auto-review.yml"

setup() {
  if ! python3 -c "import yaml" &>/dev/null; then
    echo "Error: Python 'yaml' (PyYAML) module is required to run these tests." >&2
    return 1
  fi
}

@test "pr-auto-review workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "pr-auto-review workflow is valid YAML" {
  run python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1])) or {}" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "pr-auto-review stub declares no top-level concurrency block (centrally owned)" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
assert 'concurrency' not in wf, 'caller stub must not declare its own concurrency; it is owned centrally in standards/workflows/pr-auto-review.yml'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "pr-auto-review still delegates to the org reusable workflow" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
job = wf['jobs']['pr-auto-review']
uses = job.get('uses', '')
expected = 'petry-projects/.github/.github/workflows/pr-auto-review-reusable.yml@'
assert uses.startswith(expected), f'job must call the org reusable workflow, got: {uses!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}
