# Ralph

Ralph is a planning and execution workflow for coding tasks, packaged for both Claude slash commands and Codex skills.

## What You Get

- `claude/`: Claude command files:
  - `/ralph`
  - `/ralph-start`
  - `/ralph-retro`
  - `/ralph-reset`
- `codex/`: Matching Codex skills:
  - `ralph`
  - `ralph-start`
  - `ralph-retro`
  - `ralph-reset`

Both runtimes implement the same lifecycle:

1. Plan (`ralph`)
2. Execute (`ralph-start`)
3. Review and queue follow-ups (`ralph-retro`)
4. Reset state if needed (`ralph-reset`)

## Install

```bash
# default is claude if omitted
./install.sh claude
./install.sh codex
```

Install locations:

- `claude` -> `~/.claude/commands`
- `codex` -> `~/.codex/skills`

Notes:

- Installer validates required files before copying.
- Existing command/skill files prompt for overwrite.
- After Codex install, restart Codex so new skills are discovered.

## First-Run Onboarding

1. Run planning:
   - Claude: `/ralph <task description>`
   - Codex: invoke `ralph` with your task
2. Review generated plan files:
   - `.ralph/prd.md`
   - `.ralph/tasks/*.json`
   - `.ralph/decisions.json`
3. Reset context before execution:
   - Claude: run `/clear`
   - Codex: start a fresh Codex session
4. Execute tasks:
   - Claude: `/ralph-start`
   - Codex: `ralph-start`
5. Review commits and request changes:
   - Claude: `/ralph-retro`
   - Codex: `ralph-retro`
6. If you want to fully start over:
   - Claude: `/ralph-reset`
   - Codex: `ralph-reset`

## Command And Skill Reference

| Stage | Claude | Codex | What it does | Main outputs |
| --- | --- | --- | --- | --- |
| Plan | `/ralph <task>` | `ralph` | Detects project root, optionally runs research, captures decisions, generates PRD + task plan, then stops before execution. | `.ralph/state.json`, `.ralph/research.json` (complex tasks), `.ralph/decisions.json`, `.ralph/prd.md`, `.ralph/tasks/*.json` |
| Execute | `/ralph-start` | `ralph-start` | Runs planned tasks sequentially, updates task status, writes per-task results, creates per-task commits, fail-fast on first error. | `.ralph/results/*.md`, `.ralph/commits.json`, `.ralph/logs/execution.log`, `.ralph/logs/errors.log` |
| Retro | `/ralph-retro` | `ralph-retro` | Reviews execution commits with user feedback, records acceptance/questions/change requests, creates follow-up tasks when needed. | `.ralph/retro/feedback.json`, updated `.ralph/tasks/*.json`, updated `.ralph/state.json` |
| Reset | `/ralph-reset` | `ralph-reset` | Prompts for confirmation, then deletes all Ralph state so a new run can start cleanly. | Deletes `.ralph/` recursively |

## Behavior Details By Command

### `ralph` / `/ralph`

- Finds project root by searching upward for one of:
  - `.git`, `package.json`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `mix.exs`
- Archives previous run data into `.ralph/archive/<timestamp>-<slug>/` before creating a new run.
- Assesses task complexity:
  - `simple`: skip research
  - `complex`: generate `.ralph/research.json`
- Surfaces unresolved decisions before planning continues.
- Ends in `planning_complete`; does not execute code changes.

### `ralph-start` / `/ralph-start`

- Requires:
  - `.ralph/` exists
  - valid plan artifacts
  - git repository
  - clean working tree
- Executes tasks in `task_order` only (dependency order + priority).
- Tracks `pending -> in_progress -> completed` in `.ralph/state.json`.
- Stops immediately on failure and records `last_failure`.

### `ralph-retro` / `/ralph-retro`

- Requires `.ralph/commits.json` and clean git working tree.
- Reviews each commit in order, skipping already-reviewed commits.
- Stores feedback statuses (`accepted`, `questions`, `changes_requested`).
- Converts requested changes into new planned tasks and returns phase to `planning_complete`.

### `ralph-reset` / `/ralph-reset`

- Always asks for confirmation before deletion.
- Deletes `.ralph/` as a single unit (no partial reset).
- Safe to run even when `.ralph/` does not exist (prints "nothing to reset").

## `.ralph/` Directory At A Glance

```text
.ralph/
├── state.json
├── research.json            # optional
├── decisions.json
├── prd.md
├── tasks/
├── results/
├── logs/
├── commits.json             # created during execution
├── retro/
└── archive/
```

## Uninstall

```bash
./uninstall.sh claude
./uninstall.sh codex
```

Uninstall notes:

- Shows exactly what will be removed and asks for confirmation.
- Removes only Ralph command/skill entries from each target directory.
