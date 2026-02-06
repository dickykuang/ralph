---
name: ralph
description: Orchestrate code context analysis, research, decisions, and planning into .ralph state files for later execution.
---

# Codex Runtime Mapping

- This is a Codex skill adaptation of the original Claude command flow.
- Replace Claude `Task` tool usage with fresh Codex worker sessions (for example, separate `codex exec` runs or equivalent isolated task execution in your runtime).
- Replace `AskUserQuestion` tool calls with direct user prompts in chat.
- Replace slash-command assumptions with skill invocations by name.

---

# Ralph - Task Orchestrator

You are Ralph, an intelligent task orchestrator. Your job is to take the user's task and orchestrate code context analysis, research, decisions, and planning to prepare for autonomous execution.

## Arguments

**Task Description:** $ARGUMENTS

If `$ARGUMENTS` is empty, ask the user what they want to accomplish.

---

## Orchestration Workflow

Execute these phases in order, updating state.json at each transition:

### Phase 0: Initialization

1. **Detect project root** using the algorithm in "Utility: Project Root Detection" section
2. **Archive existing Ralph state** if prior metadata exists (see "Utility: Archive Previous Run")
3. **Create `.ralph/` directory** if it doesn't exist
4. **Initialize state.json** with the template from "State Management: state.json" section
5. **Save the original request** to state.json `original_request` field

### Phase 1: Complexity Assessment

1. **Assess complexity** using the criteria in "Complexity Assessment" section
2. **Store result** in state.json as `complexity` field ("simple" or "complex")
3. **Branch workflow** based on complexity:
   - **Simple**: Skip external research after code context analysis and continue to decisions
   - **Complex**: Run code context analysis, then proceed to research phase

### Phase 2: Code Context Analysis (All Tasks)

Run this phase for both simple and complex tasks:

1. **Update state.json**: Set `phase` to "code_context"
2. **Analyze local codebase**: Identify relevant entry points, modules, call paths, and boundaries
3. **Trace data flow**: Document what data is passed through key functions, where it is validated/transformed, and where it is persisted/emitted
4. **Save results** to `.ralph/code_context.json`

### Phase 3: Research (Complex Tasks Only)

Only run this phase if complexity is "complex":

1. **Update state.json**: Set `phase` to "research"
2. **Spawn research worker session** using a Codex worker session with the prompt template from "Research Phase" section
3. **Save results** to `.ralph/research.json`
4. **Handle failures gracefully**: If research fails, create empty research.json and proceed

### Phase 4: Decision Surfacing

1. **Update state.json**: Set `phase` to "decisions"
2. **Load code_context.json and research.json** (if exists) to identify decision points
3. **For each decision**:
   - Present using the format from "Decision Surfacing Phase" section
   - Wait for user response (number, question, or custom answer)
   - Answer follow-up questions if asked
   - Record the decision
4. **Save decisions** to `.ralph/decisions.json`
5. **Verify**: All critical decisions (architecture, security) must be resolved before proceeding

### Phase 5: Planning

1. **Update state.json**: Set `phase` to "planning"
2. **Load code_context.json, research.json, and decisions.json** as context
3. **Generate PRD document** following "Planning Phase" section structure
4. **Create task files** in `.ralph/tasks/` directory:
   - Each task has: id, title, description, acceptance_criteria, dependencies, priority, files_to_modify
   - Tasks sized for single-session completion
   - Priorities assigned based on risk, dependencies, and sequencing needs
5. **Update state.json**:
   - Populate `task_order` with ordered list of task IDs (dependencies first, then priority)
   - Populate `task_statuses` with all tasks set to "pending"
   - Set `phase` to "planning_complete"

### Phase 6: Completion

After planning is complete:

1. **Display summary**:
   ```
   ✓ Planning complete!

   Plan saved to: .ralph/prd.md
   Tasks created: [count] tasks in .ralph/tasks/

   Next steps:
   1. Review the plan: .ralph/prd.md
   2. Run start a new Codex session to reset context
   3. Run ralph-start skill to begin execution
   ```

2. **STOP HERE** - Do not proceed to execution. The user must:
   - Review the generated plan
   - Run `start a new Codex session` to get fresh context
   - Run `ralph-start` skill to execute with worker sessions

---

## State Transitions Summary

```
ralph skill invoked with task
    ↓
[Initialize] → Create .ralph/ and state.json
    ↓
[Assess Complexity] → Determine simple vs complex
    ↓
[Code Context] → (all tasks) Analyze local code paths and data flow
    ↓
[Research] → (complex only) Web search for specs/practices
    ↓
[Decisions] → Surface and resolve critical decisions
    ↓
[Planning] → Generate PRD and task files
    ↓
[planning_complete] → STOP, inform user to run start a new Codex session then ralph-start skill
```

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

When implementing the ralph skill command, use the Bash tool to detect project root:

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

## Utility: Archive Previous Run

If a prior Ralph run exists in the project, archive it before creating new state. This prevents overwriting prior plans and enables retro review.

### When to Archive

Archive if any of these exist in `{PROJECT_ROOT}/.ralph/`:
- `state.json`
- `prd.md`
- `decisions.json`
- `research.json`
- `code_context.json`
- `tasks/`
- `results/`
- `logs/`

### Archive Destination

Create:
```
{PROJECT_ROOT}/.ralph/archive/{timestamp}-{slug}/
```

- `timestamp`: current ISO 8601 datetime in UTC, `YYYYMMDD-HHMMSSZ`
- `slug`: derived from the previous run's `original_request` in `state.json` if available, otherwise `previous-run`

### What to Move

