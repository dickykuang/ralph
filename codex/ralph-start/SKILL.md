---
name: ralph-start
description: Execute planned .ralph tasks sequentially with Codex worker sessions and per-task commits.
---

# Codex Runtime Mapping

- This is a Codex skill adaptation of the original Claude command flow.
- Replace Claude `Task` tool usage with fresh Codex worker sessions (for example, separate `codex exec` runs or equivalent isolated task execution in your runtime).
- Replace `AskUserQuestion` tool calls with direct user prompts in chat.
- Replace slash-command assumptions with skill invocations by name.

---

# Ralph Start - Execute Tasks

You are Ralph's execution engine. Your job is to execute the planned tasks from `.ralph/` directory using worker sessions for sequential execution with fresh context.

## Pre-Execution Checks

Before executing, verify the following:

1. **Check for .ralph/ directory**: Must exist in project root
2. **Read state.json**: Verify phase is `planning_complete` or `executing`
3. **Verify git repository**: Must be inside a git repo
4. **Verify clean working tree**: `git status --porcelain` must be empty
5. **Verify plan artifacts**: `.ralph/prd.md`, `.ralph/decisions.json`, and `.ralph/code_context.json` should exist
6. **Read task files**: Load all tasks from `.ralph/tasks/`
7. **Verify tasks exist**: At least one task file must be present
8. **Reuse notes check**: Warn if a task appears to need reuse but has no `reuse_notes`

If any check fails, report the error and stop.

---

## Execution Workflow

### Reuse Notes Heuristic

Before execution, perform a lightweight check:

- If a task title or description contains keywords like `auth`, `token`, `validation`, `schema`, `client`, `api`, `http`, `db`, `cache`, or `logger`
- AND `reuse_notes` is missing or empty

Then print a warning:
```
Warning: task-XXX may benefit from reuse_notes but none were provided.
Consider updating the plan or proceed as-is.
```

Do not block execution; this is advisory only.

### Step 1: Load State and Tasks

1. Read `.ralph/state.json`
2. Read `.ralph/decisions.json`
3. Read `.ralph/code_context.json` (required)
4. Read `.ralph/research.json` (if exists)
5. Read `.ralph/commits.json` (if exists)
6. Read `.ralph/results/` for prior task summaries (if exists)
7. Read all task files from `.ralph/tasks/` directory
8. Build execution plan from `task_order` in state.json (already sorted by dependencies, then priority)
9. Identify current progress from `task_statuses`

### Step 2: Update State to Executing

Update state.json:
- Set `phase` to `executing`
- Set `updated_at` to current timestamp
- If `base_commit` is null, set it to current `HEAD` hash

### Step 3: Execute Sequentially by Priority

Process tasks in the exact order listed in `task_order` (already sorted by dependencies, then priority).

```
For each task in task_order:
    1. If status is "completed", skip
    2. If status is "in_progress" or "pending":
       - Verify all dependencies are "completed"
       - If dependencies are missing, stop with an error (planning bug)

    3. Mark task as "in_progress" in state.json
    4. Spawn the worker session for the task
    5. Wait for the worker session to complete

    6. If success:
       - Update task status to "completed" in state.json
       - Save result to .ralph/results/task-NNN.md
       - Create a git commit for the task (see Commit Policy)
       - Show: "✓ Completed: [task-id] - [title]"

    7. If failure:
       - FAIL-FAST: Stop processing immediately
       - Update failed task status to "failed" in state.json
       - Log error to .ralph/logs/errors.log (see Error Handling)
       - Set phase to "failed" in state.json
       - Set last_failure object in state.json
       - Report failure with task ID, error, and log file path
       - EXIT - do NOT continue to next task
```

### Step 4: Completion

When all tasks complete successfully:
1. Update state.json phase to `completed`
2. Write detailed execution log to `.ralph/logs/execution.log`
3. Display execution summary to user (see Execution Summary section below)
4. Suggest `ralph-retro` skill to review commits

---

## Spawning Worker Sessions

For each task, spawn a worker session using a Codex worker session with this configuration:

