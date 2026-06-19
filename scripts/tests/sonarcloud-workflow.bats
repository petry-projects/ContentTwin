#!/usr/bin/env bats
# Tests for .github/workflows/sonarcloud.yml
# Guards the concurrency fix (issue #263): superseded redundant runs on the same
# ref must be cancelled so bot-authored PR pushes don't pile up in the
# `action_required` state and inflate the Fleet Monitor failure rate.

WORKFLOW=".github/workflows/sonarcloud.yml"

setup() {
  if ! python3 -c "import yaml" &>/dev/null; then
    echo "Error: Python 'yaml' (PyYAML) module is required to run these tests." >&2
    return 1
  fi
}

@test "sonarcloud workflow file exists" {
  [ -f "$WORKFLOW" ]
}

@test "sonarcloud workflow is valid YAML" {
  run python3 -c "import sys, yaml; yaml.safe_load(open('$WORKFLOW', encoding='utf-8'))"
  [ "$status" -eq 0 ]
}

@test "sonarcloud workflow declares a concurrency block" {
  run python3 -c "
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
  wf = yaml.safe_load(f)
assert 'concurrency' in wf, 'workflow has no top-level concurrency block'
c = wf['concurrency']
assert isinstance(c, dict), 'concurrency must be a mapping with group/cancel-in-progress'
assert c.get('group'), 'concurrency.group must be set'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "sonarcloud concurrency cancels in-progress runs" {
  run python3 -c "
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
  wf = yaml.safe_load(f)
c = wf.get('concurrency', {})
assert c.get('cancel-in-progress') is True, 'cancel-in-progress must be true'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "sonarcloud concurrency group is keyed per ref" {
  run python3 -c "
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
  wf = yaml.safe_load(f)
group = wf.get('concurrency', {}).get('group', '')
assert 'github.ref' in group, f'concurrency.group should key on github.ref, got: {group!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

# Transient-failure retry resilience (org standard ci-standards.md #3): the scanner
# CLI download from binaries.sonarsource.com occasionally returns transient 403/5xx.
# A single blip must not fail the job and skew the Fleet Monitor failure rate, so the
# first scan runs with continue-on-error and a second step retries it on failure.

@test "sonarcloud runs two SonarSource scan steps" {
  run python3 -c "
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
  wf = yaml.safe_load(f)
steps = wf['jobs']['sonarcloud']['steps']
scans = [s for s in steps if 'SonarSource/sonarqube-scan-action' in str(s.get('uses', ''))]
assert len(scans) == 2, f'expected 2 SonarSource scan steps (initial + retry), got {len(scans)}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "sonarcloud first scan tolerates a transient failure" {
  run python3 -c "
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
  wf = yaml.safe_load(f)
steps = wf['jobs']['sonarcloud']['steps']
scans = [s for s in steps if 'SonarSource/sonarqube-scan-action' in str(s.get('uses', ''))]
first = scans[0]
assert first.get('continue-on-error') is True, 'first scan must set continue-on-error: true'
assert first.get('id'), 'first scan must have an id so the retry can read its outcome'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "sonarcloud retry step is gated on the first scan failing" {
  run python3 -c "
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
  wf = yaml.safe_load(f)
steps = wf['jobs']['sonarcloud']['steps']
scans = [s for s in steps if 'SonarSource/sonarqube-scan-action' in str(s.get('uses', ''))]
first_id = scans[0].get('id')
retry_if = str(scans[1].get('if', ''))
assert first_id and first_id in retry_if, f'retry if must reference first scan id {first_id!r}, got: {retry_if!r}'
assert 'outcome' in retry_if and 'failure' in retry_if, f'retry must run only on outcome == failure, got: {retry_if!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

# Duration-bounding (issue #280): the Fleet Monitor counts a `timed_out` conclusion
# as a failure (fleet_monitor.sh). The #272 retry only recovers from a scan step
# that *errors*; a scan that *hangs* (CDN download or analysis upload stalls) has no
# step timeout, so it blocks the whole job until GitHub's 6-hour default and concludes
# `timed_out`. Bounding both the job and each scan step lets a hung first attempt fail
# fast so the retry can still run, instead of timing out the whole job.

@test "sonarcloud job declares a timeout-minutes within the org cap" {
  run python3 -c "
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
  wf = yaml.safe_load(f)
job = wf['jobs']['sonarcloud']
tm = job.get('timeout-minutes')
assert isinstance(tm, int), f'sonarcloud job must set an integer timeout-minutes, got: {tm!r}'
assert 1 <= tm <= 59, f'job timeout-minutes must be within the org cap 1..59, got: {tm}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "sonarcloud both scan steps declare a timeout-minutes" {
  run python3 -c "
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
  wf = yaml.safe_load(f)
steps = wf['jobs']['sonarcloud'].get('steps', [])
scans = [s for s in steps if 'SonarSource/sonarqube-scan-action' in str(s.get('uses', ''))]
assert len(scans) == 2, f'expected exactly 2 Sonar scan steps, got: {len(scans)}'
for i, s in enumerate(scans):
  tm = s.get('timeout-minutes')
  assert isinstance(tm, int) and tm >= 1, f'scan step {i} must set an integer timeout-minutes >= 1, got: {tm!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "sonarcloud first scan timeout leaves room for the retry within the job budget" {
  run python3 -c "
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
  wf = yaml.safe_load(f)
job = wf['jobs']['sonarcloud']
job_tm = job.get('timeout-minutes')
scans = [s for s in job.get('steps', []) if 'SonarSource/sonarqube-scan-action' in str(s.get('uses', ''))]
first_tm = scans[0].get('timeout-minutes') if scans else None
assert isinstance(job_tm, int) and isinstance(first_tm, int), 'timeouts must be integers'
assert first_tm < job_tm, f'first scan timeout ({first_tm}) must be < job timeout ({job_tm}) so a hung first attempt fails fast and the retry can run'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}