Move the following into the archive directory if they exist:
- `state.json`
- `prd.md`
- `decisions.json`
- `research.json`
- `code_context.json`
- `tasks/`
- `results/`
- `logs/`
- `commits.json` (if present)
- `retro/` (if present)

Do NOT move the `archive/` directory itself.

### Notes

- Archiving should be fast and non-destructive.
- If `state.json` is missing, use `previous-run` as the slug.

---

## State Management: state.json

Ralph maintains persistent state in `.ralph/state.json` to track progress across sessions and enable resumable execution.

### Directory Structure

```
{PROJECT_ROOT}/
└── .ralph/
    ├── state.json          # Main state file
    ├── code_context.json   # Local code path and data flow analysis (all tasks)
    ├── research.json       # Research findings (if complex task)
    ├── decisions.json      # User decisions
    ├── prd.md              # Generated PRD document
    ├── commits.json        # Task-to-commit mapping (created during execution)
    ├── tasks/              # Individual task files
    │   ├── task-001.json
    │   ├── task-002.json
    │   └── ...
    ├── results/            # Task execution results
    │   └── ...
    ├── logs/               # Execution logs
    │   ├── execution.log
    │   └── errors.log
    ├── retro/              # Retro review data
    └── archive/            # Archived prior runs
```

### state.json Schema

```json
{
  "version": "1.0",
  "created_at": "2026-01-27T12:34:56Z",
  "updated_at": "2026-01-27T12:45:00Z",
  "phase": "planning",
  "complexity": "complex",
  "original_request": "Build a REST API for user management",
  "base_commit": "abc1234",
  "task_order": ["task-001", "task-002", "task-003"],
  "task_statuses": {
    "task-001": "completed",
    "task-002": "in_progress",
    "task-003": "pending"
  },
  "last_failure": null,
  "execution_summary": null
}
```

### Field Definitions

| Field | Type | Description |
|-------|------|-------------|
| `version` | string | Schema version for future compatibility |
| `created_at` | string | ISO 8601 timestamp when state was created |
| `updated_at` | string | ISO 8601 timestamp of last state update |
| `phase` | string | Current workflow phase (see Phase Values) |
| `complexity` | string | Task complexity classification (`simple` or `complex`) |
| `original_request` | string | The user's original task description |
| `base_commit` | string\|null | Git commit hash at start of execution |
| `task_order` | array | Ordered list of task IDs for execution (dependencies, then priority) |
| `task_statuses` | object | Map of task ID to status (see Task Status Values) |
| `last_failure` | object\|null | Details of the most recent failure, if any |
| `execution_summary` | object\|null | Execution summary data (set on completion) |

### Phase Values

| Phase | Description |
|-------|-------------|
| `complexity_assessment` | Classifying task as `simple` or `complex` |
| `code_context` | Analyzing local code paths, function interactions, and data flow |
| `research` | Gathering technical specs, best practices via web search |
| `decisions` | Surfacing and resolving critical decisions with user |
| `planning` | Generating PRD and discrete task files |
| `planning_complete` | Plan ready for user review (run ralph-start skill after start a new Codex session) |
| `executing` | Tasks are being executed via worker sessions |
| `completed` | All tasks finished successfully |
| `failed` | Execution stopped due to a task failure |

### Task Status Values

| Status | Description |
|--------|-------------|
| `pending` | Task not yet started |
| `in_progress` | Task currently being executed by a worker session |
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

When `ralph` skill is invoked, create the state file if it doesn't exist:

```json
{
  "version": "1.0",
  "created_at": "<current ISO 8601 timestamp>",
  "updated_at": "<current ISO 8601 timestamp>",
  "phase": "complexity_assessment",
  "complexity": null,
  "original_request": "<user's task description>",
  "base_commit": null,
  "task_order": [],
  "task_statuses": {},
  "last_failure": null,
  "execution_summary": null
}
```

### State Transitions

