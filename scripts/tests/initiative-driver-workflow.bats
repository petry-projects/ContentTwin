#!/usr/bin/env bats
# Tests for .github/workflows/initiative-driver.yml
# Regression guard for the centrally owned invariants of this thin caller stub.

WORKFLOW=".github/workflows/initiative-driver.yml"

# setup - Verify test environment has required dependencies.
setup() {
  # Verify PyYAML is installed; required to parse and validate YAML workflow files.
  if ! python3 -c "import yaml" &>/dev/null; then
    echo "Error: Python 'yaml' (PyYAML) module is required to run these tests." >&2
    return 1
  fi
}

@test "trigger: on: surface is issues, schedule, workflow_dispatch" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
on = wf.get('on') or wf.get(True) or {}
assert set(on) == {'issues', 'schedule', 'workflow_dispatch'}, sorted(on)
assert on['issues']['types'] == ['closed', 'labeled']
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "gate tooling checkout is pinned to a 40-hex SHA and fail-open" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
on = wf.get('on') or wf.get(True) or {}
import re
steps = wf['jobs']['dispatch']['steps']
co = [s for s in steps if s.get('with', {}).get('repository') == 'petry-projects/.github']
assert len(co) == 1
assert re.fullmatch(r'[0-9a-f]{40}', co[0]['with']['ref']), co[0]['with']['ref']
assert co[0]['continue-on-error'] is True
assert co[0]['with']['persist-credentials'] is False
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "gate step is fail-open and enforcing" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
on = wf.get('on') or wf.get(True) or {}
steps = wf['jobs']['dispatch']['steps']
g = [s for s in steps if s.get('id') == 'arl_gate']
assert len(g) == 1
assert g[0]['continue-on-error'] is True
assert '--mode enforce' in g[0]['run']
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "dispatch step skips only on explicit defer" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
on = wf.get('on') or wf.get(True) or {}
steps = wf['jobs']['dispatch']['steps']
d = [s for s in steps if 'gh workflow run' in s.get('run', '')]
assert len(d) == 1
assert d[0]['if'] == 'steps.arl_gate.outputs.decision != ' + chr(39) + 'defer' + chr(39), d[0].get('if')
assert 'gh workflow run initiative-driver.yml' in d[0]['run']
assert '-R petry-projects/.github-private' in d[0]['run']
assert '-f target_repo=' + chr(36) + '{{ github.repository }}' in d[0]['run']
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

