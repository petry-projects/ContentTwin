#!/usr/bin/env bats
# Tests for .github/workflows/dependabot-rebase.yml
#
# This workflow is a Tier-1 thin caller stub for the org-level reusable. These
# tests lock the invariants the SOURCE OF TRUTH header declares immutable: the
# triggers (the self-sustaining push chain, the schedule safety net, the manual
# dispatch), the concurrency group that serializes rebases, the job name, and
# the `uses:` pin. Per ci-standards.md (Reusable workflow versioning — the
# `stable` channel) that pin must be the reusable's moving `@dependabot-rebase/stable`
# channel tag — never a frozen `@vX.Y.Z`, never a SHA.

WORKFLOW="$BATS_TEST_DIRNAME/../../.github/workflows/dependabot-rebase.yml"

# Emit a single field from the workflow via PyYAML. PyYAML parses the bare
# `on:` key as the boolean True (YAML 1.1), so callers read it as data[True].
query() {
  python3 - "$WORKFLOW" "$1" << 'PY'
import sys, yaml
path, expr = sys.argv[1], sys.argv[2]
with open(path) as fh:
    data = yaml.safe_load(fh) or {}
on = data.get("on", data.get(True)) or {}
job = data.get("jobs", {}).get("dependabot-rebase", {})
ns = {"data": data, "on": on, "job": job}
print(eval(expr, {}, ns))
PY
}

@test "workflow is valid YAML" {
  run python3 -c "import yaml; yaml.safe_load(open('$WORKFLOW'))"
  [ "$status" -eq 0 ]
}

@test "uses: reusable pinned to the moving stable channel tag" {
  run query "job['uses']"
  [ "$status" -eq 0 ]
  [ "$output" = "petry-projects/.github/.github/workflows/dependabot-rebase-reusable.yml@dependabot-rebase/stable" ]
}

@test "trigger: push targets main (self-sustaining chain)" {
  run query "on['push']['branches']"
  [ "$status" -eq 0 ]
  [ "$output" = "['main']" ]
}

@test "trigger: schedule safety net is present" {
  run query "bool(on['schedule'])"
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}

@test "trigger: workflow_dispatch allows manual queue flush" {
  run query "'workflow_dispatch' in on"
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}

@test "concurrency serializes rebases without cancelling in-progress runs" {
  run query "data['concurrency']['group']"
  [ "$status" -eq 0 ]
  [ "$output" = "dependabot-update-and-merge" ]
  run query "data['concurrency']['cancel-in-progress']"
  [ "$status" -eq 0 ]
  [ "$output" = "False" ]
}

@test "job name 'dependabot-rebase' is unchanged" {
  run query "'dependabot-rebase' in data['jobs']"
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}
