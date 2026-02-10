---
name: ralph-retro
description: Review Ralph execution commits, collect feedback, and generate follow-up tasks.
---

# Codex Runtime Mapping

- This is a Codex skill adaptation of the original Claude command flow.
- Replace Claude `Task` tool usage with fresh Codex worker sessions (subagents), for example separate `codex exec` runs or equivalent isolated task execution in your runtime.
- Replace `AskUserQuestion` tool calls with direct user prompts in chat.
- Replace slash-command assumptions with skill invocations by name.

---

### Codex CLI Subagent Pattern (Optional)

If you choose to offload any review or summarization step to a worker session, run it as a fresh, isolated `codex exec` process to avoid context carryover.

Guidelines:
- Start a new `codex exec` invocation per worker session (no shared context).
- Provide only the assembled prompt for that worker session.
- Capture stdout as the worker session response.
- Treat non-zero exit codes as failure.
- Run one worker session at a time; do not parallelize.

# Ralph Retro - Review Commits

You are Ralph's retro review assistant. Your job is to review the commits produced by `ralph-start` skill, gather feedback, and update Ralph metadata so `ralph-start` skill can apply follow-up changes.

## Pre-Retro Checks

Before starting, verify the following:

1. **Check for .ralph/ directory**: Must exist in project root
2. **Read state.json**: Phase should be `completed` or `failed` (warn if not)
3. **Verify git repository**: Must be inside a git repo
4. **Verify clean working tree**: `git status --porcelain` must be empty
5. **Verify commits.json**: `.ralph/commits.json` must exist

If any check fails, report the error and stop.

---

## Retro Workflow

### Step 1: Load Context

Load:
- `.ralph/state.json`
- `.ralph/commits.json`
- `.ralph/prd.md`
- `.ralph/decisions.json`
- `.ralph/tasks/` (task specs)
- `.ralph/results/` (task results)
- `.ralph/retro/feedback.json` (if exists)

### Step 2: Select Commits to Review

1. Read commits from `.ralph/commits.json`
2. If `.ralph/retro/feedback.json` exists, skip commits already reviewed
3. Review remaining commits in the order they appear in `commits.json`

### Step 3: Commit-by-Commit Review

For each commit:

1. **Show the diff**
   - Use `git show <commit>` to display the full diff
   - This shows the user exactly what code changed without needing to dig into files
2. **Summarize what changed**
   - Use `git show --stat <commit>` for a file-level summary
   - Reference the task description and acceptance criteria
   - Reference `.ralph/results/task-XXX.md`
3. **Explain why it changed**
   - Tie back to the task's goal and decisions made
4. **Explain how it works**
   - Provide a brief explanation of the implementation approach
5. **Ask for feedback**
   - Use the direct user prompt (or equivalent in your runtime)

Prompt format:
```
Commit: [hash]
Task: [task-id] - [title]

What changed:
[brief summary]

Why it changed:
[brief reason]

How it works:
[brief explanation]

Are you happy with this commit?
1. Yes, looks good
2. I have questions
3. I want changes
```

### Step 4: Collect Feedback

Record each response in `.ralph/retro/feedback.json`:

```json
{
  "reviewed_at": "2026-02-03T12:00:00Z",
  "commits": [
    {
      "commit": "def5678",
      "task_id": "task-001",
      "title": "Create user model and migration",
      "status": "accepted | questions | changes_requested",
      "questions": ["..."],
      "change_requests": ["..."]
    }
  ]
}
```

---

## Follow-up Changes

After reviewing all commits:

1. Summarize all questions and change requests
2. Answer questions in a short, direct discussion
3. Convert change requests into new tasks

### Create Retro Tasks

For each change request:

1. Create a new task file in `.ralph/tasks/` with a new ID
2. Set `priority` based on urgency (default to 2)
3. Add dependencies if the change relies on earlier tasks
4. Add acceptance criteria that verify the requested change

Update metadata:

- Append a **Retro Updates** section to `.ralph/prd.md`
- Update `.ralph/decisions.json` if any decisions changed
- Update `.ralph/state.json`:
  - Set `phase` to `planning_complete`
  - Update `task_order` (dependencies, then priority)
  - Add new tasks to `task_statuses` as `pending`

### Ask for Confirmation to Execute Retro Tasks

After updating metadata, instruct the user:
```
Retro updates prepared.
Run ralph-start skill to apply the new tasks.
```

---

## Repeat Review

After `ralph-start` skill runs and creates new commits:

1. Re-run `ralph-retro` skill
2. It should only review commits not listed in `.ralph/retro/feedback.json`
3. Repeat the review process until no new commits remain

---

## Notes

- Retro does not modify code directly
- Retro only updates metadata and plans
- All follow-up changes are applied by `ralph-start` skill
