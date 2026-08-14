#!/usr/bin/env bats
# Tests for .github/workflows/pr-review-mention.yml
#
# This file is a THIN CALLER STUB. Its `on:` triggers, `permissions:` grants and
# `concurrency:` surface are owned centrally by the canonical
# standards/workflows/pr-review-mention.yml and are not repo-adjustable
# (ci-standards.md → centralization tiers). The canonical stub carries NO
# top-level `concurrency:` block, so the stub must not declare one either —
# issue #404 re-synced the surface by removing a local block that had drifted in.
#
# History: #333 previously added a local `concurrency:` block here (group keyed
# on event name + PR/issue number, `cancel-in-progress: false`) to stop a comment
# burst from producing a wave of 0-job "failure" runs that inflated the Fleet
# Monitor failure rate. That protection is centrally owned now: if it is still
# wanted it belongs in the org reusable (pr-review-mention-reusable.yml), never
# re-added to this caller stub. These tests therefore assert the stub carries no
# local concurrency surface.

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

@test "pr-review-mention stub declares no local concurrency block (centrally owned, #404)" {
  # The canonical standards/workflows/pr-review-mention.yml carries no top-level
  # concurrency surface, and the concurrency surface of a thin caller stub is not
  # repo-adjustable (ci-standards.md → centralization tiers). A local block is
  # drift; #404 removed one that had crept in. If comment-burst concurrency
  # control is needed it must live in the org reusable, not this stub.
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
assert 'concurrency' not in wf, f'stub must not declare a local concurrency block (centrally owned), got: {wf.get(\"concurrency\")!r}'
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

@test "pr-review-mention still delegates to the org reusable at the v2-stable channel" {
  # Must pin the major-scoped channel @pr-review-mention/v2-stable, not the bare
  # tier @pr-review-mention/stable. The org standard (ci-standards.md →
  # centralization tiers) treats a bare tier pin as drift; the canonical stub
  # delegates to ...@pr-review-mention/v<M>-stable (#401).
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
jobs = wf.get('jobs') or {}
job = jobs.get('pr-review-mention') or {}
uses = job.get('uses', '')
expected = 'petry-projects/.github/.github/workflows/pr-review-mention-reusable.yml@pr-review-mention/v2-stable'
assert uses == expected, f'job must call the org reusable at the v2-stable channel, got: {uses!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}