```
ralph skill invoked
    ↓
[complexity_assessment] → (classify simple vs complex)
    ↓
[code_context] → (all tasks: trace local code paths and data flow)
    ↓
[research] → (complex tasks only: web search for specs/best practices)
    ↓
[decisions] → (surface critical decisions, wait for user input)
    ↓
[planning] → (generate PRD and task files)
    ↓
[planning_complete] → (user reviews, runs start a new Codex session, then ralph-start skill)
    ↓
ralph-start skill invoked
    ↓
[executing] → (worker sessions execute tasks)
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
- The `task_order` array determines execution sequence
- Tasks execute sequentially based on dependencies and priority (handled by ralph-start skill)
- On failure, execution halts immediately and `phase` becomes `failed`

---

## Complexity Assessment

Ralph assesses task complexity to determine whether external research is needed. All tasks still run code context analysis to understand local implementation and data flow.

### Complexity Levels

| Level | Description | Workflow |
|-------|-------------|----------|
| `simple` | Straightforward, well-defined tasks | Code Context Analysis → Skip External Research → Decisions/Planning → Execution |
| `complex` | Multi-faceted tasks requiring research | Code Context Analysis → Research → Decisions → Planning → Execution |

### Simple Task Criteria

A task is considered **simple** if it meets ALL of these conditions:

1. **Single File Scope**: Affects only one file or a small, well-defined set of files
2. **Clear Implementation**: No ambiguity about how to accomplish it
3. **Familiar Technology**: Uses existing patterns/tech already in the codebase
4. **Low Risk**: Unlikely to introduce bugs or break existing functionality
5. **No External Research Needed**: Standard coding task with known solution

#### Examples of Simple Tasks

- Fixing a typo in documentation or code
- Renaming a variable or function
- Adding a simple utility function with clear requirements
- Updating a configuration value
- Adding basic input validation to an existing form
- Writing a straightforward unit test for existing code
- Adding a new field to an existing data structure
- Fixing a lint warning or formatting issue

### Complex Task Criteria

A task is considered **complex** if it meets ANY of these conditions:

1. **Multi-File Changes**: Affects multiple files across different parts of the codebase
2. **New Feature**: Introduces new functionality that doesn't exist yet
3. **Unfamiliar Technology**: Requires using libraries, APIs, or patterns not already in the project
4. **Integration Work**: Connects multiple systems, services, or external APIs
5. **Architectural Decisions**: Requires choosing between different approaches
6. **Security Implications**: Touches authentication, authorization, or sensitive data
7. **Performance Critical**: Needs optimization or handles high-volume operations
8. **Ambiguous Requirements**: Multiple valid interpretations of what's needed

#### Examples of Complex Tasks

- Building a new REST API endpoint with database integration
- Implementing user authentication/authorization
- Adding a new third-party service integration
- Refactoring a module for better performance
- Implementing real-time features (WebSockets, SSE)
- Adding a new major feature to the application
- Database schema migrations
- Setting up CI/CD pipelines
- Implementing caching strategies

### Assessment Algorithm

```
function assessComplexity(task_description, codebase_context):
    # Check for complexity indicators in the task
    complexity_signals = 0

    # Signal 1: Multi-file indicators
    if mentions_multiple_files(task_description) OR
       mentions_system_wide_change(task_description):
        complexity_signals += 1

    # Signal 2: New feature indicators
    if contains_words(["new", "create", "build", "implement", "add feature"]):
        complexity_signals += 1

    # Signal 3: Integration indicators
    if contains_words(["integrate", "connect", "API", "third-party", "external"]):
        complexity_signals += 1

    # Signal 4: Technology indicators
    if mentions_unfamiliar_tech(task_description, codebase_context):
        complexity_signals += 1

    # Signal 5: Architectural indicators
    if contains_words(["architecture", "refactor", "redesign", "migrate"]):
        complexity_signals += 1

    # Signal 6: Security indicators
    if contains_words(["auth", "security", "permission", "encrypt", "token"]):
        complexity_signals += 1

    # Threshold: 2 or more signals = complex
    if complexity_signals >= 2:
        return "complex"
    else:
        return "simple"
```

### Decision Matrix

| Task Characteristic | Simple | Complex |
|---------------------|--------|---------|
| Files affected | 1-2 | 3+ |
| New dependencies | No | Yes |
| External APIs | No | Yes |
| Database changes | No/minor | Schema changes |
| Security impact | None | Any |
| External web research needed | No | Yes |
| User decisions needed | 0-1 | 2+ |

### Workflow Implications

#### For Simple Tasks

```
User invokes ralph skill "fix typo in README"
    ↓
Assess complexity → Simple
    ↓
Code context analysis phase (trace affected code and data flow)
    ↓
Skip decisions phase (or minimal)
    ↓
Generate lightweight plan
    ↓
[planning_complete]
```

#### For Complex Tasks

```
User invokes ralph skill "implement OAuth2 login"
    ↓
Assess complexity → Complex
    ↓
Code context analysis phase (trace existing auth/session flows)
    ↓
Research phase (specs, best practices, pitfalls)
    ↓
Decisions phase (which OAuth provider? session vs JWT?)
    ↓
Comprehensive planning with detailed tasks
    ↓
[planning_complete]
```

### Usage in ralph skill Command

When implementing the ralph skill command, assess complexity early:

1. Parse the user's task description
2. Run complexity assessment
3. Store result in state.json as `complexity` field
4. Branch workflow based on complexity level

### Notes

- When in doubt, classify as complex (research is valuable)
- User can override complexity assessment if they disagree
- Simple tasks still generate plans, just with less overhead
- Simple tasks skip only external/web research, not local code-context analysis
- Complexity is assessed once at the start, not re-evaluated mid-workflow

---

## Code Context Analysis Phase

For all tasks, Ralph performs local code context analysis before planning decisions. This phase maps how the existing implementation works, including function call paths and the data that moves through those paths.

### When Code Context Analysis Runs

Code context analysis runs **for every task** immediately after complexity assessment and before optional external research.

```
Complexity assessed
    ↓
[code_context] phase begins
    ↓
Inspect relevant files and modules in the repo
    ↓
Trace call paths and data flow through key functions
    ↓
Results saved to .ralph/code_context.json
    ↓
Simple: proceed to decisions
Complex: proceed to research
```

### Code Context Goals

This phase should answer:

1. Which files/modules are on the request's execution path
2. Which functions call which functions for the affected behavior
3. What input/output data moves through those functions
4. Where data is validated, transformed, and persisted or emitted
5. Which existing helpers/utilities should be reused

### Output Format: code_context.json

Save findings to `.ralph/code_context.json`:

```json
{
  "task": "add email validation to signup flow",
  "analyzed_at": "2026-02-06T12:00:00Z",
  "entry_points": ["src/routes/signup.ts:POST /signup"],
  "hot_paths": [
    {
      "path": "route -> controller -> service -> repository",
      "functions": [
        "signupRouteHandler",
        "createUserController",
        "createUserService",
        "insertUser"
      ]
    }
  ],
  "data_flows": [
    {
      "value": "email",
      "source": "req.body.email",
      "transforms": ["trim", "toLowerCase"],
      "validation": "emailSchema.parse",
      "sink": "users.email column"
    }
  ],
  "reuse_candidates": [
    "src/lib/validators/email.ts#validateEmail",
    "src/lib/normalizers/string.ts#normalizeEmail"
  ],
  "gaps_or_risks": [
    "No validation before createUserService in one alternate path"
  ]
}
```

### Implementation Instructions

When implementing the `ralph` skill command, run code context analysis as follows:

1. **Update state**: Set phase to `code_context`
2. **Identify scope**: Determine likely entry points and modules from the request
3. **Trace logic**: Follow key call chains for impacted behavior
4. **Trace data**: Record important values through function boundaries (source -> validation/transforms -> sink)
5. **Capture reuse**: Identify existing helpers/utilities to reuse
6. **Save output**: Write `.ralph/code_context.json`
7. **Branch next phase**:
   - `complex` -> `research`
   - `simple` -> `decisions`

### Notes

- This phase is mandatory even when external research is skipped
- Keep analysis focused on paths relevant to the user's request
- Reuse findings should feed directly into `reuse_notes` during planning

---

## Research Phase

For complex tasks, Ralph performs automated research to gather technical specifications, best practices, and common pitfalls before planning. This ensures the plan is informed by authoritative sources rather than relying solely on general knowledge.

### When Research Runs

Research runs **only for complex tasks** after code context analysis. Simple tasks skip external research and continue to decisions (or planning if no decisions are needed).

```
Complex task detected
    ↓
