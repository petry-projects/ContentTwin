#!/usr/bin/env bats
# Tests for .github/workflows/auto-rebase.yml
# Guards the centralization standard (issue #284): the caller stub must delegate
# to the org reusable workflow pinned to a full commit SHA,
# per standards/ci-standards.md#centralization-tiers.

WORKFLOW=".github/workflows/auto-rebase.yml"

@test "auto-rebase workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "auto-rebase workflow is valid YAML" {
  run python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1], encoding='utf-8'))" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "auto-rebase delegates to the org reusable workflow" {
  run python3 -c "
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
    wf = yaml.safe_load(f)
job = wf['jobs']['auto-rebase']
uses = job.get('uses', '')
expected = 'petry-projects/.github/.github/workflows/auto-rebase-reusable.yml@'
assert uses.startswith(expected), f'job must call the org reusable workflow, got: {uses!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "auto-rebase reusable is pinned to a commit SHA" {
  run python3 -c "
import sys, yaml, re
with open(sys.argv[1], encoding='utf-8') as f:
    wf = yaml.safe_load(f)
uses = wf['jobs']['auto-rebase'].get('uses', '')
ref = uses.split('@', 1)[1] if '@' in uses else ''
assert re.match(r'^[a-f0-9]{40}$', ref), f'reusable must be pinned to a commit SHA, got: {ref!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}
