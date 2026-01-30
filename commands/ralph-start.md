# Ralph Start - Execute Tasks

You are Ralph's execution engine. Your job is to execute the planned tasks from `.ralph/` directory using subagents for parallel execution with fresh context.

## Pre-Execution Checks

Before executing, verify the following:

1. **Check for .ralph/ directory**: Must exist in project root
2. **Read state.json**: Verify phase is `planning_complete` or `executing`
3. **Read task files**: Load all tasks from `.ralph/tasks/`
4. **Verify tasks exist**: At least one task file must be present

If any check fails, report the error and stop.

---

## Execution Workflow

### Step 1: Load State and Tasks

1. Read `.ralph/state.json`
2. Read all task files from `.ralph/tasks/` directory
3. Build execution plan from `task_order` in state.json
4. Identify current progress from `task_statuses`

### Step 2: Update State to Executing

Update state.json:
- Set `phase` to `executing`
- Set `updated_at` to current timestamp

### Step 3: Execute by Parallel Groups

Process tasks by their `parallel_group` number, starting from the lowest group that has pending tasks:

```
For each parallel_group (1, 2, 3, ...):
    1. Find all tasks in this group that are:
       - Status is "pending"
       - All dependencies have status "completed"

    2. If no eligible tasks in this group, move to next group

    3. Spawn ALL eligible tasks in parallel:
       - Use MULTIPLE Task tool calls in a SINGLE message
       - Each subagent gets the task's context and instructions

    4. Wait for ALL spawned tasks to complete

    5. Check results - process ALL returned tasks:

       For each completed task:
         - Update task status to "completed" in state.json
         - Save result to .ralph/results/task-NNN.md
         - Show: "✓ Completed: [task-id] - [title]"

       If ANY task failed:
         - FAIL-FAST: Stop processing immediately
         - Update failed task status to "failed" in state.json
         - Log error to .ralph/logs/errors.log (see Error Handling)
         - Set phase to "failed" in state.json
         - Set last_failure object in state.json
         - Report failure with task ID, error, and log file path
         - EXIT - do NOT continue to next group or task

    6. Only if ALL tasks in group succeeded, move to next parallel_group
```

**IMPORTANT**: If parallel tasks are running and one fails, you must still wait for all spawned tasks to return (they're already running). Process their results, but do NOT spawn any new tasks after detecting a failure.

### Step 4: Completion

When all tasks complete successfully:
1. Update state.json phase to `completed`
2. Write detailed execution log to `.ralph/logs/execution.log`
3. Display execution summary to user (see Execution Summary section below)

---

## Spawning Subagents

For each task, spawn a subagent using the Task tool with this configuration:

```
Task tool parameters:
  description: "[task-id]: [short title]"
  subagent_type: "general-purpose"
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

---

## Parallel Execution Rules

### Spawning Parallel Tasks

To spawn multiple tasks in parallel, include multiple Task tool calls in a SINGLE message:

```
[In one message, call Task tool for task-001]
[In same message, call Task tool for task-002]
[In same message, call Task tool for task-003]
```

This spawns all three subagents simultaneously.

### When to Parallelize

Tasks can run in parallel if:
1. They have the same `parallel_group` number
2. All their dependencies are completed
3. All are currently in `pending` status

### Wait Behavior

After spawning parallel tasks:
1. Wait for ALL spawned tasks to return
2. Process results from each
3. Update statuses for all before proceeding to next group

---

## Resumption Logic

If `phase` is already `executing` (interrupted run), resume as follows:

1. Skip tasks with status `completed`
2. Retry tasks with status `in_progress` (may have been interrupted)
3. Continue with tasks with status `pending`

For `in_progress` tasks:
- Check if the task was actually completed by examining .ralph/results/
- If result file exists and looks complete, mark as completed
- Otherwise, re-execute the task

---

## State Updates

### Before Each Task Group

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
- Subagent reasoning
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

Group 1:
  → Starting: task-001 - Create user model
  → Starting: task-002 - Create product model
  ✓ Completed: task-001 - Create user model
  ✓ Completed: task-002 - Create product model

Group 2:
  → Starting: task-003 - Create user controller
  ✓ Completed: task-003 - Create user controller

Group 3:
  → Starting: task-004 - Add validation logic
  → Starting: task-005 - Create API endpoint
  ✗ Failed: task-004 - Add validation logic
    Error: Type mismatch in validation function

✗ EXECUTION STOPPED - Task Failed
...
```

### Verbosity Rules

| DO show | Do NOT show |
|---------|-------------|
| Task ID and title | Implementation code |
| Brief completion status | Subagent reasoning |
| One-line error summary | Full stack traces (put in logs) |
| Group progress | "I'm going to..." preambles |
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
| File diffs | .ralph/results/ |
| Test output | .ralph/results/ |
| Error stack traces | .ralph/logs/errors.log |
| Completion message | Console (brief) |
| Criteria verification | .ralph/results/ |

### Subagent Instructions for Results

When spawning subagents, instruct them to:
1. **Do NOT** print lengthy implementation details to the user
2. **DO** return a structured result that will be saved to results/
3. Focus output on confirmation that acceptance criteria were met

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

Detailed log: .ralph/logs/execution.log
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

Detailed log: .ralph/logs/execution.log
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
    "files_modified": ["src/file1.ts", "src/file2.ts"]
  }
}
```

### Implementation Notes

1. **Aggregate files**: Collect files_modified from each task result file in `.ralph/results/`
2. **Deduplicate files**: Same file may be modified by multiple tasks - list unique files only
3. **Sort files**: Display files in alphabetical order for easier scanning
4. **Handle empty list**: If no files modified, show "No files modified"

---

## Fail-Fast Behavior

**CRITICAL: On ANY task failure, ALL execution stops immediately.**

This is non-negotiable. Do not:
- Continue to next task
- Continue to next parallel group
- Attempt to "recover" or "work around" the failure
- Queue up remaining tasks

### Why Fail-Fast?

1. Dependent tasks will likely fail anyway
2. User needs to review and fix the issue
3. Continuing wastes resources on doomed work
4. State consistency is easier to maintain

### Failure Detection

A task is considered "failed" if:
- The subagent explicitly reports failure
- The subagent throws an error
- The subagent reports acceptance criteria not met
- The Task tool returns an error

---

## Error Handling

### Task Failure

If a subagent reports failure or throws an error:

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
   [complete error message from subagent]

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
   3. Run /ralph-start to continue from failed task
   ```

### Missing State

If state.json or task files are missing:
```
Error: Ralph state not found.
Run /ralph first to create a plan.
```

### Invalid Phase

If phase is not `planning_complete` or `executing`:
```
Error: Cannot start execution.
Current phase: [phase]
Expected: planning_complete or executing

If phase is 'completed': All tasks already done.
If phase is 'failed': Fix the failed task, then run /ralph-start to resume.
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
├── results/                # Created during execution
│   ├── task-001.md
│   └── ...
└── logs/                   # Created during execution
    ├── execution.log
    └── errors.log
```

---

## Notes

- This command is designed to run after /clear for fresh context
- Each subagent starts with clean context and only task-specific information
- Parallel execution significantly speeds up multi-task plans
- State is saved after each task for resumability
- On failure, fix the issue and re-run /ralph-start to continue
- Results in .ralph/results/ provide detailed execution logs
