#!/usr/bin/env bats
# Tests for .github/workflows/pr-review-mention.yml
# Guards the concurrency fix (issue #323): superseded redundant runs from
# near-simultaneous comment / review-request events must be cancelled so they
# don't pile up in the `action_required` state and inflate the Fleet Monitor
# failure rate. Mirrors the #274 fix guarded by pr-auto-review-workflow.bats.

WORKFLOW=".github/workflows/pr-review-mention.yml"

setup() {
  if ! python3 -c "import yaml" &>/dev/null; then
    echo "Error: Python 'yaml' (PyYAML) module is required to run these tests." >&2
    return 1
  fi
}

@test "pr-review-mention workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "pr-review-mention workflow is valid YAML" {
  run python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "pr-review-mention workflow declares a concurrency block" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
assert 'concurrency' in wf, 'workflow has no top-level concurrency block'
c = wf.get('concurrency')
assert isinstance(c, dict), 'concurrency must be a mapping with group/cancel-in-progress'
assert c.get('group'), 'concurrency.group must be set'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "pr-review-mention concurrency cancels in-progress runs" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
c = wf.get('concurrency') or {}
assert c.get('cancel-in-progress') is True, 'cancel-in-progress must be true'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "pr-review-mention concurrency group is keyed per conversation" {
  # The workflow fires on issue_comment, pull_request_review_comment and
  # pull_request events, whose github.ref is the default branch for comment
  # events. Keying only on github.ref would collapse runs across unrelated PRs,
  # so the group must key on the PR/issue number (with a github.ref fallback).
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
c = wf.get('concurrency') or {}
group = c.get('group', '')
assert 'github.event.issue.number' in group, f'group must key on issue number, got: {group!r}'
assert 'github.event.pull_request.number' in group, f'group must key on PR number, got: {group!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "pr-review-mention triggers are unchanged (stub must not alter events)" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
on = wf.get('on') or wf.get(True) or {}
assert 'created' in on.get('issue_comment', {}).get('types', []), 'issue_comment.created trigger missing'
assert 'created' in on.get('pull_request_review_comment', {}).get('types', []), 'pull_request_review_comment.created trigger missing'
assert 'review_requested' in on.get('pull_request', {}).get('types', []), 'pull_request.review_requested trigger missing'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "pr-review-mention still delegates to the org reusable at the stable channel" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
jobs = wf.get('jobs') or {}
job = jobs.get('pr-review-mention') or {}
uses = job.get('uses', '')
expected = 'petry-projects/.github/.github/workflows/pr-review-mention-reusable.yml@pr-review-mention/stable'
assert uses == expected, f'job must call the org reusable at the stable channel, got: {uses!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}
