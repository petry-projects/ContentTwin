#!/usr/bin/env bats
# Tests for .github/workflows/persona-mention.yml
# Regression guard for the centrally owned invariants of this thin caller stub.

WORKFLOW=".github/workflows/persona-mention.yml"

# setup - Verify test environment has required dependencies.
setup() {
  # Verify PyYAML is installed; required to parse and validate YAML workflow files.
  if ! python3 -c "import yaml" &>/dev/null; then
    echo "Error: Python 'yaml' (PyYAML) module is required to run these tests." >&2
    return 1
  fi
}

@test "trigger: on: surface includes comment events and reviewer assignment" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
on = wf.get('on') or wf.get(True) or {}
assert set(on) == {'issue_comment', 'pull_request_review_comment', 'discussion_comment', 'pull_request'}, sorted(on)
for k, v in on.items():
    if k == 'pull_request':
        assert v == {'types': ['review_requested']}, (k, v)
    else:
        assert v == {'types': ['created']}, (k, v)
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "permissions: workflow-level empty, job-level least privilege" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
on = wf.get('on') or wf.get(True) or {}
assert wf['permissions'] == {}, wf.get('permissions')
assert wf['jobs']['persona-mention']['permissions'] == {'contents': 'read', 'issues': 'read', 'pull-requests': 'read'}
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "uses: reusable pinned to persona-mention v1-stable channel" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
on = wf.get('on') or wf.get(True) or {}
uses = wf['jobs']['persona-mention']['uses']
assert uses == 'petry-projects/.github/.github/workflows/persona-mention-reusable.yml@persona-mention/v1-stable', uses
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "secrets: inherit contract is unchanged" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
on = wf.get('on') or wf.get(True) or {}
assert wf['jobs']['persona-mention']['secrets'] == 'inherit'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