```
Worker session parameters:
  description: "[task-id]: [short title]"
  execution_mode: "general-purpose"
  prompt: |
    Execute this task from the Ralph plan:

    OVERALL CONTEXT:
    You are executing one task as part of a larger implementation plan.
    Original Request: [from state.json original_request]

    IMPORTANT: Before implementing, read `.ralph/prd.md` to understand the full
    project requirements, architecture decisions, and how this task fits into
    the overall plan.

    ---

    TASK ID: [task.id]
    TITLE: [task.title]

    DESCRIPTION:
    [task.description]

    ACCEPTANCE CRITERIA:
    [Each criterion as a bullet point]

    FILES TO MODIFY:
    [Each file path as a bullet point]

    DEPENDENCIES:
    [List each task dependency with commit hash if available]

    PRIOR CHANGES:
    [Brief summaries from .ralph/results/task-XXX.md for each dependency, if available]

    CODE CONTEXT NOTES:
    [If task.context.code_context_refs exists, include the referenced items from .ralph/code_context.json.
    Otherwise include the most relevant entry_points, hot_paths, and data_flows from .ralph/code_context.json for this task.]

    RESEARCH NOTES:
    [If task.context.research_refs exists, include the referenced items from .ralph/research.json]

    REUSE NOTES:
    [If task.reuse_notes exists, list the helpers/utilities to prefer]

    TASK-SPECIFIC CONTEXT:
    [task.context if present, or "No additional context"]

    DECISIONS MADE:
    [Relevant decisions from decisions.json, if task.context.decisions_refs exists]

    ---

    Instructions:
    1. Read `.ralph/prd.md` to understand the overall project context
    2. Implement the task following the description
    3. Ensure ALL acceptance criteria are met
    4. Only modify the files listed (or closely related files if necessary)
    5. Run relevant tests if applicable
    6. Do NOT run `git add` or `git commit` (the orchestrator handles commits)
    7. Prefer existing helpers/utilities. Before creating a new function, search the codebase for an existing one. Only add a new function if no suitable helper exists, and keep it centralized (avoid duplicates).
    8. Preserve documented data-flow invariants from CODE CONTEXT NOTES unless the task explicitly requires changing them.

    OUTPUT REQUIREMENTS - CRITICAL:
    - Do NOT output lengthy explanations or implementation details
    - Do NOT use phrases like "Let me think..." or "I'm going to..."
    - Focus your response on RESULTS, not process
    - Return a brief, structured result confirming what was done

    When complete, return ONLY:
    1. Status: success or failure
    2. Brief summary (1-2 sentences max)
    3. List of files modified
    4. For each acceptance criterion: ✓ Met or ✗ Not met (with brief reason if not met)
```

### Prompt Assembly Notes

- **Dependencies**: Use `task.dependencies`. For each dependency, include the commit hash from `.ralph/commits.json` if present.
- **Prior Changes**: If `.ralph/results/task-XXX.md` exists for a dependency, include a 1-2 sentence summary.
- **Code Context Notes**: If `task.context.code_context_refs` exists, include only the referenced items from `.ralph/code_context.json`; otherwise include the most relevant entry_points, hot_paths, and data_flows for the task.
- **Research Notes**: If `task.context.research_refs` exists, include only the referenced items from `.ralph/research.json`.
- **Reuse Notes**: If `task.reuse_notes` exists, include it as a bullet list.
- **Fallbacks**: If any of the above data is missing, write "None" for that section.

---

## Sequential Execution Rules

Tasks run one at a time in `task_order`. Do not spawn multiple Codex worker session calls in a single message.

### Wait Behavior

For each task:
1. Spawn a single worker session
2. Wait for completion
3. Process result, commit, and update state before starting the next task

---

## Resumption Logic

If `phase` is already `executing` (interrupted run), resume as follows:

1. Skip tasks with status `completed`
2. Retry tasks with status `in_progress` (may have been interrupted)
3. Continue with tasks with status `pending`

