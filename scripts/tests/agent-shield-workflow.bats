#!/usr/bin/env bats
# Tests for .github/workflows/agent-shield.yml
# Regression guard for the centrally owned invariants of this thin caller stub.

WORKFLOW=".github/workflows/agent-shield.yml"

setup() {
  # Verify PyYAML is installed; required to parse and validate YAML workflow files.
  if ! python3 -c "import yaml" &>/dev/null; then
    echo "Error: Python 'yaml' (PyYAML) module is required to run these tests." >&2
    return 1
  fi
}

@test "trigger: on: surface is exactly push, pull_request, merge_group" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
on = wf.get('on') or wf.get(True) or {}
assert set(on) == {'push', 'pull_request', 'merge_group'}, sorted(on)
assert on['push']['branches'] == ['main']
assert on['pull_request']['branches'] == ['main']
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "permissions: workflow-level contents read only" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
on = wf.get('on') or wf.get(True) or {}
assert wf['permissions'] == {'contents': 'read'}, wf.get('permissions')
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "uses: reusable pinned to agent-shield v2-stable channel" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
on = wf.get('on') or wf.get(True) or {}
uses = wf['jobs']['agent-shield']['uses']
assert uses == 'petry-projects/.github/.github/workflows/agent-shield-reusable.yml@agent-shield/v2-stable', uses
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

