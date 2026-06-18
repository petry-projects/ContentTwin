#!/usr/bin/env bats
# Tests for .github/workflows/pr-auto-review.yml
# Guards the concurrency fix (issue #274): superseded redundant runs on the same
# ref must be cancelled so bot-authored PR pushes don't pile up in the
# `action_required` state and inflate the Fleet Monitor failure rate.

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
  run python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "pr-auto-review workflow declares a concurrency block" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
assert 'concurrency' in wf, 'workflow has no top-level concurrency block'
c = wf['concurrency']
assert isinstance(c, dict), 'concurrency must be a mapping with group/cancel-in-progress'
assert c.get('group'), 'concurrency.group must be set'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "pr-auto-review concurrency cancels in-progress runs" {
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

@test "pr-auto-review concurrency group is keyed per ref" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
group = wf.get('concurrency', {}).get('group', '')
assert 'github.ref' in group, f'concurrency.group should key on github.ref, got: {group!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "pr-auto-review still delegates to the org reusable workflow" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
job = wf['jobs']['pr-auto-review']
uses = job.get('uses', '')
assert 'pr-auto-review-reusable.yml' in uses, f'job must call the org reusable, got: {uses!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}