For `in_progress` tasks:
- Check if the task was actually completed by examining .ralph/results/
- If result file exists and commits.json contains a commit for the task, mark as completed
- Otherwise, re-execute the task

---

## State Updates

### Before Each Task

```json
// For each task about to start
{
  "task_statuses": {
    "[task-id]": "in_progress"
  },
  "updated_at": "<timestamp>"
}
```

### After Each Task Completes

```json
// For successful completion
{
  "task_statuses": {
    "[task-id]": "completed"
  },
  "updated_at": "<timestamp>"
}
```

### On Failure

```json
{
  "phase": "failed",
  "task_statuses": {
    "[failed-task-id]": "failed"
  },
  "last_failure": {
    "task_id": "[task-id]",
    "task_title": "[task title]",
    "error_message": "[error details]",
    "failed_at": "<timestamp>",
    "log_file": ".ralph/logs/errors.log"
  },
  "updated_at": "<timestamp>"
}
```

---

## Progress Display

**CRITICAL: Keep output minimal and informative. No lengthy explanations or "let me think" verbosity.**

### Output Format Requirements

When executing, show ONLY brief status updates. Do NOT stream:
- Implementation details
- Code being written
- File contents
- Worker Session reasoning
- "Let me think about..." or similar phrases

### Required Messages

**When starting a task:**
```
→ Starting: [task-id] - [task title]
```

**When a task completes successfully:**
```
✓ Completed: [task-id] - [task title]
```

**When a task fails:**
```
✗ Failed: [task-id] - [task title]
  Error: [brief one-line error summary]
```

### Example Execution Output

```
Starting execution...
Phase: executing
Tasks: 5 total, 0 completed

→ Starting: task-001 - Create user model
✓ Completed: task-001 - Create user model
→ Starting: task-002 - Create product model
✓ Completed: task-002 - Create product model
→ Starting: task-003 - Create user controller
✓ Completed: task-003 - Create user controller
→ Starting: task-004 - Add validation logic
✗ Failed: task-004 - Add validation logic
  Error: Type mismatch in validation function

✗ EXECUTION STOPPED - Task Failed
...
```

### Verbosity Rules

| DO show | Do NOT show |
|---------|-------------|
| Task ID and title | Implementation code |
| Brief completion status | Worker Session reasoning |
| One-line error summary | Full stack traces (put in logs) |
| Task progress | "I'm going to..." preambles |
| Final summary | "Let me think..." explanations |

---

## Results Storage

**Detailed task results go to .ralph/results/, NOT to the console output.**

### Why Store Results Separately?

1. **Keeps console clean** - Users see progress, not implementation noise
2. **Provides detailed logs** - Full execution details available for debugging
3. **Enables review** - Users can examine what each task actually did
4. **Supports resumption** - Helps determine if interrupted tasks completed

### Result File Format

For each completed task, save to `.ralph/results/task-NNN.md`:

```markdown
# Task Result: [task-id]

## Task: [task title]

## Status: completed | failed

## Timestamp: [ISO 8601]

## Commit: [commit hash or "n/a" if failed]

## Changes Made
- [file1.ext]: [brief description of change]
- [file2.ext]: [brief description of change]

## Acceptance Criteria Results
- [x] Criterion 1 - Met because...
- [x] Criterion 2 - Met because...
- [ ] Criterion 3 - NOT MET: [reason]

## Notes
[Any additional context, warnings, or observations]
```

### What Goes Where

| Information | Where it goes |
|-------------|---------------|
| "Starting task X" | Console (brief) |
| Code changes made | .ralph/results/ |
| File diffs | `git show <commit>` (commit hash in results/commits.json) |
| Test output | .ralph/results/ |
| Commit hash | .ralph/results/ and .ralph/commits.json |
| Error stack traces | .ralph/logs/errors.log |
| Completion message | Console (brief) |
| Criteria verification | .ralph/results/ |

### Worker Session Instructions for Results

When spawning worker sessions, instruct them to:
1. **Do NOT** print lengthy implementation details to the user
2. **DO** return a structured result that will be saved to results/
3. Focus output on confirmation that acceptance criteria were met

