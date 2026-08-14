#!/usr/bin/env bats
# Tests for .github/workflows/pr-auto-review.yml
# pr-auto-review.yml is a Tier-1 thin caller stub: its behaviour lives in the org
# reusable (pr-auto-review-reusable.yml) and its `on:`, `permissions:` and
# `concurrency:` surfaces are centrally owned and NOT repo-adjustable
# (ci-standards.md#centralization-tiers). Adding a per-repo `concurrency:` block
# is drift, not a repo-specific liberty — the canonical
# `standards/workflows/pr-auto-review.yml` carries none. This guard locks that
# invariant (issue #405) so a future well-meaning edit can't re-introduce the
# drift the earlier `#274` block represented. Mirrors dev-lead-workflow.bats.

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

@test "pr-auto-review declares NO per-repo concurrency block (concurrency is centralised in the reusable)" {
  # `concurrency:` is a centrally-owned surface for Tier-1 stubs
  # (ci-standards.md#centralization-tiers); the canonical
  # standards/workflows/pr-auto-review.yml carries none. A per-repo block drifts
  # the stub from canonical (the compliance finding in issue #405) and would
  # fight the reusable's centralised grouping. If cancel-superseded-runs
  # behaviour is needed, it belongs in the reusable, not here.
  run python3 -c "
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1])) or {}
concurrency = wf.get('concurrency')
assert 'concurrency' not in wf, f'pr-auto-review stub must not add a concurrency block (it is centralised in the reusable), got: {concurrency!r}'
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
