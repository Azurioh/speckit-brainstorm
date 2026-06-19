# speckit-brainstorm — Design Spec

- **Date:** 2026-06-19
- **Status:** Approved (design), pending implementation plan
- **Distribution:** Claude Code plugin (marketplace-installable)

## 1. Purpose

[GitHub Spec Kit](https://github.com/github/spec-kit) ("speckit") drives Spec-Driven
Development through a sequence of slash commands the user must run by hand, in the right
order, knowing which one to use:

`/speckit.constitution → /speckit.specify → /speckit.clarify → /speckit.plan → /speckit.tasks → /speckit.analyze → /speckit.implement`

This project ships a **single conversational command, `/speckit-brainstorm`**, that wraps the
entire speckit pipeline. Instead of memorizing commands, the user talks: the command
**challenges the idea** (Socratic, brainstorming-style) to surface the real need, then
orchestrates the right speckit step at the right moment, previews each command before
running it, and explains every result in plain language.

The command also bootstraps speckit itself: on launch it detects whether speckit is
installed and, if not, offers to install the **latest release** and initialize the project.

## 2. Goals / Non-goals

**Goals**
- One entry point (`/speckit-brainstorm`) covering the full speckit lifecycle.
- Brainstorm-style challenge to extract the real requirement before any spec is written.
- Phase-aware: re-runnable across sessions, resumes at the correct step.
- Auto-detect + offer install of speckit, pinned to the latest GitHub release.
- Never run a speckit (or shell) command without showing it and the message it carries,
  and getting user validation first.
- Distributable to others as a Claude Code plugin via a git marketplace.

**Non-goals**
- Reimplementing speckit's logic. We orchestrate the native commands, not replace them.
- Windows/PowerShell support in v1 (bash-first; PowerShell mirror is a follow-up).
- Installing language runtimes silently (Python). We guide; we don't force.

## 3. Approach

**Thin orchestrator over native speckit.** The `/speckit-brainstorm` prompt:
1. runs a detect script to learn the project state,
2. routes to the correct phase,
3. performs the conversational challenge for that phase,
4. **previews the exact command + message and gets confirmation**,
5. invokes the native `/speckit.*` command,
6. summarizes the output, challenges gaps, and confirms before advancing.

Rejected alternatives:
- **Self-contained reimplementation** — duplicates speckit logic, rots on every speckit
  release. Rejected.
- **Always-on phase menu** — more friction, less guided. Kept only as a fallback for
  genuinely ambiguous states (e.g. multiple features in `specs/`).

**Invocation mechanism:** drive each phase via Claude Code's `SlashCommand` tool to call
`/speckit.specify` etc. If that tool is unavailable, fall back to reading and following the
corresponding `.claude/commands/speckit.<phase>.md` file inline. Available phase commands are
discovered from the installed files, not hardcoded, so version differences degrade gracefully.

## 4. Repository / plugin layout

The repo `speckit-brainstorm` is both the marketplace and the plugin:

```
speckit-brainstorm/
├─ .claude-plugin/
│  ├─ plugin.json        # manifest: name, version, description, author
│  └─ marketplace.json   # /plugin marketplace add <you>/speckit-brainstorm → /plugin install
├─ commands/
│  └─ speckit-brainstorm.md   # THE orchestrator command (frontmatter + prompt)
├─ scripts/
│  ├─ detect.sh          # prints JSON state (read-only)
│  └─ install.sh         # prereqs → latest release → uv tool install → specify init
├─ docs/superpowers/specs/
│  └─ 2026-06-19-speckit-brainstorm-design.md
├─ README.md             # install + usage
└─ LICENSE
```

- Deterministic logic (detect, install) lives in **bash scripts**, not the prompt — testable,
  DRY, single-responsibility.
- The exact `plugin.json` / `marketplace.json` field schema is verified against current
  Claude Code plugin docs at build time.

## 5. The `/speckit-brainstorm` command flow

A phase-aware state machine. On **every** launch:

1. **Detect** — run `detect.sh`; parse its JSON.
2. **Not installed** → explain in ~2 lines, ask consent, run install flow (§7).
3. **Outdated** (`version < latest`) → mention, offer upgrade (skippable).
4. **Route by phase:**
   | State | Action |
   |---|---|
   | no constitution | offer `/speckit.constitution` once (skippable) |
   | no active feature / wants new | **INTAKE CHALLENGE** → distill brief → `/speckit.specify` |
   | spec exists, gaps | review, offer `/speckit.clarify` |
   | spec, no plan | checkpoint (stack/constraints) → `/speckit.plan` |
   | plan, no tasks | `/speckit.tasks` (then offer `/speckit.analyze`) |
   | tasks ready | confirm gate → `/speckit.implement` |
   | ambiguous / multiple features | **menu** (fallback) |
5. **After each native command** → summarize plainly, challenge gaps, confirm advance.

**Challenge intensity:** heavy at intake (real problem, users, constraints, success criteria,
non-goals, scope), light checkpoints afterward. Always **one question at a time**, multiple
choice when possible — mirroring the superpowers brainstorming style.

## 6. Cross-cutting rule — preview-and-confirm gate

Before running **any** speckit command or shell command, the command shows a confirm block and
waits:

```
▶ About to run:  /speckit.specify
   With message:
   ┌─────────────────────────────────────
   │ <the exact distilled brief / args text>
   └─────────────────────────────────────
   [Enter to run · edit the text · skip]
```

- Applies to every `/speckit.*` invocation **and** every shell command in the install flow.
- The user can edit the message; on edit, the block is re-shown before firing.
- Nothing executes behind the user's back.

## 7. `detect.sh` (read-only probe)

Prints a single JSON line; no side effects:

| Field | Source |
|---|---|
| `uv` | `command -v uv` |
| `python` | `python3 --version` (need ≥ 3.11) |
| `specify_cli` | `command -v specify` + `specify version` |
| `speckit_installed` | `[ -d .specify ] && [ -f .specify/feature.json ]` |
| `version` | installed speckit version |
| `latest` | `curl -s https://api.github.com/repos/github/spec-kit/releases/latest` → `.tag_name` |
| `has_constitution` | `[ -s .specify/memory/constitution.md ]` |
| `feature` | newest dir under `specs/` (active feature) |
| `has_spec` / `has_plan` / `has_tasks` | existence of `spec.md` / `plan.md` / `tasks.md` in that dir |

- `latest` is best-effort: offline / rate-limited → `null`; the flow still works (upgrade prompt
  is simply skipped).
- Output is the contract between script and command prompt.

## 8. `install.sh` (idempotent)

Consent is gathered at the command layer (via the preview gate); the script assumes go-ahead.

1. **uv missing** → offer `curl -LsSf https://astral.sh/uv/install.sh | sh` (confirm — external script).
2. **python < 3.11** → report and point to a fix; do not silently install a runtime.
3. **Latest tag** from the GitHub releases API (fallback: a pinned known-good tag if the API is down).
4. **Install pinned to that tag:**
   `uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@<tag>`
5. **Init in current project:** `specify init . --integration claude` (the exact current-dir flag —
   `.` vs `--here` — is confirmed via `specify init --help` at build time).
6. **Verify:** `specify version` succeeds and `.specify/` exists; otherwise surface the raw error and
   do not claim success.

## 9. Edge cases

- **Not a git repo / unexpected dir** → warn, confirm target dir before init.
- **`.specify/` partial or corrupt** → detect reports it; offer repair (re-init) vs continue.
- **GitHub API down / rate-limited** → `latest=null` → skip upgrade prompt; install uses fallback tag.
- **uv / python missing** → guided fix, never a silent runtime install.
- **Multiple features under `specs/`** → menu to pick the active one.
- **User edits a previewed message** → re-show the updated block before firing.
- **`SlashCommand` tool unavailable** → read + follow `.claude/commands/speckit.<phase>.md` inline.
- **speckit command names differ across versions** → discover available `speckit.*` files instead of
  hardcoding.

## 10. Testing

- `detect.sh` / `install.sh`: `shellcheck` clean + `bats` unit tests against fixture project dirs
  (fresh / installed / partial / multi-feature). `curl` and `specify` are mocked.
- Manual end-to-end: fresh project (no speckit) → install → full pipeline → re-launch mid-flow →
  resume at correct phase.
- Plugin smoke test: `/plugin marketplace add` + `/plugin install` in a scratch project; confirm
  `/speckit-brainstorm` appears and runs.

## 11. Open items to confirm at build time

- Exact `plugin.json` / `marketplace.json` schema (current Claude Code plugin docs).
- `specify init` current-directory flag (`.` vs `--here`) and the precise `--integration claude` syntax.
- Availability/permission model of the `SlashCommand` tool in target environments.
- Confirm the namespaced command names (`/speckit.*`) against the installed speckit version.

## 12. Addendum (2026-06-19) — GitHub tracking-issues step

A new closing step turns the generated tasks into GitHub issues using speckit's **native**
`/speckit.taskstoissues` command (confirmed present in spec-kit v0.11.3: "Convert generated task
lists into GitHub issues"; it skips tasks that already have an issue).

- **Mechanism:** same inline-follow + preview-and-confirm gate as every other phase — no new
  tool, no duplication. Because `taskstoissues` is itself an agent prompt, the command passes a
  reusable **Issue quality rules** block as guidance so the created issues honor them.
- **Placement:** offered once `has_tasks` is true (before implementing, if the user wants to
  track work first) and again as the closing proposal after `implement`.
- **Source/granularity:** issues are **grouped** from `tasks.md` into coherent work items — not
  one issue per micro-task.
- **Issue quality rules (enforced):** (1) group, don't enumerate; (2) meaningful outcome-oriented
  title, never "Task N"/"Issue N"; (3) relevant description (what + why, scope, spec/plan refs);
  (4) explicit acceptance criteria (verifiable "done" checklist).
- **Prerequisite/edge case:** needs a GitHub repo + remote + `gh` (or speckit's GitHub
  integration); if absent, the command says so and skips rather than fabricating issues.
- **No script/contract change:** `detect.sh` is unchanged (`taskstoissues` self-skips existing
  issues, so no new state field is required). Only the command prompt and its structural test
  changed.