---

## Commit Policy

After each successful task, create a git commit so every task maps to a single commit.

### Commit Preconditions

1. Working tree must be clean before starting a task
2. After the task completes, only task-related changes should exist
3. If unrelated changes are detected, stop and report an error

### Commit Steps

1. `git add -A`
2. `git commit -m "ralph: [task-id] - [task title]"`
3. Capture the commit hash
4. Write or update `.ralph/commits.json` with the mapping
5. Ensure working tree is clean after the commit

### commits.json Format

Save commit metadata to `.ralph/commits.json`:

```json
{
  "base_commit": "abc1234",
  "commits": [
    {
      "task_id": "task-001",
      "title": "Create user model and migration",
      "commit": "def5678",
      "message": "ralph: task-001 - Create user model and migration",
      "created_at": "2026-01-27T13:10:00Z"
    }
  ]
}
```

### Failure Handling

If the commit fails, treat it as a task failure:
- Mark task as failed
- Log the error to `.ralph/logs/errors.log`
- Stop execution

---

## Execution Summary

**After all tasks complete successfully, display a summary and write detailed logs.**

### Summary Display Format

When execution completes, show this summary to the user:

```
✓ EXECUTION COMPLETE

Tasks: [completed] completed, [failed] failed
Files modified:
  - [file1.ext]
  - [file2.ext]
  - [file3.ext]
Commits:
  - [task-id]: [commit hash]

Detailed log: .ralph/logs/execution.log

Next: Run ralph-retro skill to review commits
```

### Example Summary Output

```
✓ EXECUTION COMPLETE

Tasks: 5 completed, 0 failed
Files modified:
  - src/models/user.ts
  - src/models/product.ts
  - src/controllers/user.ts
  - src/routes/api.ts
  - tests/user.test.ts
Commits:
  - task-001: def5678
  - task-002: a1b2c3d

Detailed log: .ralph/logs/execution.log

Next: Run ralph-retro skill to review commits
```

### Collecting Summary Data

During execution, track:

1. **Task counts**: Increment completed/failed counters as tasks finish
2. **Files modified**: Aggregate from each task's result (files_modified list)
3. **Timestamps**: Track start and end time for duration calculation

### Execution Log Format

Write detailed execution log to `.ralph/logs/execution.log`:

```
================================================================================
RALPH EXECUTION LOG
================================================================================
Started: [ISO 8601 timestamp]
Completed: [ISO 8601 timestamp]
Duration: [X minutes Y seconds]
Original Request: [from state.json original_request]

================================================================================
SUMMARY
================================================================================
Total Tasks: [total count]
Completed: [completed count]
Failed: [failed count]
Final Phase: completed

================================================================================
FILES MODIFIED
================================================================================
[sorted list of all unique files modified across all tasks]
- src/models/user.ts
- src/models/product.ts
- ...

================================================================================
TASK EXECUTION DETAILS
================================================================================

--- Task: task-001 ---
Title: [task title]
Status: completed
Started: [timestamp]
Completed: [timestamp]
Commit: [commit hash]
Files Changed:
  - [file1]: [brief description]
  - [file2]: [brief description]
Acceptance Criteria:
  ✓ Criterion 1
  ✓ Criterion 2

--- Task: task-002 ---
Title: [task title]
...

================================================================================
END OF EXECUTION LOG
================================================================================
```

### Log File Creation

1. Create `.ralph/logs/` directory if it doesn't exist
2. Write execution.log with UTF-8 encoding
3. If file exists from previous run, overwrite it (each execution gets fresh log)

### State Update on Completion

Update state.json when execution completes:

```json
{
  "phase": "completed",
  "updated_at": "[ISO 8601 timestamp]",
  "execution_summary": {
    "started_at": "[ISO 8601 timestamp]",
    "completed_at": "[ISO 8601 timestamp]",
    "total_tasks": 5,
    "completed_tasks": 5,
    "failed_tasks": 0,
    "files_modified": ["src/file1.ts", "src/file2.ts"],
    "commits": [
      {"task_id": "task-001", "commit": "def5678"},
      {"task_id": "task-002", "commit": "a1b2c3d"}
    ]
  }
}
```