[research] phase begins
    ↓
Spawn research worker session with Codex worker session
    ↓
Worker Session performs web searches
    ↓
Results saved to .ralph/research.json
    ↓
State updated to [decisions] phase
```

### Research Goals

The research worker session gathers information in these categories:

| Category | Description | Examples |
|----------|-------------|----------|
| **Specifications** | Official specs, RFCs, documentation | OAuth 2.0 RFC, GraphQL spec, REST API guidelines |
| **Best Practices** | Industry-standard approaches | Error handling patterns, security best practices |
| **Common Pitfalls** | Known issues and anti-patterns | Race conditions, security vulnerabilities, performance traps |
| **References** | Authoritative sources for further reading | Official docs, trusted tutorials, GitHub repos |

### Spawning the Research Worker Session

Use the Codex worker session with `execution_mode: "general-purpose"` to spawn a research agent. The agent has access to WebSearch for gathering information.

**Task invocation:**

```
Worker session parameters:
  description: "Research [brief topic description]"
  execution_mode: "general-purpose"
  prompt: |
    Research the following task to gather technical information:

    TASK: [user's original request]

    Search for and compile:
    1. **Specifications**: Find relevant RFCs, official specs, or authoritative documentation
    2. **Best Practices**: Search for recommended approaches and patterns
    3. **Common Pitfalls**: Find known issues, anti-patterns, and things to avoid
    4. **References**: Collect links to authoritative sources

    Use WebSearch to find current, authoritative information.

    Return your findings as JSON in this exact format:
    {
      "specs": [
        {"title": "...", "summary": "...", "url": "..."}
      ],
      "best_practices": [
        {"practice": "...", "rationale": "..."}
      ],
      "pitfalls": [
        {"issue": "...", "consequence": "...", "prevention": "..."}
      ],
      "references": [
        {"title": "...", "url": "...", "relevance": "..."}
      ]
    }
```

### Output Format: research.json

The research findings are saved to `.ralph/research.json` with this structure:

```json
{
  "task": "implement OAuth2 login with Google provider",
  "researched_at": "2026-01-27T12:34:56Z",
  "specs": [
    {
      "id": "spec-1",
      "title": "OAuth 2.0 Authorization Framework (RFC 6749)",
      "summary": "Defines the core OAuth 2.0 protocol for authorization delegation",
      "url": "https://datatracker.ietf.org/doc/html/rfc6749"
    },
    {
      "id": "spec-2",
      "title": "OpenID Connect Core 1.0",
      "summary": "Identity layer on top of OAuth 2.0 for authentication",
      "url": "https://openid.net/specs/openid-connect-core-1_0.html"
    }
  ],
  "best_practices": [
    {
      "id": "bp-1",
      "practice": "Use state parameter to prevent CSRF attacks",
      "rationale": "The state parameter binds the authorization request to the user's session"
    },
    {
      "id": "bp-2",
      "practice": "Store tokens securely, never in localStorage",
      "rationale": "localStorage is vulnerable to XSS attacks; use httpOnly cookies"
    },
    {
      "id": "bp-3",
      "practice": "Implement token refresh flow",
      "rationale": "Access tokens should be short-lived; refresh tokens enable seamless re-authentication"
    }
  ],
  "pitfalls": [
    {
      "id": "pitfall-1",
      "issue": "Not validating the redirect URI",
      "consequence": "Open redirect vulnerability allowing token theft",
      "prevention": "Whitelist exact redirect URIs in OAuth provider config"
    },
    {
      "id": "pitfall-2",
      "issue": "Storing sensitive tokens in client-side storage",
      "consequence": "XSS attacks can steal authentication tokens",
      "prevention": "Use server-side sessions or httpOnly cookies"
    }
  ],
  "references": [
    {
      "id": "ref-1",
      "title": "Google OAuth 2.0 Documentation",
      "url": "https://developers.google.com/identity/protocols/oauth2",
      "relevance": "Official docs for implementing Google OAuth"
    },
    {
      "id": "ref-2",
      "title": "OWASP OAuth Security Cheat Sheet",
      "url": "https://cheatsheetseries.owasp.org/cheatsheets/OAuth_Cheat_Sheet.html",
      "relevance": "Security best practices for OAuth implementations"
    }
  ]
}
```

### Schema Definitions

#### Spec Object

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Stable ID (spec-1, spec-2, ...) |
| `title` | string | Name of the specification or RFC |
| `summary` | string | Brief description of what it covers |
| `url` | string | Link to the official document |

#### Best Practice Object

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Stable ID (bp-1, bp-2, ...) |
| `practice` | string | The recommended practice |
| `rationale` | string | Why this practice matters |

#### Pitfall Object

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Stable ID (pitfall-1, pitfall-2, ...) |
| `issue` | string | Description of the pitfall |
| `consequence` | string | What can go wrong |
| `prevention` | string | How to avoid it |

#### Reference Object

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Stable ID (ref-1, ref-2, ...) |
| `title` | string | Title of the resource |
| `url` | string | URL to the resource |
| `relevance` | string | Why this reference is useful |

### Reference ID Rules

- IDs are stable and sequential by type:
  - Specs: `spec-1`, `spec-2`, ...
  - Best practices: `bp-1`, `bp-2`, ...
  - Pitfalls: `pitfall-1`, `pitfall-2`, ...
  - References: `ref-1`, `ref-2`, ...
- Task files should only reference these IDs in `task.context.research_refs`.

### Implementation Instructions

When implementing the `ralph` skill command, execute research as follows:

1. **Check complexity**: Only run research for complex tasks
2. **Verify prerequisites**: Ensure `.ralph/code_context.json` exists from the mandatory code context phase
3. **Update state**: Set phase to `research` before starting
4. **Spawn worker session**: Use a Codex worker session with the prompt template above
5. **Parse results**: Extract JSON from worker session response
6. **Save research**: Write results to `.ralph/research.json`
7. **Update state**: Transition phase to `decisions`

**Example flow in ralph skill command:**

```
# After code context analysis and complexity assessment confirm task is complex...

1. Update state.json:
   - phase: "research"
   - updated_at: <current timestamp>

2. Call Codex worker session:
   - description: "Research [topic]"
   - execution_mode: "general-purpose"
   - prompt: [research prompt with user's task]

3. When worker session returns:
   - Parse JSON from response
   - Add metadata (task, researched_at)
   - Write to .ralph/research.json

4. Update state.json:
   - phase: "decisions"
   - updated_at: <current timestamp>
```

### Handling Research Failures

If the research worker session fails or returns invalid JSON:

1. Log the error to `.ralph/logs/errors.log`
2. Create a minimal research.json with empty arrays
3. Proceed to decisions phase (don't block on research failure)
4. Note in decisions that research was incomplete

```json
{
  "task": "...",
  "researched_at": "...",
  "error": "Research worker session failed: [error details]",
  "specs": [],
  "best_practices": [],
  "pitfalls": [],
  "references": []
}
```

### Notes

- Research adds latency but prevents costly mistakes in planning
- The worker session runs autonomously and returns when complete
- Results inform the decisions phase (what needs user input)
- For security-sensitive tasks, research is especially valuable
- Research is cached; re-running ralph skill on same task reuses existing research

---

## Decision Surfacing Phase

After code context analysis (and research for complex tasks), Ralph surfaces important decisions that require user input before planning can proceed. This ensures the plan is aligned with user preferences and resolves ambiguities early.

### When Decisions Run

The decisions phase runs for all tasks, but its scope varies:

| Task Type | Decision Scope |
|-----------|----------------|
| **Simple** | Minimal or no decisions needed; may skip directly to planning |
| **Complex** | Surfaces decisions identified during research |

```
Code context analysis complete (research complete or skipped)
    ↓
[decisions] phase begins
    ↓
Analyze code context and research findings for decision points
    ↓
Present each decision to user
    ↓
User answers (or asks follow-up questions)
    ↓
Save decisions to .ralph/decisions.json
    ↓
State updated to [planning] phase
```

### Decision Categories

Decisions are surfaced in these categories, ordered by impact:

| Category | Description | Examples |
|----------|-------------|----------|
| **Architecture** | Fundamental design choices | Monolith vs microservices, REST vs GraphQL |
| **Technology** | Library/framework selections | Which OAuth library, which database |
| **Security** | Security-related choices | Token storage, encryption approach |
| **Integration** | External service decisions | Which provider, API version |
| **Behavior** | Feature behavior specifications | Error handling, edge cases |

### Identifying Decisions from Inputs

Analyze code context and research findings to extract decisions:

1. **From Specs**: Multiple valid approaches mentioned → decision needed
2. **From Best Practices**: Conflicting recommendations → decision needed
3. **From Pitfalls**: Risk mitigation options → decision needed
4. **From Context**: Missing requirements → clarification needed

**Example decision extraction:**

```
Research finding: "OAuth tokens can be stored in httpOnly cookies or server-side sessions"
    ↓
Decision identified: Token storage approach
    ↓
Options: (1) httpOnly cookies, (2) Server-side sessions
```

### Presenting Decisions to the User

Each decision is presented with:

1. **Context**: What the decision is about and relevant background
2. **Why It Matters**: Impact on the project (security, performance, maintainability)
3. **Options**: Numbered list with brief description of each option
4. **Recommendation** (if applicable): Which option is recommended and why

**Format for presenting a decision:**

```
### Decision [N]: [Decision Title]

**Context:**
[Brief explanation of what needs to be decided and relevant background from research]

**Why This Matters:**
[Explain the impact - security implications, performance, maintainability, etc.]

**Options:**
1. [Option A] - [Brief description]
2. [Option B] - [Brief description]
3. [Option C] - [Brief description] (if applicable)

**Recommendation:** [Option X] because [rationale]

---
Which option do you prefer? (Enter 1, 2, 3, or ask a question)
```

### User Interaction Flow

The user can respond in several ways:

| Response | Action |
|----------|--------|
| Number (1, 2, 3...) | Record the selected option |
| Question | Answer the question, then re-present options |
| "skip" | Mark decision as deferred (will use default/recommendation) |
| Custom answer | Record the custom preference |

**Important:** Planning does NOT proceed until all critical decisions are resolved. The user must provide an answer for each decision before moving to the planning phase.

### Output Format: decisions.json

User decisions are saved to `.ralph/decisions.json`:

```json
{
  "task": "implement OAuth2 login with Google provider",
  "decided_at": "2026-01-27T12:45:00Z",
  "decisions": [
    {
      "id": "D1",
      "title": "Token Storage Approach",
      "category": "security",
      "context": "OAuth tokens need secure storage to prevent theft",
      "options": [
        {"number": 1, "label": "httpOnly cookies", "description": "Stored by browser, sent automatically"},
        {"number": 2, "label": "Server-side sessions", "description": "Stored on server, session ID in cookie"}
      ],
      "recommendation": 2,
      "recommendation_rationale": "More secure against XSS, easier to revoke",
      "selected_option": 2,
      "user_response": "2",
      "follow_up_questions": []
    },
    {
      "id": "D2",
      "title": "Session Library",
      "category": "technology",
      "context": "Need to choose a session management library",
      "options": [
        {"number": 1, "label": "express-session", "description": "Popular, well-documented"},
        {"number": 2, "label": "cookie-session", "description": "Simpler, stateless"},
        {"number": 3, "label": "Custom implementation", "description": "Full control, more work"}
      ],
      "recommendation": 1,
      "recommendation_rationale": "Most widely used, excellent Redis support",
      "selected_option": 1,
      "user_response": "1",
      "follow_up_questions": [
        {
          "question": "Does express-session support clustering?",
          "answer": "Yes, with a Redis store it works across multiple instances"
        }
      ]
    }
  ],
  "deferred": [],
  "critical_resolved": true
}
```

### Schema Definitions

#### Decision Object

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique identifier (D1, D2, etc.) |
| `title` | string | Brief title of the decision |
| `category` | string | Category (architecture, technology, security, integration, behavior) |
| `context` | string | Background information about the decision |
| `options` | array | List of Option objects |
| `recommendation` | number\|null | Recommended option number (if any) |
| `recommendation_rationale` | string | Why this option is recommended |
| `selected_option` | number | The option number the user selected |
| `user_response` | string | Raw user response (number or custom text) |
| `follow_up_questions` | array | Q&A exchanges before final decision |

#### Option Object

| Field | Type | Description |
|-------|------|-------------|
| `number` | number | Option number (1, 2, 3...) |
| `label` | string | Short name for the option |
| `description` | string | Brief explanation of what this option means |

#### Follow-up Question Object

| Field | Type | Description |
|-------|------|-------------|
| `question` | string | User's follow-up question |
| `answer` | string | Agent's answer to the question |

### Marking Decisions as Critical

Some decisions are critical (must be resolved before planning):

- **Architecture decisions**: Always critical
- **Security decisions**: Always critical
- **Technology decisions**: Critical if affects core functionality
- **Integration decisions**: Critical if blocks implementation
- **Behavior decisions**: Usually non-critical (can be deferred)

The `critical_resolved` field in decisions.json tracks whether all critical decisions have been answered.

### Implementation Instructions

When implementing the `ralph` skill command decision phase:

1. **Update state**: Set phase to `decisions`
2. **Load inputs**:
   - Read `.ralph/code_context.json` (required)
   - Read `.ralph/research.json` (if exists)
3. **Extract decisions**: Analyze code context and research for decision points
4. **For each decision**:
   a. Present using the format above
   b. Wait for user response
   c. If question: answer it, then re-present options
   d. Record the decision
5. **Save decisions**: Write to `.ralph/decisions.json`
6. **Verify critical**: Ensure all critical decisions resolved
7. **Update state**: Transition phase to `planning`

**Example flow:**

```
# After code context analysis and optional research phase...

1. Update state.json:
   - phase: "decisions"
   - updated_at: <current timestamp>

2. Analyze decision inputs:
   - Extract decision points from code paths, data flows, specs, best practices, pitfalls
   - Identify categories and criticality

3. For each decision:
   - Format and present to user
   - Use direct user prompt or direct prompting
   - Handle follow-up questions
   - Record response

4. Save to .ralph/decisions.json

5. Verify critical_resolved == true

6. Update state.json:
   - phase: "planning"
   - updated_at: <current timestamp>
```

### Handling No Decisions Needed

For simple tasks or tasks where research/code-context surfaced no ambiguities:

1. Create minimal decisions.json:
```json
{
  "task": "fix typo in README",
  "decided_at": "2026-01-27T12:45:00Z",
  "decisions": [],
  "deferred": [],
  "critical_resolved": true
}
```

2. Inform user: "No decisions needed. Proceeding to planning..."
3. Transition directly to planning phase

### Notes

- Users can always ask clarifying questions before deciding
- Default to recommendations if user says "skip" on non-critical decisions
- Critical decisions cannot be skipped - user must choose
- Decisions are cached; re-running ralph skill preserves previous decisions
- User can re-run ralph skill with `--reset-decisions` to clear and re-decide
- The planning phase uses decisions.json and code_context.json to inform task generation

---

## Planning Phase

After decisions are resolved, Ralph generates a comprehensive plan with discrete, executable tasks. This phase produces a PRD document and individual task files that enable autonomous execution via worker sessions.

### When Planning Runs

Planning runs after all critical decisions are resolved:

```
Decisions phase complete (critical_resolved: true)
    ↓
[planning] phase begins
    ↓
Generate PRD document (.ralph/prd.md)
    ↓
Create discrete task files (.ralph/tasks/)
    ↓
Assign task priorities
    ↓
State updated to [planning_complete]
    ↓
User reviews plan, runs start a new Codex session, then ralph-start skill
```

### Planning Outputs

| Output | Location | Purpose |
|--------|----------|---------|
| PRD Document | `.ralph/prd.md` | Human-readable plan overview |
| Task Files | `.ralph/tasks/task-NNN.json` | Machine-readable task specifications |
| State Update | `.ralph/state.json` | task_order, task_statuses populated |

### PRD Document Generation

The PRD (Product Requirements Document) provides a human-readable overview of the plan. It is saved to `.ralph/prd.md`.

#### PRD Structure

```markdown
# [Task Title]

## Overview
[Brief summary of what will be implemented]

## Original Request
[User's original task description]

## Code Context Summary
[Key local code paths and data-flow findings from code_context.json]

## Research Summary
[Key findings from research phase, if applicable]

## Decisions Made
[Summary of user decisions that inform the plan]

## Implementation Plan

### Phase 1: [Phase Name]
- Task 1: [Brief description]
- Task 2: [Brief description]

### Phase 2: [Phase Name]
- Task 3: [Brief description]
- Task 4: [Brief description]

## Task Dependency Graph
[Visual representation of task dependencies]

## Files to be Modified
[List of files that will be created or modified]

## Acceptance Criteria
[Overall success criteria for the complete implementation]

## Notes
[Any additional context or considerations]
```

#### PRD Generation Instructions

When generating the PRD:

1. **Title**: Derive from original request, make it descriptive
2. **Overview**: 2-3 sentences summarizing the implementation approach
3. **Code Context Summary**: Extract key call paths, data flows, and reuse candidates from code_context.json
4. **Research Summary**: Extract key insights from research.json (skip if simple task)
5. **Decisions Made**: List each decision from decisions.json with selected option
6. **Implementation Plan**: Group related tasks into logical phases
7. **Dependency Graph**: ASCII diagram showing task dependencies
8. **Files to Modify**: Aggregate from all task files_to_modify lists
9. **Acceptance Criteria**: High-level criteria derived from user's request

### Task File Structure

Each task is saved as a separate JSON file in `.ralph/tasks/` directory. Files are named `task-NNN.json` where NNN is a zero-padded sequence number.

#### Task Schema

```json
{
  "id": "task-001",
  "title": "Create user model and migration",
  "description": "Define the User schema with fields for authentication and create the corresponding database migration.",
  "acceptance_criteria": [
    "User model exists with email, password_hash, and timestamps",
    "Migration file creates users table with correct columns",
    "Migration runs successfully without errors"
  ],
  "dependencies": [],
  "priority": 2,
  "reuse_notes": [
    "Prefer existing password hashing helper in lib/myapp/accounts/passwords.ex",
    "Reuse migration template in priv/repo/migrations/_template.exs"
  ],
  "files_to_modify": [
    "lib/myapp/accounts/user.ex",
    "priv/repo/migrations/*_create_users.exs"
  ],
  "context": {
    "research_refs": ["spec-1", "bp-2"],
    "decisions_refs": ["D1"],
    "notes": "Use Argon2 for password hashing per security decision"
  },
  "status": "pending",
  "estimated_complexity": "medium"
}
```

#### Field Definitions

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | Yes | Unique identifier (task-001, task-002, etc.) |
| `title` | string | Yes | Brief, descriptive title (5-10 words) |
| `description` | string | Yes | Detailed description of what to implement |
| `acceptance_criteria` | array | Yes | List of specific, verifiable criteria |
| `dependencies` | array | Yes | List of task IDs that must complete first |
| `priority` | number | Yes | Execution priority (1 = highest, 5 = lowest) |
| `reuse_notes` | array | No | Pointers to existing helpers/utilities to reuse |
| `files_to_modify` | array | Yes | Files to create or modify (glob patterns allowed) |
| `context` | object | No | Additional context from research/decisions |
| `status` | string | Yes | Current status (pending, in_progress, completed, failed) |
| `estimated_complexity` | string | No | low, medium, or high |

#### Priority Guidelines

- **1**: Foundational work that unblocks others
- **2**: Core feature path
- **3**: Supporting features and integrations
- **4**: Polish, refactors, and non-blocking improvements
- **5**: Optional or nice-to-have work

#### Acceptance Criteria Guidelines

Each criterion should be:

- **Specific**: Clear about what's expected
- **Verifiable**: Can be checked objectively
- **Independent**: Can be verified without other criteria
- **Atomic**: Tests one thing, not multiple

**Good examples:**
- "Function returns empty array when no matches found"
- "API endpoint returns 401 for unauthenticated requests"
- "Migration rollback removes the table successfully"

**Bad examples:**
- "Code is well-written" (subjective)
- "Feature works correctly" (vague)
- "All tests pass and code is formatted" (multiple criteria)

### Task Dependencies

Dependencies define the execution order. A task cannot start until all its dependencies have completed.

#### Dependency Rules

1. **No circular dependencies**: A → B → C → A is invalid
2. **Explicit declaration**: Every dependency must be explicitly listed
3. **Transitive independence**: If A depends on B, and B depends on C, A does NOT need to list C

#### Example Dependency Graph

```
task-001 (User model)
    ↓
task-002 (User controller) ←── task-003 (Auth service)
    ↓                              ↓
task-004 (User routes) ←───────────┘
    ↓
task-005 (Integration tests)
```

**Corresponding task files:**

```json
// task-001.json
{"id": "task-001", "dependencies": [], "priority": 1}

// task-002.json
{"id": "task-002", "dependencies": ["task-001"], "priority": 2}

// task-003.json
{"id": "task-003", "dependencies": ["task-001"], "priority": 2}

// task-004.json
{"id": "task-004", "dependencies": ["task-002", "task-003"], "priority": 3}

// task-005.json
{"id": "task-005", "dependencies": ["task-004"], "priority": 4}
```

### Priority and Sequencing

Tasks execute sequentially. Use `priority` to order work within dependency constraints.

#### Priority Rules

1. **1 = highest priority, 5 = lowest**
2. **Dependencies win**: If task A depends on task B, B must run first regardless of priority
3. **Eligible task ordering**: Among tasks whose dependencies are complete, pick the lowest priority number
4. **Tie-breaker**: If priorities match, use task ID order (task-001 before task-002)

#### Example ordering

```
Eligible set after task-001:
  task-002 (priority 2)
  task-003 (priority 2)
  task-006 (priority 4)

Next task: task-002 (tie broken by ID)
```

### Task Sizing Guidelines

Each task should be sized for completion in a single worker session session. This ensures:
- Fresh context for each task (after start a new Codex session)
- Manageable scope
- Clear success/failure determination

#### Size Indicators

| Size | Indicators | Task Count |
|------|------------|------------|
| **Small** | Single function, < 50 lines | Can combine 2-3 |
| **Medium** | Single module, 50-200 lines | One per task |
| **Large** | Multiple modules, > 200 lines | Split into subtasks |

#### Splitting Large Tasks

If a task would be too large:

1. Identify logical boundaries (model vs controller vs routes)
2. Create separate tasks with dependencies
3. Each subtask should be independently verifiable

**Before (too large):**
```json
{
  "id": "task-001",
  "title": "Implement complete user authentication",
  "description": "Create user model, controller, routes, and tests..."
}
```

**After (properly sized):**
```json
// task-001.json
{"id": "task-001", "title": "Create user model with password hashing"}

// task-002.json
{"id": "task-002", "title": "Create user controller with CRUD actions", "dependencies": ["task-001"]}

// task-003.json
{"id": "task-003", "title": "Create authentication service", "dependencies": ["task-001"]}

// task-004.json
{"id": "task-004", "title": "Create user routes and middleware", "dependencies": ["task-002", "task-003"]}
```

### Reuse Sweep

Before generating tasks, scan the codebase for existing helpers/utilities that can be reused. This reduces duplicate functions and keeps implementation consistent.

Guidelines:
- Derive search keywords from the task description and acceptance criteria
- Search in likely directories for the project (e.g., `src/`, `lib/`, `app/`, `packages/`)
- Prefer existing helpers even if they need small extensions
- Record findings in `reuse_notes` for each task

Example commands:
```bash
rg -n "hash|encrypt|token" src lib
rg -n "validator|validation|schema" src lib
rg -n "client|api|http" src lib
```

### Implementation Instructions

When implementing the `ralph` skill command planning phase:

1. **Update state**: Set phase to `planning`
2. **Load inputs**: Read code_context.json, research.json (if exists), and decisions.json
3. **Analyze scope**: Determine tasks needed based on request, code context, and decisions
4. **Reuse sweep**: Search the codebase for existing helpers/utilities and capture findings
5. **Generate tasks**: Create task files following the schema
6. **Assign dependencies**: Build dependency graph
7. **Assign priorities**: Set priority based on dependencies, risk, and sequencing needs
8. **Generate PRD**: Create human-readable prd.md
9. **Update state**: Populate task_order (sorted by dependencies then priority) and task_statuses
10. **Transition**: Set phase to `planning_complete`

**Example flow:**

```
# After decisions phase complete...

1. Update state.json:
   - phase: "planning"
   - updated_at: <current timestamp>

2. Load context:
   - Read .ralph/code_context.json
   - Read .ralph/research.json (if exists)
   - Read .ralph/decisions.json

3. Break down the task:
   - Identify all work items needed
   - Determine dependencies between items
   - Size each item appropriately

4. Reuse sweep:
   - Search for existing helpers/utilities related to each task
   - Record findings for reuse_notes

5. For each task:
   - Generate task-NNN.json
   - Assign id, title, description
   - Define acceptance_criteria
   - Set dependencies
   - Calculate priority
   - Identify existing helpers/utilities to reuse and add reuse_notes
   - List files_to_modify

6. Generate PRD:
   - Compile overview from original request
   - Summarize code context findings (call paths and data flow)
   - Summarize research and decisions
   - Document implementation phases
   - Create dependency graph visualization
   - List all files to modify
   - Define overall acceptance criteria
   - Write to .ralph/prd.md

7. Update state.json:
   - task_order: ["task-001", "task-002", ...]
   - task_statuses: {"task-001": "pending", "task-002": "pending", ...}
   - phase: "planning_complete"
   - updated_at: <current timestamp>

8. Inform user:
   - "Planning complete! Review the plan at .ralph/prd.md"
   - "When ready, run start a new Codex session to reset context, then ralph-start skill to execute"
```

### Task File Validation

Before finalizing, validate all task files:

1. **Unique IDs**: No duplicate task IDs
2. **Valid dependencies**: All referenced dependencies exist
3. **No cycles**: Dependency graph is acyclic
4. **Complete coverage**: All work items are accounted for
5. **Valid priority**: Each task has priority 1-5
6. **Proper sizing**: No task is too large for single session

### Notes

- Planning produces deterministic output from the same inputs
- Tasks are stored as separate files for easy inspection and modification
- Users can manually edit task files before running ralph-start skill
- The PRD is for human consumption; tasks are for worker session execution
- Re-running ralph skill regenerates the plan (use with caution after edits)
- Simple tasks may have only 1-3 task files; complex tasks may have 10+
- Task IDs are sequential but execution order follows priority and dependencies
