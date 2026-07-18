#!/usr/bin/env bats
# Tests for .github/workflows/dev-lead.yml
# Guards the dev-lead thin-caller stub against the startup-failure drift class
# that inflates the Fleet Monitor failure rate (issue #359). dev-lead.yml is a
# VERBATIM caller stub: its behaviour lives in the org reusable
# (dev-lead-reusable.yml), and its `on:`, `permissions:` and concurrency design
# are NOT repo-adjustable (see the stub header and petry-projects/.github#402).
#
# The failure/cancellation class the monitor flags is drift, not a repo bug:
#   • trimming a trigger, or
#   • adding a per-repo `concurrency:` block (the tempting-but-wrong "fix" that
#     worked for pr-review-mention #333 / add-to-project #331, but here would
#     fight the reusable's centralised per-issue/per-PR lanes and re-inflate the
#     rate), or
#   • letting `uses:`/`agent_ref` fall off the moving `dev-lead/stable` channel
#     (cf. add-to-project #330, where a stale channel pin failed to resolve and
#     runs died at startup with zero jobs, recorded as failures).
# This guard locks those invariants so a future well-meaning edit can't silently
# re-introduce the drift. Mirrors add-to-project-workflow.bats and
# pr-review-mention-workflow.bats.

WORKFLOW=".github/workflows/dev-lead.yml"

setup() {
  if ! python3 -c "import yaml" &>/dev/null; then
    echo "Error: Python 'yaml' (PyYAML) module is required to run these tests." >&2
    return 1
  fi
}

@test "dev-lead workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "dev-lead workflow is valid YAML" {
  run python3 -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

@test "dev-lead triggers are unchanged (stub must not trim events)" {
  # The reusable dispatches on the full event surface; trimming any trigger here
  # would silently drop coverage. The stub header forbids trimming triggers.
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
on = wf.get('on') or wf.get(True) or {}
pr = on.get('pull_request') or {}
assert sorted(pr.get('types', [])) == sorted(['opened', 'reopened', 'synchronize']), f'pull_request triggers changed: {pr!r}'
pr_rev = on.get('pull_request_review') or {}
assert sorted(pr_rev.get('types', [])) == sorted(['submitted']), f'pull_request_review triggers changed: {pr_rev!r}'
pr_rev_cmt = on.get('pull_request_review_comment') or {}
assert sorted(pr_rev_cmt.get('types', [])) == sorted(['created']), f'pull_request_review_comment triggers changed: {pr_rev_cmt!r}'
issue_cmt = on.get('issue_comment') or {}
assert sorted(issue_cmt.get('types', [])) == sorted(['created']), f'issue_comment triggers changed: {issue_cmt!r}'
issues = on.get('issues') or {}
assert sorted(issues.get('types', [])) == sorted(['labeled']), f'issues triggers changed: {issues!r}'
check_run = on.get('check_run') or {}
assert sorted(check_run.get('types', [])) == sorted(['completed']), f'check_run triggers changed: {check_run!r}'
repo_disp = on.get('repository_dispatch') or {}
assert sorted(repo_disp.get('types', [])) == sorted(['dev-lead-ci-failure', 'dev-lead-reviews-retry', 'dev-lead-issue-retry']), f'repository_dispatch triggers changed: {repo_disp!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "dev-lead top-level permissions stay empty ({})" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
perms = wf.get('permissions')
assert perms == {}, f'top-level permissions must stay empty, got: {perms!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "dev-lead declares NO per-repo concurrency block (concurrency is centralised in the reusable)" {
  # Concurrency lives in dev-lead-reusable.yml with per-issue/per-PR lanes
  # (petry-projects/.github#402) so issue pickups are never cancelled by PR
  # follow-up traffic. A per-repo concurrency block would drift the stub and
  # fight the centralised grouping — re-inflating the failure/cancellation rate.
  # This is the one point where dev-lead deliberately diverges from the
  # add-to-project / pr-review-mention stubs (which DO carry a concurrency block).
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
concurrency = wf.get('concurrency')
assert 'concurrency' not in wf, f'dev-lead stub must not add a concurrency block (it is centralised in the reusable), got: {concurrency!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "dev-lead job keeps its documented least-privilege permissions" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
job = (wf.get('jobs') or {}).get('dev-lead') or {}
expected = {'contents': 'write', 'pull-requests': 'write', 'issues': 'write', 'actions': 'read', 'checks': 'read', 'statuses': 'read'}
perms = job.get('permissions')
assert perms == expected, f'job permissions drifted, got: {perms!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "dev-lead uses: pins the org reusable at the dev-lead/stable channel (not @main or a SHA)" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
job = (wf.get('jobs') or {}).get('dev-lead') or {}
uses = job.get('uses', '')
expected = 'petry-projects/.github-private/.github/workflows/dev-lead-reusable.yml@dev-lead/stable'
assert uses == expected, f'uses: must pin the dev-lead/stable channel, got: {uses!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "dev-lead agent_ref matches the uses: channel (both dev-lead/stable)" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
job = (wf.get('jobs') or {}).get('dev-lead') or {}
agent_ref = (job.get('with') or {}).get('agent_ref', '')
assert agent_ref == 'dev-lead/stable', f'agent_ref must be dev-lead/stable, got: {agent_ref!r}'
uses = job.get('uses', '')
uses_channel = uses.rsplit('@', 1)[-1] if '@' in uses else ''
assert uses_channel == agent_ref, f'uses: channel ({uses_channel!r}) must equal agent_ref ({agent_ref!r})'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}
