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
#
# Also guards the issue #364 fix: the `secret-scan` job previously used
# `gitleaks/gitleaks-action`, which requires a paid GITLEAKS_LICENSE for org
# repos. Dependabot PR runs receive no repository secrets, so the license was
# empty and gitleaks failed `missing gitleaks license` on every Dependabot PR —
# a conditional failure that pushed the failure rate over threshold. The job now
# runs the free, pinned gitleaks CLI (binary download + SHA256 verification) per
# push-protection.md Layer 3, removing the license dependency entirely.

WORKFLOW=".github/workflows/ci.yml"
GITLEAKS_CONFIG=".gitleaks.toml"

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
assert '--proto' in script, 'shfmt curl must pass --proto to restrict protocols'
assert '=https' in script, 'shfmt curl --proto flag must enforce HTTPS-only redirects (=https)'
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

@test "gitleaks download retries on transient failure" {
  run python3 -c "
import sys, yaml, re
with open(sys.argv[1], encoding='utf-8') as f:
  wf = yaml.safe_load(f) or {}
jobs = wf.get('jobs') or {}
scan = jobs.get('secret-scan') or {}
steps = scan.get('steps') or []
install = [s for s in steps if 'gitleaks' in str(s.get('run', '')) and 'detect' not in str(s.get('run', ''))]
assert install, 'secret-scan must have a step that installs the gitleaks CLI'
script = '\n'.join(str(s.get('run', '')) for s in install)
assert 'curl' in script, 'gitleaks install must download via curl'
assert '--proto' in script, 'gitleaks curl must pass --proto to restrict protocols'
assert '=https' in script, 'gitleaks curl --proto flag must enforce HTTPS-only redirects (=https)'
assert re.search(r'for\s+\w+\s+in', script), 'gitleaks install must loop over multiple attempts (retry loop)'
assert 'sleep' in script, 'gitleaks retry loop must back off between attempts (sleep)'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

# ── License-free secret scan: must not fail on Dependabot PRs (issue #364) ─────

@test "secret-scan does not depend on the licensed gitleaks-action or GITLEAKS_LICENSE" {
  run python3 -c "
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
  wf = yaml.safe_load(f) or {}
jobs = wf.get('jobs') or {}
scan = jobs.get('secret-scan') or {}
steps = scan.get('steps') or []
for s in steps:
  uses = str(s.get('uses', ''))
  assert 'gitleaks/gitleaks-action' not in uses, (
    'secret-scan must not use gitleaks/gitleaks-action (requires paid org license; '
    'fails on Dependabot PRs which get no secrets)')
blob = yaml.safe_dump(scan)
assert 'GITLEAKS_LICENSE' not in blob, (
  'secret-scan must not reference GITLEAKS_LICENSE — the license dependency is '
  'what breaks Dependabot PR runs')
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "secret-scan installs a pinned gitleaks binary verified with a checksum" {
  run python3 -c "
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
  wf = yaml.safe_load(f) or {}
jobs = wf.get('jobs') or {}
scan = jobs.get('secret-scan') or {}
steps = scan.get('steps') or []
install = [s for s in steps if 'gitleaks' in str(s.get('run', '')) and 'detect' not in str(s.get('run', ''))]
assert install, 'secret-scan must have a step that installs the gitleaks CLI'
script = '\n'.join(str(s.get('run', '')) for s in install)
env = {}
for s in install:
  env.update(s.get('env') or {})
version = env.get('GITLEAKS_VERSION')
checksum = env.get('GITLEAKS_CHECKSUM')
assert version, 'gitleaks install must pin an explicit GITLEAKS_VERSION'
assert checksum, 'gitleaks install must pin a GITLEAKS_CHECKSUM'
assert 'sha256sum -c' in script, 'gitleaks binary must be verified with sha256sum -c before use'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "secret-scan runs the gitleaks CLI with redact, exit-code, and config" {
  run python3 -c "
import sys, yaml
with open(sys.argv[1], encoding='utf-8') as f:
  wf = yaml.safe_load(f) or {}
jobs = wf.get('jobs') or {}
scan = jobs.get('secret-scan') or {}
steps = scan.get('steps') or []
runs = [str(s.get('run', '')) for s in steps if 'gitleaks detect' in str(s.get('run', ''))]
assert runs, 'secret-scan must run gitleaks detect via the CLI'
script = '\n'.join(runs)
assert '--redact' in script, 'gitleaks detect must pass --redact so secrets never hit logs'
assert '--exit-code 1' in script, 'gitleaks detect must fail the build on findings (--exit-code 1)'
assert '--config .gitleaks.toml' in script, 'gitleaks detect must pass --config .gitleaks.toml'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "repo ships a .gitleaks.toml config at root" {
  [ -f "$GITLEAKS_CONFIG" ]
}

@test ".gitleaks.toml parses as valid TOML" {
  python3 -c "import tomllib" 2>/dev/null || skip "tomllib not available (Python < 3.11)"
  run python3 -c "
import sys, tomllib
with open(sys.argv[1], 'rb') as f:
  tomllib.load(f)
print('ok')
" "$GITLEAKS_CONFIG"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}
