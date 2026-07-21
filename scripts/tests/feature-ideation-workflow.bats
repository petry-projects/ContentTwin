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
wf = yaml.safe_load(open(sys.argv[1]))
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
wf = yaml.safe_load(open(sys.argv[1]))
job = wf['jobs']['redispatch']
assert job.get('permissions') == {}, f'redispatch permissions must be {{}}, got: {job.get(\"permissions\")!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "prep input-resolution job declares empty permissions" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
job = wf['jobs']['prep']
assert job.get('permissions') == {}, f'prep permissions must be {{}}, got: {job.get(\"permissions\")!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "ideate job permissions match the canonical grant set" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
perms = wf['jobs']['ideate'].get('permissions')
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
wf = yaml.safe_load(open(sys.argv[1]))
uses = wf['jobs']['ideate'].get('uses', '')
expected = 'petry-projects/.github/.github/workflows/feature-ideation-reusable.yml@'
assert uses.startswith(expected), f'ideate must call the org reusable workflow, got: {uses!r}'
print(uses)
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == petry-projects/.github/.github/workflows/feature-ideation-reusable.yml@* ]]
}
