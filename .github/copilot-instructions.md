# Copilot Instructions — ContentTwin

> **Note:** This file applies to the `petry-projects/ContentTwin` repository only. Org-wide rules are in [`petry-projects/.github/copilot-instructions.md`](https://github.com/petry-projects/.github/blob/main/.github/copilot-instructions.md). This file covers only what is specific to ContentTwin.

## About

ContentTwin is a repository security and analysis settings automation tool — a collection of shell scripts that apply required GitHub repository configurations (secret scanning, push protection, rulesets) across the petry-projects org.

## Tech Stack

- **Runtime:** Bash
- **Framework:** GitHub CLI (`gh`) for GitHub API operations
- **Testing:** ShellCheck (linting) · `shfmt` (formatting) — both enforced as CI gates
- **Linting:** ShellCheck (zero warnings required)
- **Key tools:** `gh` CLI (required, with repo admin scope)

## Project Structure

```text
scripts/
  apply-repo-settings.sh          # Applies security_and_analysis settings via GitHub API
  setup-rulesets.sh               # Configures branch protection rulesets
.github/
  scripts/                        # GitHub Actions helper scripts
    apply-code-quality-ruleset.sh
    apply-repo-settings.sh
    apply-secret-scanning-ai-detection.sh
  workflows/
    ci.yml                        # Runs ShellCheck + shfmt on every PR
    ...
```

## Local Dev Commands

- Lint:    `shellcheck scripts/*.sh`
- Format:  `shfmt -l -w scripts/`
- Run:     `bash scripts/apply-repo-settings.sh` (requires `gh` auth with repo admin scope)

## Required Environment Variables

- `GITHUB_TOKEN`: GitHub PAT with `repo` administration scope (or `gh auth login` interactively)
- `GITHUB_REPOSITORY`: Target repo in `owner/repo` format (defaults to `petry-projects/ContentTwin`)

## Testing Framework

- Runner: ShellCheck — static analysis enforced as a required CI check
- Format: `shfmt` — format check enforced as a required CI check
- Coverage: N/A — scripts are validated by running against the target repository
- Mutation testing: not configured

## Repo-Specific Overrides

All scripts must follow shell safety standards: `#!/usr/bin/env bash` with `set -euo pipefail`. No hardcoded tokens — use `$GITHUB_TOKEN` from the environment. Both ShellCheck and `shfmt` must pass before merge.

## Org Standards

See [petry-projects/.github — AGENTS.md](https://github.com/petry-projects/.github/blob/main/AGENTS.md) for org-wide development standards.

**Language-specific instructions** (applied automatically by Copilot when you open matching file types):

- [Shell](.github/instructions/shell.instructions.md) — safety flags, ShellCheck, quoting, error handling, Makefile standards
