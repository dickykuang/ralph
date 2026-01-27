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

---

## Complexity Assessment

Ralph assesses task complexity to determine the appropriate workflow. Simple tasks skip research and proceed directly to planning, while complex tasks get full research treatment.

### Complexity Levels

| Level | Description | Workflow |
|-------|-------------|----------|
| `simple` | Straightforward, well-defined tasks | Skip research → Planning → Execution |
| `complex` | Multi-faceted tasks requiring research | Research → Decisions → Planning → Execution |

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
| Research needed | No | Yes |
| User decisions needed | 0-1 | 2+ |

### Workflow Implications

#### For Simple Tasks

```
User invokes /ralph "fix typo in README"
    ↓
Assess complexity → Simple
    ↓
Skip research phase
    ↓
Skip decisions phase (or minimal)
    ↓
Generate lightweight plan
    ↓
[planning_complete]
```

#### For Complex Tasks

```
User invokes /ralph "implement OAuth2 login"
    ↓
Assess complexity → Complex
    ↓
Research phase (specs, best practices, pitfalls)
    ↓
Decisions phase (which OAuth provider? session vs JWT?)
    ↓
Comprehensive planning with detailed tasks
    ↓
[planning_complete]
```

### Usage in /ralph Command

When implementing the /ralph command, assess complexity early:

1. Parse the user's task description
2. Run complexity assessment
3. Store result in state.json as `complexity` field
4. Branch workflow based on complexity level

### Notes

- When in doubt, classify as complex (research is valuable)
- User can override complexity assessment if they disagree
- Simple tasks still generate plans, just with less overhead
- Complexity is assessed once at the start, not re-evaluated mid-workflow

---

## Research Phase

For complex tasks, Ralph performs automated research to gather technical specifications, best practices, and common pitfalls before planning. This ensures the plan is informed by authoritative sources rather than relying solely on general knowledge.

### When Research Runs

Research runs **only for complex tasks**. Simple tasks skip directly to the decisions phase (or planning if no decisions needed).

```
Complex task detected
    ↓
[research] phase begins
    ↓
Spawn research subagent with Task tool
    ↓
Subagent performs web searches
    ↓
Results saved to .ralph/research.json
    ↓
State updated to [decisions] phase
```

### Research Goals

The research subagent gathers information in these categories:

| Category | Description | Examples |
|----------|-------------|----------|
| **Specifications** | Official specs, RFCs, documentation | OAuth 2.0 RFC, GraphQL spec, REST API guidelines |
| **Best Practices** | Industry-standard approaches | Error handling patterns, security best practices |
| **Common Pitfalls** | Known issues and anti-patterns | Race conditions, security vulnerabilities, performance traps |
| **References** | Authoritative sources for further reading | Official docs, trusted tutorials, GitHub repos |

### Spawning the Research Subagent

Use the Task tool with `subagent_type: "general-purpose"` to spawn a research agent. The agent has access to WebSearch for gathering information.

**Task invocation:**

```
Task tool parameters:
  description: "Research [brief topic description]"
  subagent_type: "general-purpose"
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
      "title": "OAuth 2.0 Authorization Framework (RFC 6749)",
      "summary": "Defines the core OAuth 2.0 protocol for authorization delegation",
      "url": "https://datatracker.ietf.org/doc/html/rfc6749"
    },
    {
      "title": "OpenID Connect Core 1.0",
      "summary": "Identity layer on top of OAuth 2.0 for authentication",
      "url": "https://openid.net/specs/openid-connect-core-1_0.html"
    }
  ],
  "best_practices": [
    {
      "practice": "Use state parameter to prevent CSRF attacks",
      "rationale": "The state parameter binds the authorization request to the user's session"
    },
    {
      "practice": "Store tokens securely, never in localStorage",
      "rationale": "localStorage is vulnerable to XSS attacks; use httpOnly cookies"
    },
    {
      "practice": "Implement token refresh flow",
      "rationale": "Access tokens should be short-lived; refresh tokens enable seamless re-authentication"
    }
  ],
  "pitfalls": [
    {
      "issue": "Not validating the redirect URI",
      "consequence": "Open redirect vulnerability allowing token theft",
      "prevention": "Whitelist exact redirect URIs in OAuth provider config"
    },
    {
      "issue": "Storing sensitive tokens in client-side storage",
      "consequence": "XSS attacks can steal authentication tokens",
      "prevention": "Use server-side sessions or httpOnly cookies"
    }
  ],
  "references": [
    {
      "title": "Google OAuth 2.0 Documentation",
      "url": "https://developers.google.com/identity/protocols/oauth2",
      "relevance": "Official docs for implementing Google OAuth"
    },
    {
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
| `title` | string | Name of the specification or RFC |
| `summary` | string | Brief description of what it covers |
| `url` | string | Link to the official document |

#### Best Practice Object

| Field | Type | Description |
|-------|------|-------------|
| `practice` | string | The recommended practice |
| `rationale` | string | Why this practice matters |

#### Pitfall Object

| Field | Type | Description |
|-------|------|-------------|
| `issue` | string | Description of the pitfall |
| `consequence` | string | What can go wrong |
| `prevention` | string | How to avoid it |

#### Reference Object

| Field | Type | Description |
|-------|------|-------------|
| `title` | string | Title of the resource |
| `url` | string | URL to the resource |
| `relevance` | string | Why this reference is useful |

### Implementation Instructions

When implementing the `/ralph` command, execute research as follows:

1. **Check complexity**: Only run research for complex tasks
2. **Update state**: Set phase to `research` before starting
3. **Spawn subagent**: Use Task tool with the prompt template above
4. **Parse results**: Extract JSON from subagent response
5. **Save research**: Write results to `.ralph/research.json`
6. **Update state**: Transition phase to `decisions`

**Example flow in /ralph command:**

```
# After complexity assessment determines task is complex...

1. Update state.json:
   - phase: "research"
   - updated_at: <current timestamp>

2. Call Task tool:
   - description: "Research [topic]"
   - subagent_type: "general-purpose"
   - prompt: [research prompt with user's task]

3. When subagent returns:
   - Parse JSON from response
   - Add metadata (task, researched_at)
   - Write to .ralph/research.json

4. Update state.json:
   - phase: "decisions"
   - updated_at: <current timestamp>
```

### Handling Research Failures

If the research subagent fails or returns invalid JSON:

1. Log the error to `.ralph/logs/errors.log`
2. Create a minimal research.json with empty arrays
3. Proceed to decisions phase (don't block on research failure)
4. Note in decisions that research was incomplete

```json
{
  "task": "...",
  "researched_at": "...",
  "error": "Research subagent failed: [error details]",
  "specs": [],
  "best_practices": [],
  "pitfalls": [],
  "references": []
}
```

### Notes

- Research adds latency but prevents costly mistakes in planning
- The subagent runs autonomously and returns when complete
- Results inform the decisions phase (what needs user input)
- For security-sensitive tasks, research is especially valuable
- Research is cached; re-running /ralph on same task reuses existing research
