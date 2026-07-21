#!/usr/bin/env bats
# Tests for .github/workflows/feature-ideation.yml
# Guards the centrally-owned surface of the thin caller stub
# (standard: ci-standards.md#8-feature-ideation-feature-ideationyml--bmad-method-repos).
# The `permissions:` grants are owned by the org template and are NOT
# repo-adjustable; these tests fail if that surface drifts from canonical.

WORKFLOW=".github/workflows/feature-ideation.yml"

setup() {
  if ! python3 -c "import yaml" &>/dev/null; then
    echo "Error: Python 'yaml' (PyYAML) module is required to run these tests." >&2
    return 1
  fi
}

@test "feature-ideation workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "feature-ideation workflow is valid YAML" {
  run python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "top-level permissions are empty (default-deny)" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
perms = wf.get('permissions')
assert perms == {}, f'top-level permissions must be {{}} (default-deny), got: {perms!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "redispatch bridge job declares empty permissions" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
job = (wf.get('jobs') or {}).get('redispatch') or {}
perms = job.get('permissions')
assert perms == {}, f'redispatch permissions must be {{}}, got: {perms!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "prep input-resolution job declares empty permissions" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
job = (wf.get('jobs') or {}).get('prep') or {}
perms = job.get('permissions')
assert perms == {}, f'prep permissions must be {{}}, got: {perms!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "ideate job permissions match the canonical grant set" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
job = (wf.get('jobs') or {}).get('ideate') or {}
perms = job.get('permissions')
expected = {
    'contents': 'read',
    'issues': 'read',
    'pull-requests': 'read',
    'discussions': 'write',
    'id-token': 'write',
    'actions': 'read',
}
assert perms == expected, f'ideate permissions drifted from canonical.\nexpected: {expected}\ngot:      {perms}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "uses: reusable pinned line calls the org reusable on the stable channel" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
job = (wf.get('jobs') or {}).get('ideate') or {}
uses = job.get('uses', '')
expected = 'petry-projects/.github/.github/workflows/feature-ideation-reusable.yml@feature-ideation/stable'
assert uses == expected, f'ideate must call the org reusable workflow on the stable channel, got: {uses!r}'
print(uses)
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == petry-projects/.github/.github/workflows/feature-ideation-reusable.yml@feature-ideation/stable ]]
}
