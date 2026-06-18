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
  run python3 -c "import sys, yaml; yaml.safe_load(open('$WORKFLOW'))"
  [ "$status" -eq 0 ]
}

@test "sonarcloud workflow declares a concurrency block" {
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

@test "sonarcloud concurrency cancels in-progress runs" {
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

@test "sonarcloud concurrency group is keyed per ref" {
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

# Transient-failure retry resilience (org standard ci-standards.md #3): the scanner
# CLI download from binaries.sonarsource.com occasionally returns transient 403/5xx.
# A single blip must not fail the job and skew the Fleet Monitor failure rate, so the
# first scan runs with continue-on-error and a second step retries it on failure.

@test "sonarcloud runs two SonarSource scan steps" {
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
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
wf = yaml.safe_load(open(sys.argv[1]))
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
wf = yaml.safe_load(open(sys.argv[1]))
steps = wf['jobs']['sonarcloud']['steps']
scans = [s for s in steps if 'SonarSource/sonarqube-scan-action' in str(s.get('uses', ''))]
first_id = scans[0].get('id')
retry_if = str(scans[1].get('if', ''))
assert first_id and first_id in retry_if, f'retry if must reference first scan id {first_id!r}, got: {retry_if!r}'
assert \"outcome == 'failure'\" in retry_if, f'retry must run only on outcome == failure, got: {retry_if!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}
