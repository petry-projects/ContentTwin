#!/usr/bin/env bats
# Tests for .github/workflows/dependency-audit.yml
#
# This workflow is a thin caller for the org-level reusable and is wired as a
# required status check. These tests lock the invariants that branch protection
# depends on (triggers, the `uses:` line, and the job name) and assert the
# repo-local reliability addition (a concurrency group, mirroring ci.yml) that
# trims redundant concurrent runs — the in-scope lever for issue #264.

WORKFLOW=".github/workflows/dependency-audit.yml"

# Emit a single field from the workflow via PyYAML. PyYAML parses the bare
# `on:` key as the boolean True (YAML 1.1), so callers read it as data[True].
query() {
  python3 - "$WORKFLOW" "$1" << 'PY'
import sys, yaml
path, expr = sys.argv[1], sys.argv[2]
with open(path) as fh:
    data = yaml.safe_load(fh)
on = data.get("on", data.get(True))
job = data["jobs"]["dependency-audit"]
ns = {"data": data, "on": on, "job": job}
print(eval(expr, {}, ns))
PY
}

@test "workflow is valid YAML" {
  run python3 -c "import yaml,sys; yaml.safe_load(open('$WORKFLOW'))"
  [ "$status" -eq 0 ]
}

@test "trigger: pull_request targets main (unchanged)" {
  run query "on['pull_request']['branches']"
  [ "$status" -eq 0 ]
  [ "$output" = "['main']" ]
}

@test "trigger: push targets main (unchanged)" {
  run query "on['push']['branches']"
  [ "$status" -eq 0 ]
  [ "$output" = "['main']" ]
}

@test "uses: reusable pinned line is unchanged" {
  run query "job['uses']"
  [ "$status" -eq 0 ]
  [ "$output" = "petry-projects/.github/.github/workflows/dependency-audit-reusable.yml@v1" ]
}

@test "job name 'dependency-audit' is unchanged" {
  run query "'dependency-audit' in data['jobs']"
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}

@test "concurrency group is defined" {
  run query "bool(data['concurrency']['group'])"
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}

@test "concurrency cancels superseded in-progress runs" {
  run query "data['concurrency']['cancel-in-progress']"
  [ "$status" -eq 0 ]
  [ "$output" = "True" ]
}