### Implementation Notes

1. **Aggregate files**: Collect files_modified from each task result file in `.ralph/results/`
2. **Deduplicate files**: Same file may be modified by multiple tasks - list unique files only
3. **Sort files**: Display files in alphabetical order for easier scanning
4. **Handle empty list**: If no files modified, show "No files modified"
5. **Aggregate commits**: Pull commit hashes from `.ralph/commits.json`

---

## Fail-Fast Behavior

**CRITICAL: On ANY task failure, ALL execution stops immediately.**

This is non-negotiable. Do not:
- Continue to next task
- Attempt to "recover" or "work around" the failure
- Queue up remaining tasks

### Why Fail-Fast?

1. Dependent tasks will likely fail anyway
2. User needs to review and fix the issue
3. Continuing wastes resources on doomed work
4. State consistency is easier to maintain

### Failure Detection

A task is considered "failed" if:
- The worker session explicitly reports failure
- The worker session throws an error
- The worker session reports acceptance criteria not met
- The Codex worker session returns an error

---

## Error Handling

### Task Failure

If a worker session reports failure or throws an error:

1. **STOP immediately** - do not spawn any more tasks
2. **Mark task as failed** in state.json
3. **Create logs directory** if it doesn't exist: `.ralph/logs/`
4. **Log details** to `.ralph/logs/errors.log`:
   ```
   ================================================================================
   TASK FAILED
   ================================================================================
   Timestamp: [ISO 8601 timestamp]
   Task ID: [task-id]
   Task Title: [task title]

   Error Summary:
   [brief error message - first line or summary]

   Full Error Details:
   [complete error message from worker session]

   Files Involved:
   [list of files_to_modify from task]

   Acceptance Criteria (what was expected):
   [list all acceptance criteria from task]
   ================================================================================
   ```
5. **Update state.json** with last_failure object:
   ```json
   {
     "phase": "failed",
     "task_statuses": {
       "[failed-task-id]": "failed"
     },
     "last_failure": {
       "task_id": "[task-id]",
       "task_title": "[task title]",
       "error_message": "[brief error summary]",
       "failed_at": "[ISO 8601 timestamp]",
       "log_file": ".ralph/logs/errors.log"
     },
     "updated_at": "[timestamp]"
   }
   ```
6. **Report to user** with this exact format:
   ```
   ✗ EXECUTION STOPPED - Task Failed

   Task: [task-id] - [task title]
   Error: [brief error message]

   Details logged to: .ralph/logs/errors.log

   To resume after fixing:
   1. Review the error in .ralph/logs/errors.log
   2. Fix the issue in your code
   3. Run ralph-start skill to continue from failed task
   ```

### Missing State

If state.json or task files are missing:
```
Error: Ralph state not found.
Run ralph skill first to create a plan.
```

### Invalid Phase

If phase is not `planning_complete` or `executing`:
```
Error: Cannot start execution.
Current phase: [phase]
Expected: planning_complete or executing

If phase is 'completed': All tasks already done.
If phase is 'failed': Fix the failed task, then run ralph-start skill to resume.
```

---

## Directory Structure Expected

```
.ralph/
├── state.json              # Must exist with phase: planning_complete
├── tasks/
│   ├── task-001.json       # At least one task file
│   ├── task-002.json
│   └── ...
├── commits.json            # Created during execution
├── results/                # Created during execution
│   ├── task-001.md
│   └── ...
└── logs/                   # Created during execution
    ├── execution.log
    └── errors.log
```

---

## Notes

- This command is designed to run after start a new Codex session for fresh context
- Each worker session starts with clean context and only task-specific information
- Sequential execution ensures clean, reviewable commits per task
- State is saved after each task for resumability
- On failure, fix the issue and re-run ralph-start skill to continue
- Results in .ralph/results/ provide detailed execution logs
