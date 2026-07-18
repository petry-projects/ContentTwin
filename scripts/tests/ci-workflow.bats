#!/usr/bin/env bats
# Tests for .github/workflows/ci.yml
# Guards the Fleet Monitor resilience fix (issue #360): the CI pipeline's failure
# rate crossed the 10% threshold. Two transient-failure modes are addressed and
# must not regress:
#   1. Unretried network installs — `format` downloads shfmt via curl and `test`
#      installs bats via apt-get. A single 5xx/DNS blip failed the whole run, so
#      both are wrapped in a bounded retry loop.
#   2. Hung jobs — with no per-job timeout-minutes, a stalled download/scan ran to
#      GitHub's 6h default and concluded `timed_out`, which fleet_monitor.sh counts
#      as a failure. Every job now declares a timeout-minutes within the org cap.

WORKFLOW=".github/workflows/ci.yml"

setup() {
  if ! python3 -c "import yaml" &>/dev/null; then
    echo "Error: Python 'yaml' (PyYAML) module is required to run these tests." >&2
    return 1
  fi
}

@test "ci workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "ci workflow is valid YAML" {
  run python3 -c "
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
  yaml.safe_load(f)
" "$WORKFLOW"
  [ "$status" -eq 0 ]
}

# ── Triggers / config preserved (must not regress while hardening) ────────────

@test "ci triggers on push and pull_request to main" {
  run python3 -c "
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
  wf = yaml.safe_load(f) or {}
on = wf.get('on') or wf.get(True) or {}
push_val = on.get('push')
push_branches = (push_val or {}).get('branches', [])
assert 'main' in push_branches, f'push must target main, got: {push_val!r}'
pr_val = on.get('pull_request')
pr_branches = (pr_val or {}).get('branches', [])
assert 'main' in pr_branches, f'pull_request must target main, got: {pr_val!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "ci resets top-level permissions to empty" {
  run python3 -c "
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
  wf = yaml.safe_load(f) or {}
perms = wf.get('permissions')
assert perms == {}, f'top-level permissions must be reset to {{}}, got: {perms!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "ci declares SHA-scoped concurrency that cancels in-progress runs" {
  run python3 -c "
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
  wf = yaml.safe_load(f) or {}
c = wf.get('concurrency') or {}
assert isinstance(c, dict), f'concurrency must be a mapping, got: {c!r}'
group = c.get('group', '')
assert 'github.ref' in group and 'github.sha' in group, f'concurrency.group must be SHA-scoped per ref, got: {group!r}'
assert c.get('cancel-in-progress') is True, 'cancel-in-progress must be true'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

# ── Duration bounding: every job must fail fast rather than time out at 6h ─────

@test "every ci job declares an integer timeout-minutes within the org cap" {
  run python3 -c "
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
  wf = yaml.safe_load(f) or {}
jobs = wf.get('jobs') or {}
for name, job in jobs.items():
  tm = (job or {}).get('timeout-minutes')
  assert isinstance(tm, int), f'job {name!r} must set an integer timeout-minutes, got: {tm!r}'
  assert 1 <= tm <= 59, f'job {name!r} timeout-minutes must be within org cap 1..59, got: {tm}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

# ── Transient-failure retry resilience on unretried network installs ──────────

@test "shfmt download retries on transient failure" {
  run python3 -c "
import sys, yaml, re
with open(sys.argv[1], encoding='utf-8') as f:
  wf = yaml.safe_load(f) or {}
jobs = wf.get('jobs') or {}
format_job = jobs.get('format') or {}
steps = format_job.get('steps') or []
runs = [str(s.get('run', '')) for s in steps if 'shfmt' in str(s.get('run', ''))]
assert runs, 'format job must have a step that installs shfmt'
script = '\n'.join(runs)
assert 'curl' in script, 'shfmt install must download via curl'
assert re.search(r'for\s+\w+\s+in', script), 'shfmt install must loop over multiple attempts (retry loop)'
assert 'sleep' in script, 'shfmt retry loop must back off between attempts (sleep)'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "bats install retries on transient failure" {
  run python3 -c "
import sys, yaml, re
with open(sys.argv[1], encoding='utf-8') as f:
  wf = yaml.safe_load(f) or {}
jobs = wf.get('jobs') or {}
test_job = jobs.get('test') or {}
steps = test_job.get('steps') or []
runs = [str(s.get('run', '')) for s in steps if 'apt-get' in str(s.get('run', ''))]
assert runs, 'test job must have a step that installs bats via apt-get'
script = '\n'.join(runs)
assert re.search(r'for\s+\w+\s+in', script), 'bats install must loop over multiple attempts (retry loop)'
assert 'sleep' in script, 'bats retry loop must back off between attempts (sleep)'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}
