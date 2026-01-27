# Ralph - Task Orchestrator

This command will be implemented in US-009.

Usage: /ralph <task description>

Orchestrates research, decisions, and planning for your task.

---

## Utility: Project Root Detection

Ralph needs to find the project root to store state files consistently in `.ralph/` directory.

### Detection Logic

Search upward from the current working directory for these project markers (in order):
1. `.git` - Git repository root
2. `package.json` - Node.js/JavaScript project
3. `Cargo.toml` - Rust project
4. `go.mod` - Go module
5. `pyproject.toml` - Python project
6. `mix.exs` - Elixir/Phoenix project

### Algorithm

```
function detectProjectRoot():
    current_dir = getcwd()

    while current_dir != "/":
        for marker in [".git", "package.json", "Cargo.toml", "go.mod", "pyproject.toml", "mix.exs"]:
            if exists(current_dir + "/" + marker):
                return current_dir  # Found project root
        current_dir = parent(current_dir)

    return ERROR: "No project root found. Please run Ralph from within a project directory."
```

### Implementation Instructions

When implementing the /ralph command, use the Bash tool to detect project root:

```bash
# Find project root by searching for markers
PROJECT_ROOT=""
CURRENT="$(pwd)"
MARKERS=(".git" "package.json" "Cargo.toml" "go.mod" "pyproject.toml" "mix.exs")

while [ "$CURRENT" != "/" ]; do
    for marker in "${MARKERS[@]}"; do
        if [ -e "$CURRENT/$marker" ]; then
            PROJECT_ROOT="$CURRENT"
            break 2
        fi
    done
    CURRENT="$(dirname "$CURRENT")"
done

if [ -z "$PROJECT_ROOT" ]; then
    echo "ERROR: No project root found"
    exit 1
fi

echo "$PROJECT_ROOT"
```

### Return Values

- **Success**: Returns absolute path to the project root (e.g., `/home/user/myproject`)
- **Failure**: Returns error message: "No project root found. Please run Ralph from within a project directory."

### Notes

- The search stops at the first marker found (closest to current directory)
- The `.git` marker is checked first as it's the most common project identifier
- All state files will be stored in `{PROJECT_ROOT}/.ralph/`

---

## State Management: state.json

Ralph maintains persistent state in `.ralph/state.json` to track progress across sessions and enable resumable execution.

### Directory Structure

```
{PROJECT_ROOT}/
└── .ralph/
    ├── state.json          # Main state file
    ├── research.json       # Research findings (if complex task)
    ├── decisions.json      # User decisions
    ├── prd.md              # Generated PRD document
    ├── tasks/              # Individual task files
    │   ├── task-001.json
    │   ├── task-002.json
    │   └── ...
    ├── results/            # Task execution results
    │   └── ...
    └── logs/               # Execution logs
        ├── execution.log
        └── errors.log
```

### state.json Schema

```json
{
  "version": "1.0",
  "created_at": "2026-01-27T12:34:56Z",
  "updated_at": "2026-01-27T12:45:00Z",
  "phase": "planning",
  "original_request": "Build a REST API for user management",
  "task_order": ["task-001", "task-002", "task-003"],
  "task_statuses": {
    "task-001": "completed",
    "task-002": "in_progress",
    "task-003": "pending"
  },
  "last_failure": null
}
```

### Field Definitions

| Field | Type | Description |
|-------|------|-------------|
| `version` | string | Schema version for future compatibility |
| `created_at` | string | ISO 8601 timestamp when state was created |
| `updated_at` | string | ISO 8601 timestamp of last state update |
| `phase` | string | Current workflow phase (see Phase Values) |
| `original_request` | string | The user's original task description |
| `task_order` | array | Ordered list of task IDs for execution |
| `task_statuses` | object | Map of task ID to status (see Task Status Values) |
| `last_failure` | object\|null | Details of the most recent failure, if any |

### Phase Values

| Phase | Description |
|-------|-------------|
| `research` | Gathering technical specs, best practices via web search |
| `decisions` | Surfacing and resolving critical decisions with user |
| `planning` | Generating PRD and discrete task files |
| `planning_complete` | Plan ready for user review (run /ralph-start after /clear) |
| `executing` | Tasks are being executed via subagents |
| `completed` | All tasks finished successfully |
| `failed` | Execution stopped due to a task failure |

### Task Status Values

| Status | Description |
|--------|-------------|
| `pending` | Task not yet started |
| `in_progress` | Task currently being executed by a subagent |
| `completed` | Task finished successfully |
| `failed` | Task execution failed |

### last_failure Object

When a task fails, `last_failure` contains error details:

```json
{
  "last_failure": {
    "task_id": "task-002",
    "task_title": "Create API endpoint",
    "error_message": "Test assertions failed: expected 200 OK, got 404",
    "failed_at": "2026-01-27T12:50:00Z",
    "log_file": ".ralph/logs/errors.log"
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `task_id` | string | ID of the failed task |
| `task_title` | string | Human-readable task title |
| `error_message` | string | Description of what went wrong |
| `failed_at` | string | ISO 8601 timestamp of failure |
| `log_file` | string | Path to detailed error log |

### Initialization

When `/ralph` is invoked, create the state file if it doesn't exist:

```json
{
  "version": "1.0",
  "created_at": "<current ISO 8601 timestamp>",
  "updated_at": "<current ISO 8601 timestamp>",
  "phase": "research",
  "original_request": "<user's task description>",
  "task_order": [],
  "task_statuses": {},
  "last_failure": null
}
```

### State Transitions

```
/ralph invoked
    ↓
[research] → (complex tasks: web search for specs/best practices)
    ↓
[decisions] → (surface critical decisions, wait for user input)
    ↓
[planning] → (generate PRD and task files)
    ↓
[planning_complete] → (user reviews, runs /clear, then /ralph-start)
    ↓
/ralph-start invoked
    ↓
[executing] → (subagents execute tasks)
    ↓
[completed] or [failed]
```

### Usage in Commands

**Reading state:**
```bash
cat .ralph/state.json | jq '.phase'
```

**Updating state (example - update phase):**
The agent should read the current state, modify the necessary fields, and write the complete updated state back to the file.

### Notes

- Always update `updated_at` when modifying state
- The `task_order` array determines execution sequence and parallel grouping
- Tasks with no dependencies can run in parallel (handled by /ralph-start)
- On failure, execution halts immediately and `phase` becomes `failed`
