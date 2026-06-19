#!/usr/bin/env bats
# Tests for .github/workflows/auto-rebase.yml
# Guards the centralization standard (issue #284): the caller stub must delegate
# to the org reusable workflow pinned to the canonical `@v1` ref, not a raw SHA,
# per standards/ci-standards.md#centralization-tiers.

WORKFLOW=".github/workflows/auto-rebase.yml"

setup() {
  if ! python3 -c "import yaml" &>/dev/null; then
    echo "Error: Python 'yaml' (PyYAML) module is required to run these tests." >&2
    return 1
  fi
}

@test "auto-rebase workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "auto-rebase workflow is valid YAML" {
  run python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "auto-rebase delegates to the org reusable workflow" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
job = wf['jobs']['auto-rebase']
uses = job.get('uses', '')
expected = 'petry-projects/.github/.github/workflows/auto-rebase-reusable.yml@'
assert uses.startswith(expected), f'job must call the org reusable workflow, got: {uses!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "auto-rebase reusable is pinned to the canonical @v1 ref" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
uses = wf['jobs']['auto-rebase'].get('uses', '')
ref = uses.split('@', 1)[1] if '@' in uses else ''
assert ref == 'v1', f'reusable must be pinned to @v1, got: {ref!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}
