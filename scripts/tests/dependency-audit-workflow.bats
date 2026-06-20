#!/usr/bin/env bats
# Tests for .github/workflows/dependency-audit.yml
# Guards the reusable workflow reference (standard: ci-standards.md#5-dependency-audit):
# ensures the workflow correctly delegates to the org reusable workflow with proper pinning.

WORKFLOW=".github/workflows/dependency-audit.yml"

setup() {
  if ! python3 -c "import yaml" &>/dev/null; then
    echo "Error: Python 'yaml' (PyYAML) module is required to run these tests." >&2
    return 1
  fi
}

@test "dependency-audit workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "dependency-audit workflow is valid YAML" {
  run python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "trigger: pull_request targets main (unchanged)" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
on = wf.get('on', wf.get(True, {}))
pr = on.get('pull_request', {})
branches = pr.get('branches', [])
assert 'main' in branches, f'pull_request must target main, got: {branches}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "trigger: push targets main (unchanged)" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
on = wf.get('on', wf.get(True, {}))
push = on.get('push', {})
branches = push.get('branches', [])
assert 'main' in branches, f'push must target main, got: {branches}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "uses: reusable pinned line is unchanged" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
job = wf['jobs']['dependency-audit']
uses = job.get('uses', '')
expected = 'petry-projects/.github/.github/workflows/dependency-audit-reusable.yml@'
assert uses.startswith(expected), f'job must call the org reusable workflow, got: {uses!r}'
print(uses)
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == petry-projects/.github/.github/workflows/dependency-audit-reusable.yml@* ]]
}

@test "job name 'dependency-audit' is unchanged" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
assert 'dependency-audit' in wf['jobs'], 'job name must be dependency-audit'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "concurrency group is defined" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
assert 'concurrency' in wf, 'workflow has no top-level concurrency block'
c = wf['concurrency']
assert isinstance(c, dict), 'concurrency must be a mapping'
assert c.get('group'), 'concurrency.group must be set'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "concurrency cancels superseded in-progress runs" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
c = wf.get('concurrency', {})
assert c.get('cancel-in-progress') is True, 'cancel-in-progress must be true'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}
