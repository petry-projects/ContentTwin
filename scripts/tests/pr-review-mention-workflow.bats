#!/usr/bin/env bats
# Tests for .github/workflows/pr-review-mention.yml
# Guards the concurrency fix (issue #333). The #323 attempt used
# `cancel-in-progress: true`, but when it superseded a *pending* reusable-caller
# run (before the reusable resolved) GitHub recorded the cancellation as a
# startup failure — a burst of comment events on one conversation produced a
# wave of 0-job "failure" runs that inflated the Fleet Monitor failure rate.
# The fix mirrors add-to-project.yml (#331): `cancel-in-progress: false` with a
# group keyed on the event name AND the PR/issue number, so superseded runs are
# recorded as clean `cancelled` (not `failure`) and distinct event types on the
# same conversation don't cross-cancel.

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

@test "pr-review-mention concurrency does not cancel in-progress runs" {
  # cancel-in-progress must be false: superseding a pending reusable-caller run
  # makes GitHub record it as a startup failure, so a comment burst inflates the
  # failure rate (#333). With false, superseded runs are recorded as clean
  # `cancelled`. Mirrors add-to-project.yml (#331).
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
c = wf.get('concurrency') or {}
val = c.get('cancel-in-progress')
assert val is False, f'cancel-in-progress must be false, got: {val!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "pr-review-mention concurrency group is keyed per event and conversation" {
  # The workflow fires on issue_comment, pull_request_review_comment and
  # pull_request events, whose github.ref is the default branch for comment
  # events. Keying only on github.ref would collapse runs across unrelated PRs,
  # so the group keys on the PR/issue number. It also keys on github.event_name
  # so distinct event types on the same conversation get distinct groups and do
  # not cross-cancel (mirrors add-to-project.yml, #333/#331).
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
c = wf.get('concurrency') or {}
group = c.get('group', '')
assert 'github.event_name' in group, f'group must key on the event name, got: {group!r}'
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
