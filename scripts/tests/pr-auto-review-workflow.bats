#!/usr/bin/env bats
# Tests for .github/workflows/pr-auto-review.yml
# pr-auto-review.yml is a Tier-1 thin caller stub: its behaviour lives in the org
# reusable (pr-auto-review-reusable.yml) and its `on:`, `permissions:` and
# `concurrency:` surfaces are centrally owned and NOT repo-adjustable
# (ci-standards.md#centralization-tiers). Because those surfaces are central, the
# stub must carry the SAME `concurrency:` block as the canonical
# `standards/workflows/pr-auto-review.yml`: neither a per-repo variant nor its
# absence is a repo-specific liberty.
#
# History: the canonical originally carried NO concurrency block, so issue #405
# locked "no concurrency" here (removing the earlier drifting `#274` block). That
# premise changed with petry-projects/.github#1126 (2026-09-16), which added a
# central concurrency block that deduplicates ONLY the default-branch-context
# triggers (check_suite / workflow_run) per PR while leaving PR-head triggers on a
# unique-per-run group. Issue #457 re-synced this stub to that block, and this
# guard now locks the new invariant so a future edit can't drop or drift it.
# Mirrors add-to-project-workflow.bats (a sibling stub that carries a concurrency
# block).

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

@test "pr-auto-review carries the canonical top-level concurrency block (synced from standards, issue #1126/#457)" {
  # `concurrency:` is a centrally-owned surface for Tier-1 stubs
  # (ci-standards.md#centralization-tiers). Since petry-projects/.github#1126 the
  # canonical standards/workflows/pr-auto-review.yml carries a top-level block that
  # dedupes ONLY the default-branch-context triggers per PR: the `group` selects a
  # per-PR group for check_suite/workflow_run and a unique-per-run group otherwise,
  # and `cancel-in-progress` is true only for those two events. The stub must match
  # it verbatim in shape — a missing block (the #457 drift) or a per-repo variant
  # is drift. Concurrency must live at the TOP level, not per-job, so we also assert
  # no job introduces its own block.
  run python3 -c "
import sys, yaml, re
wf = yaml.safe_load(open(sys.argv[1])) or {}
c = wf.get('concurrency')
assert isinstance(c, dict), f'pr-auto-review stub must carry a top-level concurrency block synced from canonical, got: {c!r}'

def strip_expr(s):
    # Strip ${{ ... }} wrapper if present, then normalize whitespace
    s = s.strip()
    if s.startswith('\${{') and s.endswith('}}'):
        s = s[3:-2].strip()
    return ' '.join(s.split())

# Canonical group expression from petry-projects/.github#1126
canonical_group = (
    \"(github.event_name == 'check_suite' && github.event.check_suite.pull_requests[0].number) \"
    \"&& format('pr-auto-review-ready-check-pr-{0}', github.event.check_suite.pull_requests[0].number) \"
    \"|| (github.event_name == 'workflow_run' && github.event.workflow_run.pull_requests[0].number) \"
    \"&& format('pr-auto-review-ready-check-pr-{0}', github.event.workflow_run.pull_requests[0].number) \"
    \"|| format('pr-auto-review-ready-check-unique-{0}', github.run_id)\"
)

# Canonical cancel-in-progress expression
canonical_cip = \"github.event_name == 'check_suite' || github.event_name == 'workflow_run'\"

group_raw = c.get('group', '')
cip_raw = c.get('cancel-in-progress', '')

group_norm = strip_expr(group_raw)
cip_norm = strip_expr(cip_raw)
canonical_group_norm = ' '.join(canonical_group.split())
canonical_cip_norm = ' '.join(canonical_cip.split())

assert group_norm == canonical_group_norm, \\
    f'concurrency.group must match canonical expression exactly, got:\\n{group_norm!r}\\n\\nexpected:\\n{canonical_group_norm!r}'
assert cip_norm == canonical_cip_norm, \\
    f'cancel-in-progress must match canonical expression exactly, got:\\n{cip_norm!r}\\n\\nexpected:\\n{canonical_cip_norm!r}'

for job_id, job_cfg in (wf.get('jobs') or {}).items():
    job_cfg = job_cfg or {}
    job_conc = job_cfg.get('concurrency')
    assert 'concurrency' not in job_cfg, f'job {job_id!r} must not add a per-job concurrency block; concurrency is top-level, got: {job_conc!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}

@test "pr-auto-review workflow has no unresolved TODO comment (S1135)" {
  run grep -nE '(^|[[:space:]])#[[:space:]]*TODO' "$WORKFLOW"
  if [ "$status" -eq 0 ]; then
    echo "Found TODO(s):" >&2
    echo "$output" >&2
    return 1
  fi
  # grep returns 1 when no matches were found
  [ "$status" -eq 1 ]
}

@test "pr-auto-review workflow_run targets real CI workflow name(s)" {
  run python3 -c "
import sys, glob, os, yaml

wf = yaml.safe_load(open(sys.argv[1])) or {}
# PyYAML parses the bare 'on:' key as boolean True.
on = wf.get('on') or wf.get(True) or {}
targets = (on.get('workflow_run') or {}).get('workflows', [])
assert targets, 'workflow_run.workflows must list at least one workflow name'

names = set()
for path in glob.glob('.github/workflows/*.yml'):
    doc = yaml.safe_load(open(path)) or {}
    if isinstance(doc, dict) and doc.get('name'):
        names.add(doc['name'])

missing = [t for t in targets if t not in names]
assert not missing, f'workflow_run.workflows names not found in repo: {missing!r}'
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
expected = 'petry-projects/.github/.github/workflows/pr-auto-review-reusable.yml@'
assert uses.startswith(expected), f'job must call the org reusable workflow, got: {uses!r}'
print('ok')
" "$WORKFLOW"
  [ "$status" -eq 0 ]
  [[ "$output" == "ok" ]]
}
