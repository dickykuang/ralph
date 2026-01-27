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

    5. For each completed task:
       - Update task status to "completed" in state.json
       - Save result to .ralph/results/task-NNN.md
       - Show: "✓ Completed: [task-id] - [title]"

    6. If ANY task fails:
       - Update task status to "failed" in state.json
       - Log error to .ralph/logs/errors.log
       - Set phase to "failed" in state.json
       - STOP ALL EXECUTION IMMEDIATELY
       - Report failure details and exit

    7. Move to next parallel_group
```

### Step 4: Completion

When all tasks complete successfully:
- Update state.json phase to `completed`
- Display summary (handled by subsequent story)

---

## Spawning Subagents

For each task, spawn a subagent using the Task tool with this configuration:

```
Task tool parameters:
  description: "[task-id]: [short title]"
  subagent_type: "general-purpose"
  prompt: |
    Execute this task from the Ralph plan:

    TASK ID: [task.id]
    TITLE: [task.title]

    DESCRIPTION:
    [task.description]

    ACCEPTANCE CRITERIA:
    [Each criterion as a bullet point]

    FILES TO MODIFY:
    [Each file path as a bullet point]

    CONTEXT:
    [task.context if present, or "No additional context"]

    DECISIONS MADE:
    [Relevant decisions from decisions.json, if task.context.decisions_refs exists]

    ---

    Instructions:
    1. Implement the task following the description
    2. Ensure ALL acceptance criteria are met
    3. Only modify the files listed (or closely related files if necessary)
    4. Run relevant tests if applicable
    5. Report what was done and any issues encountered

    When complete, confirm each acceptance criterion was met.
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

Show brief status updates as tasks execute:

```
Starting execution...
Phase: executing

Group 1:
  → Starting: task-001 - Create user model
  → Starting: task-002 - Create product model
  ✓ Completed: task-001 - Create user model
  ✓ Completed: task-002 - Create product model

Group 2:
  → Starting: task-003 - Create user controller
  ✓ Completed: task-003 - Create user controller

...
```

Keep output minimal - no lengthy explanations.

---

## Error Handling

### Task Failure

If a subagent reports failure or throws an error:

1. **Mark task as failed** in state.json
2. **Log details** to .ralph/logs/errors.log:
   ```
   [timestamp] TASK FAILED: [task-id]
   Title: [task title]
   Error: [error message]
   ---
   [full error details]
   ```
3. **Update state.json** with last_failure object
4. **STOP immediately** - do not continue to next task or group
5. **Report to user**:
   ```
   ✗ Task failed: [task-id] - [title]
   Error: [brief error message]

   See .ralph/logs/errors.log for details.
   Fix the issue and run /ralph-start to resume.
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
