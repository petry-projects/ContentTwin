#!/usr/bin/env bats
# Tests for .github/workflows/add-to-project.yml
# Guards the reusable-channel pin (issue #330). The stub delegates to the org
# add-to-project reusable via a `uses:` ref and passes a matching `agent_ref`
# input. Both MUST pin the same v-form channel tag `add-to-project/v1-stable`.
# The bare `add-to-project/stable` tag is being retired (#657 v-form migration,
# completed for `agent_ref` by #328 but MISSED for `uses:`); a `uses:` left on
# the retiring bare tag fails to resolve and the run dies at startup with zero
# jobs, inflating the Fleet Monitor failure rate. Mirrors the stub guard in
# pr-review-mention-workflow.bats.

WORKFLOW=".github/workflows/add-to-project.yml"

setup() {
  if ! python3 -c "import yaml" &>/dev/null; then
    echo "Error: Python 'yaml' (PyYAML) module is required to run these tests." >&2
    return 1
  fi
}

@test "add-to-project workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "add-to-project workflow is valid YAML" {
  run python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "add-to-project triggers are unchanged (stub must not alter events)" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
on = wf.get('on') or wf.get(True) or {}
assert sorted(on.get('issues', {}).get('types', [])) == sorted(['opened', 'labeled', 'unlabeled', 'reopened']), f'issues triggers changed: {on.get(\"issues\")!r}'
assert sorted(on.get('pull_request_target', {}).get('types', [])) == sorted(['opened', 'labeled', 'unlabeled', 'reopened', 'ready_for_review']), f'pull_request_target triggers changed: {on.get(\"pull_request_target\")!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "add-to-project job keeps least-privilege permissions (contents: read)" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
assert wf.get('permissions') == {}, f'top-level permissions must stay empty, got: {wf.get(\"permissions\")!r}'
job = (wf.get('jobs') or {}).get('add-to-project') or {}
assert job.get('permissions') == {'contents': 'read'}, f'job permissions must be contents:read, got: {job.get(\"permissions\")!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "add-to-project declares a concurrency block that does not cancel in-progress runs" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
c = wf.get('concurrency')
assert isinstance(c, dict), 'concurrency must be a mapping'
assert c.get('group'), 'concurrency.group must be set'
assert c.get('cancel-in-progress') is False, f'cancel-in-progress must be false, got: {c.get(\"cancel-in-progress\")!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "add-to-project uses: pins the org reusable at the v1-stable channel (not the retiring bare tag)" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
job = (wf.get('jobs') or {}).get('add-to-project') or {}
uses = job.get('uses', '')
expected = 'petry-projects/.github/.github/workflows/add-to-project-reusable.yml@add-to-project/v1-stable'
assert uses == expected, f'uses: must pin the v1-stable channel, got: {uses!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "add-to-project agent_ref matches the uses: channel (both add-to-project/v1-stable)" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
job = (wf.get('jobs') or {}).get('add-to-project') or {}
agent_ref = (job.get('with') or {}).get('agent_ref', '')
assert agent_ref == 'add-to-project/v1-stable', f'agent_ref must be add-to-project/v1-stable, got: {agent_ref!r}'
uses = job.get('uses', '')
uses_channel = uses.rsplit('@', 1)[-1] if '@' in uses else ''
assert uses_channel == agent_ref, f'uses: channel ({uses_channel!r}) must equal agent_ref ({agent_ref!r})'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}
