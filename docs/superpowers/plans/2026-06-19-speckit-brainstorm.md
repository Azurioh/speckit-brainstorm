# speckit-brainstorm Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a Claude Code plugin whose single `/speckit-brainstorm` command conversationally guides a user through the entire GitHub Spec Kit pipeline, installing speckit (latest release) if missing.

**Architecture:** A thin orchestrator. Deterministic logic (state detection, install) lives in bash scripts sharing one helper library; the user-facing intelligence lives in one command-prompt markdown file. The command detects project state, challenges the idea like a brainstorming partner, then drives each native `/speckit.*` phase by reading and following its installed command file inline (there is no programmatic slash-command tool), always behind a preview-and-confirm gate. The repo is simultaneously the plugin and its marketplace.

**Tech Stack:** Bash (coreutils + curl; `jq` optional with grep fallback), Claude Code plugin manifests (JSON), GitHub Spec Kit (`specify` CLI via `uv`), `shellcheck` for linting.

## Global Constraints

- Bash scripts start with `#!/usr/bin/env bash` and `set -euo pipefail` (the sourced `lib.sh` and test scripts are the exceptions — see their tasks); all must pass `shellcheck` with zero warnings.
- No hard dependency beyond coreutils + `curl`. `jq` is optional — every JSON read has a `grep`/`sed` fallback. Network is best-effort; honor `SPECKIT_BRAINSTORM_OFFLINE=1` to skip all network calls.
- Shared helpers (`have`, `resolve_latest_tag`) live in `scripts/lib.sh` and are sourced by `detect.sh` and `install.sh` — never duplicated inline.
- Bundled scripts are located at runtime via `${CLAUDE_PLUGIN_ROOT}/scripts/<name>.sh`. Each script resolves its own directory (`${BASH_SOURCE[0]}`) to source `lib.sh`, independent of CWD. Project root is `${CLAUDE_PROJECT_DIR:-$PWD}`.
- speckit install is **pinned to the latest GitHub release tag** (`https://api.github.com/repos/github/spec-kit/releases/latest` → `.tag_name`); fallback tag when offline/rate-limited: `v0.11.2`.
- speckit agent flag is exactly `--integration claude`. Current-dir init is `specify init . --force --integration claude --script sh`.
- Plugin command name is `/speckit-brainstorm` (file `commands/speckit-brainstorm.md`). `plugin.json` requires `name`; `marketplace.json` requires `name`, `owner`, `plugins[]` (entry `source: "."`).
- All commit messages in English, ending with: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- Work happens on branch `feat/speckit-brainstorm-command` (already created).

---

### Task 1: Plugin manifests + scaffolding

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`
- Create: `commands/speckit-brainstorm.md` (minimal stub; full prompt lands in Task 5)
- Create: `tests/test_manifests.sh`

**Interfaces:**
- Produces: a loadable plugin named `speckit-brainstorm` exposing the `/speckit-brainstorm` command; manifests other tasks do not modify.

- [ ] **Step 1: Write the failing test**

`tests/test_manifests.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
check() { if eval "$2" >/dev/null 2>&1; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi; }

PJ="$ROOT/.claude-plugin/plugin.json"
MK="$ROOT/.claude-plugin/marketplace.json"
CMD="$ROOT/commands/speckit-brainstorm.md"

check "plugin.json exists"        "[ -f '$PJ' ]"
check "marketplace.json exists"   "[ -f '$MK' ]"
check "command file exists"       "[ -f '$CMD' ]"
check "plugin.json valid JSON"    "python3 -c 'import json,sys;json.load(open(\"$PJ\"))'"
check "marketplace.json valid"    "python3 -c 'import json,sys;json.load(open(\"$MK\"))'"
check "plugin name correct"       "python3 -c 'import json;assert json.load(open(\"$PJ\"))[\"name\"]==\"speckit-brainstorm\"'"
check "marketplace has owner"     "python3 -c 'import json;assert json.load(open(\"$MK\"))[\"owner\"][\"name\"]'"
check "marketplace lists plugin"  "python3 -c 'import json;p=json.load(open(\"$MK\"))[\"plugins\"];assert any(x[\"name\"]==\"speckit-brainstorm\" for x in p)'"
check "command has description"   "grep -q '^description:' '$CMD'"

exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_manifests.sh`
Expected: FAIL lines for missing files (manifests/command not created yet).

- [ ] **Step 3: Create the manifests and command stub**

`.claude-plugin/plugin.json`:
```json
{
  "name": "speckit-brainstorm",
  "displayName": "Speckit Brainstorm",
  "description": "Conversational guide for the full GitHub Spec Kit workflow — challenge your idea, then run each speckit step at the right moment behind a preview-and-confirm gate. Installs speckit (latest release) if missing.",
  "version": "0.1.0",
  "author": { "name": "Azurioh" },
  "repository": "https://github.com/Azurioh/speckit-brainstorm",
  "license": "MIT",
  "keywords": ["speckit", "spec-driven-development", "brainstorming", "workflow"]
}
```

`.claude-plugin/marketplace.json`:
```json
{
  "name": "speckit-brainstorm",
  "owner": { "name": "Azurioh" },
  "plugins": [
    {
      "name": "speckit-brainstorm",
      "source": ".",
      "description": "Conversational guide for the full GitHub Spec Kit workflow."
    }
  ]
}
```

`commands/speckit-brainstorm.md` (stub, replaced in Task 5):
```markdown
---
description: Conversational guide for the full GitHub Spec Kit workflow. Installs speckit (latest release) if missing.
argument-hint: "[optional: a short description of your idea]"
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
---

(stub — full orchestrator prompt added in Task 5)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_manifests.sh`
Expected: all `ok:` lines, exit 0.

- [ ] **Step 5: Lint the test**

Run: `shellcheck tests/test_manifests.sh`
Expected: no output (clean).

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json commands/speckit-brainstorm.md tests/test_manifests.sh
git commit -m "feat: scaffold plugin manifests and command stub

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `scripts/lib.sh` — shared helpers

**Files:**
- Create: `scripts/lib.sh`
- Create: `tests/test_lib.sh`

**Interfaces:**
- Produces: `scripts/lib.sh`, a sourced library (no side effects on source, not meant to be executed). Functions:
  - `have CMD` → exit 0 if `CMD` is on `PATH`, else non-zero.
  - `resolve_latest_tag` → prints the latest spec-kit release tag (e.g. `v0.11.2`) to stdout, or prints nothing if it cannot be resolved. Honors `SPECKIT_BRAINSTORM_OFFLINE=1` (skips network, prints nothing). Best-effort: never returns non-zero to the caller.
- Consumed by Tasks 3 (`detect.sh`) and 4 (`install.sh`).

- [ ] **Step 1: Write the failing test**

`tests/test_lib.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib.sh
. "$ROOT/scripts/lib.sh"
fail=0
chk() { if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAIL: $1 (want '$3' got '$2')"; fail=1; fi; }

# have()
if have sh; then echo "ok: have finds sh"; else echo "FAIL: have sh"; fail=1; fi
if have __no_such_cmd_xyz__; then echo "FAIL: have false-positive"; fail=1; else echo "ok: have rejects missing"; fi

# resolve_latest_tag offline -> empty
out="$(SPECKIT_BRAINSTORM_OFFLINE=1 resolve_latest_tag)"
chk "offline tag empty" "$out" ""

# resolve_latest_tag with a curl shim returning JSON -> parses tag
bin="$(mktemp -d)"
printf '#!/usr/bin/env bash\necho "{\\"tag_name\\":\\"v9.9.9\\"}"\n' > "$bin/curl"
chmod +x "$bin/curl"
out="$(PATH="$bin:$PATH" resolve_latest_tag)"
chk "tag parsed from API" "$out" "v9.9.9"
rm -rf "$bin"

exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_lib.sh`
Expected: FAIL — `. "$ROOT/scripts/lib.sh"` errors because the file does not exist (test aborts / functions undefined).

- [ ] **Step 3: Implement `scripts/lib.sh`**

```bash
#!/usr/bin/env bash
# lib.sh — shared helpers for the speckit-brainstorm bundled scripts.
# Source this file (do not execute it). Provides: have(), resolve_latest_tag().

# have CMD — succeed if CMD is on PATH.
have() { command -v "$1" >/dev/null 2>&1; }

# resolve_latest_tag — print the latest spec-kit release tag (e.g. "v0.11.2"),
# or print nothing if it cannot be resolved. Honors SPECKIT_BRAINSTORM_OFFLINE=1.
# Best-effort: never fails the caller.
resolve_latest_tag() {
  local api="https://api.github.com/repos/github/spec-kit/releases/latest"
  local resp tag=""
  if [ "${SPECKIT_BRAINSTORM_OFFLINE:-0}" = 1 ] || ! have curl; then
    return 0
  fi
  resp="$(curl -fsSL --max-time 5 "$api" 2>/dev/null || true)"
  [ -n "$resp" ] || return 0
  if have jq; then
    tag="$(printf '%s' "$resp" | jq -r '.tag_name // empty')"
  else
    tag="$(printf '%s' "$resp" | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' | head -n1 | sed -E 's/.*"([^"]+)"$/\1/')"
  fi
  printf '%s' "$tag"
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_lib.sh`
Expected: all `ok:` lines, exit 0.

- [ ] **Step 5: Lint**

Run: `shellcheck scripts/lib.sh tests/test_lib.sh`
Expected: no output (clean).

- [ ] **Step 6: Commit**

```bash
git add scripts/lib.sh tests/test_lib.sh
git commit -m "feat: add shared script helpers (have, resolve_latest_tag)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `detect.sh` — read-only state probe

**Files:**
- Create: `scripts/detect.sh`
- Create: `tests/test_detect.sh`

**Interfaces:**
- Consumes: `scripts/lib.sh` (`have`, `resolve_latest_tag`) from Task 2, sourced via the script's own directory.
- Produces: `scripts/detect.sh` prints a single-line JSON object to stdout with exactly these keys: `uv` (bool), `python` (string like `"3.11"` or `""`), `specify_cli` (bool), `speckit_installed` (bool), `version` (string), `latest` (string), `has_constitution` (bool), `cmd_prefix` (string, `"speckit."` or `""`), `feature` (string), `feature_count` (number), `has_spec` (bool), `has_plan` (bool), `has_tasks` (bool). Honors `CLAUDE_PROJECT_DIR` and `SPECKIT_BRAINSTORM_OFFLINE`. The command prompt (Task 5) consumes this contract.

- [ ] **Step 1: Write the failing test**

`tests/test_detect.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/detect.sh"
fail=0
check() { if printf '%s' "$OUT" | grep -q -- "$2"; then echo "ok: $1"; else echo "FAIL: $1 (missing: $2)"; echo "  got: $OUT"; fail=1; fi; }

# Fixture A: fresh project (no speckit)
tmp="$(mktemp -d)"
OUT="$(CLAUDE_PROJECT_DIR="$tmp" SPECKIT_BRAINSTORM_OFFLINE=1 bash "$SCRIPT")"
check "fresh: not installed"     '"speckit_installed":false'
check "fresh: no constitution"   '"has_constitution":false'
check "fresh: feature empty"     '"feature":""'
check "fresh: feature_count 0"   '"feature_count":0'
rm -rf "$tmp"

# Fixture B: installed project, one feature, spec only, namespaced commands
tmp="$(mktemp -d)"
mkdir -p "$tmp/.specify/memory" "$tmp/.claude/commands" "$tmp/specs/001-foo"
echo '{}'          > "$tmp/.specify/feature.json"
echo 'principles'  > "$tmp/.specify/memory/constitution.md"
: > "$tmp/.claude/commands/speckit.specify.md"
: > "$tmp/specs/001-foo/spec.md"
OUT="$(CLAUDE_PROJECT_DIR="$tmp" SPECKIT_BRAINSTORM_OFFLINE=1 bash "$SCRIPT")"
check "installed: speckit true"   '"speckit_installed":true'
check "installed: constitution"   '"has_constitution":true'
check "installed: cmd_prefix"     '"cmd_prefix":"speckit."'
check "installed: feature"        '"feature":"001-foo"'
check "installed: feature_count"  '"feature_count":1'
check "installed: has_spec"       '"has_spec":true'
check "installed: has_plan false" '"has_plan":false'
check "installed: has_tasks false" '"has_tasks":false'
rm -rf "$tmp"

# Fixture C: non-namespaced command files
tmp="$(mktemp -d)"
mkdir -p "$tmp/.specify" "$tmp/.claude/commands"
echo '{}' > "$tmp/.specify/feature.json"
: > "$tmp/.claude/commands/specify.md"
OUT="$(CLAUDE_PROJECT_DIR="$tmp" SPECKIT_BRAINSTORM_OFFLINE=1 bash "$SCRIPT")"
check "plain: cmd_prefix empty"   '"cmd_prefix":""'
rm -rf "$tmp"

exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_detect.sh`
Expected: FAIL (script does not exist → `grep` finds nothing, every check fails).

- [ ] **Step 3: Implement `scripts/detect.sh`**

```bash
#!/usr/bin/env bash
# detect.sh — read-only probe of GitHub Spec Kit state in the current project.
# Emits one JSON object on stdout. No side effects.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_DIR"

jbool() { if [ "$1" = true ]; then printf 'true'; else printf 'false'; fi; }

uv_present=false;      have uv && uv_present=true
specify_present=false; have specify && specify_present=true

python_version=""
if have python3; then
  python_version="$(python3 --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -n1 || true)"
fi

speckit_installed=false
{ [ -d .specify ] && [ -f .specify/feature.json ]; } && speckit_installed=true

installed_version=""
if $specify_present; then
  installed_version="$(specify version 2>/dev/null | grep -oiE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -n1 || true)"
fi

latest="$(resolve_latest_tag)"

has_constitution=false
[ -s .specify/memory/constitution.md ] && has_constitution=true

cmd_prefix=""
if [ -f .claude/commands/speckit.specify.md ]; then
  cmd_prefix="speckit."
elif [ -f .claude/commands/specify.md ]; then
  cmd_prefix=""
fi

feature=""; has_spec=false; has_plan=false; has_tasks=false; feature_count=0
if [ -d specs ]; then
  feature="$(ls -1dt specs/*/ 2>/dev/null | head -n1 | sed -e 's#/$##' -e 's#^specs/##' || true)"
  feature_count="$(find specs -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
  if [ -n "$feature" ]; then
    [ -f "specs/$feature/spec.md" ]  && has_spec=true
    [ -f "specs/$feature/plan.md" ]  && has_plan=true
    [ -f "specs/$feature/tasks.md" ] && has_tasks=true
  fi
fi

printf '{'
printf '"uv":%s,'                "$(jbool $uv_present)"
printf '"python":"%s",'          "$python_version"
printf '"specify_cli":%s,'       "$(jbool $specify_present)"
printf '"speckit_installed":%s,' "$(jbool $speckit_installed)"
printf '"version":"%s",'         "$installed_version"
printf '"latest":"%s",'          "$latest"
printf '"has_constitution":%s,'  "$(jbool $has_constitution)"
printf '"cmd_prefix":"%s",'      "$cmd_prefix"
printf '"feature":"%s",'         "$feature"
printf '"feature_count":%s,'     "${feature_count:-0}"
printf '"has_spec":%s,'          "$(jbool $has_spec)"
printf '"has_plan":%s,'          "$(jbool $has_plan)"
printf '"has_tasks":%s'          "$(jbool $has_tasks)"
printf '}\n'
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_detect.sh`
Expected: all `ok:` lines, exit 0.

- [ ] **Step 5: Lint**

Run: `shellcheck scripts/detect.sh tests/test_detect.sh`
Expected: no output (clean).

- [ ] **Step 6: Commit**

```bash
git add scripts/detect.sh tests/test_detect.sh
git commit -m "feat: add read-only speckit state probe (detect.sh)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: `install.sh` — install latest speckit + init project

**Files:**
- Create: `scripts/install.sh`
- Create: `tests/test_install.sh`

**Interfaces:**
- Consumes: `scripts/lib.sh` (`have`, `resolve_latest_tag`) from Task 2; consent is handled by the command layer.
- Produces: `scripts/install.sh` that, given `uv`/`python3` present, resolves the latest spec-kit tag (fallback `v0.11.2`), runs `uv tool install --force specify-cli --from git+https://github.com/github/spec-kit.git@<tag>`, then `specify init . --force --integration claude --script sh`, then verifies `.specify/` exists. Exits non-zero with a clear `ERROR:` message when a prerequisite is missing. Honors `CLAUDE_PROJECT_DIR` and `SPECKIT_BRAINSTORM_OFFLINE`.

- [ ] **Step 1: Write the failing test**

`tests/test_install.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/install.sh"
fail=0

make_shim() { # dir name body
  printf '#!/usr/bin/env bash\necho "%s $*" >> "$SHIM_LOG"\n%s\n' "$2" "$3" > "$1/$2"
  chmod +x "$1/$2"
}

# --- Happy path: all prereqs present, API returns a tag ---
bin="$(mktemp -d)"; proj="$(mktemp -d)"; export SHIM_LOG="$bin/calls.log"; : > "$SHIM_LOG"
mkdir -p "$proj/.specify"   # so the post-init verification passes
make_shim "$bin" uv      'exit 0'
make_shim "$bin" python3 'echo "Python 3.11.5"'
make_shim "$bin" specify 'if [ "$1" = version ]; then echo "specify 0.11.2"; fi; exit 0'
make_shim "$bin" curl    'echo "{\"tag_name\":\"v0.11.2\"}"'
if PATH="$bin:/usr/bin:/bin" CLAUDE_PROJECT_DIR="$proj" bash "$SCRIPT" >/dev/null 2>&1; then
  echo "ok: happy path exits 0"
else echo "FAIL: happy path should exit 0"; fail=1; fi
grep -q 'uv tool install --force specify-cli --from git+https://github.com/github/spec-kit.git@v0.11.2' "$SHIM_LOG" \
  && echo "ok: uv install args" || { echo "FAIL: uv install args"; cat "$SHIM_LOG"; fail=1; }
grep -q 'specify init . --force --integration claude --script sh' "$SHIM_LOG" \
  && echo "ok: specify init args" || { echo "FAIL: specify init args"; fail=1; }
rm -rf "$bin" "$proj"

# --- Offline: API skipped, fallback tag used ---
bin="$(mktemp -d)"; proj="$(mktemp -d)"; export SHIM_LOG="$bin/calls.log"; : > "$SHIM_LOG"
mkdir -p "$proj/.specify"
make_shim "$bin" uv      'exit 0'
make_shim "$bin" python3 'echo "Python 3.11.5"'
make_shim "$bin" specify 'if [ "$1" = version ]; then echo "specify 0.11.2"; fi; exit 0'
PATH="$bin:/usr/bin:/bin" CLAUDE_PROJECT_DIR="$proj" SPECKIT_BRAINSTORM_OFFLINE=1 bash "$SCRIPT" >/dev/null 2>&1
grep -q 'specify-cli --from git+https://github.com/github/spec-kit.git@v0.11.2' "$SHIM_LOG" \
  && echo "ok: offline uses fallback tag" || { echo "FAIL: fallback tag"; cat "$SHIM_LOG"; fail=1; }
rm -rf "$bin" "$proj"

# --- Missing uv: exit non-zero ---
bin="$(mktemp -d)"; proj="$(mktemp -d)"; export SHIM_LOG="$bin/calls.log"; : > "$SHIM_LOG"
make_shim "$bin" python3 'echo "Python 3.11.5"'
if PATH="$bin:/usr/bin:/bin" CLAUDE_PROJECT_DIR="$proj" bash "$SCRIPT" >/dev/null 2>&1; then
  echo "FAIL: should exit non-zero without uv"; fail=1
else echo "ok: fails without uv"; fi
rm -rf "$bin" "$proj"

# --- Python too old: exit non-zero ---
bin="$(mktemp -d)"; proj="$(mktemp -d)"; export SHIM_LOG="$bin/calls.log"; : > "$SHIM_LOG"
make_shim "$bin" uv      'exit 0'
make_shim "$bin" python3 'echo "Python 3.9.0"'
if PATH="$bin:/usr/bin:/bin" CLAUDE_PROJECT_DIR="$proj" bash "$SCRIPT" >/dev/null 2>&1; then
  echo "FAIL: should reject python < 3.11"; fail=1
else echo "ok: rejects old python"; fi
rm -rf "$bin" "$proj"

exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_install.sh`
Expected: FAIL (script missing → all checks fail / non-zero).

- [ ] **Step 3: Implement `scripts/install.sh`**

```bash
#!/usr/bin/env bash
# install.sh — install the latest GitHub Spec Kit release and initialize the
# current project for Claude Code. Consent is handled by the calling command.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$SCRIPT_DIR/lib.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_DIR"

GIT_SRC="git+https://github.com/github/spec-kit.git"
FALLBACK_TAG="v0.11.2"

die() { echo "ERROR: $*" >&2; exit 1; }

# 1. uv
have uv || die "uv not found. Install it first: curl -LsSf https://astral.sh/uv/install.sh | sh"

# 2. python >= 3.11
have python3 || die "python3 not found. Install Python >= 3.11."
pyver="$(python3 --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)"
pymajor="${pyver%%.*}"; pyminor="${pyver#*.}"
if [ "${pymajor:-0}" -lt 3 ] || { [ "${pymajor:-0}" -eq 3 ] && [ "${pyminor:-0}" -lt 11 ]; }; then
  die "Python >= 3.11 required (found ${pyver:-unknown})."
fi

# 3. resolve latest release tag (best effort; fallback when unavailable)
tag="$(resolve_latest_tag)"
[ -n "$tag" ] || tag="$FALLBACK_TAG"
echo "Installing GitHub Spec Kit ${tag} ..."

# 4. install the CLI pinned to that tag (idempotent via --force)
uv tool install --force specify-cli --from "${GIT_SRC}@${tag}"

# 5. initialize the current project for Claude Code
have specify || die "specify not on PATH after install. Ensure 'uv tool' bin dir is on PATH (uv tool update-shell)."
specify init . --force --integration claude --script sh

# 6. verify
specify version >/dev/null 2>&1 || die "specify version failed after init."
[ -d .specify ] || die ".specify/ was not created — init did not complete."
echo "OK: GitHub Spec Kit ${tag} installed and project initialized."
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_install.sh`
Expected: all `ok:` lines, exit 0.

- [ ] **Step 5: Lint**

Run: `shellcheck scripts/install.sh tests/test_install.sh`
Expected: no output (clean).

- [ ] **Step 6: Commit**

```bash
git add scripts/install.sh tests/test_install.sh
git commit -m "feat: add speckit installer pinned to latest release (install.sh)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Orchestrator command prompt

**Files:**
- Modify: `commands/speckit-brainstorm.md` (replace the Task 1 stub with the full prompt)
- Create: `tests/test_command.sh`

**Interfaces:**
- Consumes: the `detect.sh` JSON contract (Task 3) and `install.sh` behavior (Task 4), both located via `${CLAUDE_PLUGIN_ROOT}/scripts/`.
- Produces: the user-facing command. No later task depends on its internals.

- [ ] **Step 1: Write the failing test**

`tests/test_command.sh` (structural assertions — the prompt is prose, so we verify it wires up the contract and encodes the non-negotiable rules):
```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CMD="$ROOT/commands/speckit-brainstorm.md"
fail=0
need() { if grep -q -- "$2" "$CMD"; then echo "ok: $1"; else echo "FAIL: $1 (missing: $2)"; fail=1; fi; }

need "has description frontmatter"  '^description:'
need "allows Bash tool"             'allowed-tools:.*Bash'
need "runs detect.sh via plugin root" 'CLAUDE_PLUGIN_ROOT}/scripts/detect.sh'
need "references install.sh"        'CLAUDE_PLUGIN_ROOT}/scripts/install.sh'
need "preview-and-confirm gate"     'About to run'
need "one question at a time"       'one question at a time'
need "inline-follow mechanism"      'cmd_prefix'
need "intake challenge section"     'Intake challenge'
need "not a stub"                   'speckit-brainstorm guide'

# stub marker must be gone
if grep -q 'full orchestrator prompt added in Task 5' "$CMD"; then echo "FAIL: still a stub"; fail=1; else echo "ok: stub replaced"; fi
exit $fail
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/test_command.sh`
Expected: FAIL (stub lacks all required markers; stub marker still present).

- [ ] **Step 3: Replace `commands/speckit-brainstorm.md` with the full prompt**

````markdown
---
description: Conversational guide for the full GitHub Spec Kit workflow — challenge your idea, then run each speckit step at the right moment behind a preview-and-confirm gate. Installs speckit (latest release) if missing.
argument-hint: "[optional: a short description of your idea]"
allowed-tools: Bash, Read, Glob, Grep, AskUserQuestion
---

You are the **speckit-brainstorm guide**. Take the user from a raw idea to shipped,
spec-driven code using GitHub Spec Kit — WITHOUT making them remember speckit's commands.
You challenge their thinking like a brainstorming partner, then orchestrate the right
speckit step at the right time.

## Absolute rules

1. **Preview-and-confirm gate.** NEVER run a speckit phase or an install/shell command
   without first showing exactly what will run and the message it carries, then waiting
   for the user's go-ahead. Use this block:
   ```
   ▶ About to run:  /speckit.<phase>
      With message:
      ┌─────────────────────────────
      │ <exact text passed as arguments>
      └─────────────────────────────
      Reply: ok to run · edit the message · skip
   ```
   If the user edits the message, re-show the block before running.
2. **One question at a time.** When challenging or clarifying, ask a single question per
   message; prefer multiple-choice (use the AskUserQuestion tool).
3. **Never claim success you didn't verify.** After install or any phase, check the real
   files/output before saying it worked; relay errors verbatim.
4. **Match the user's language** (answer in whatever language they write in).

## Step 0 — Detect state

Run the bundled probe and parse its single-line JSON:
```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect.sh"
```
Fields: `uv, python, specify_cli, speckit_installed, version, latest, has_constitution,
cmd_prefix, feature, feature_count, has_spec, has_plan, has_tasks`.

## Step 1 — Ensure speckit is installed

- If `speckit_installed` is false:
  1. In ~2 lines, tell the user speckit isn't set up here and you'd like to install the
     latest release and initialize the project.
  2. Show the preview-and-confirm block:
     ```
     ▶ About to run:  bash ${CLAUDE_PLUGIN_ROOT}/scripts/install.sh
        This will: install the latest spec-kit release via uv, then run
        `specify init . --force --integration claude --script sh`.
     ```
  3. On confirm, run:
     ```bash
     bash "${CLAUDE_PLUGIN_ROOT}/scripts/install.sh"
     ```
     If it exits non-zero (e.g. `uv`/Python missing), relay the `ERROR:` line verbatim,
     help the user fix the prerequisite, then offer to retry. Do not proceed until the
     re-run of `detect.sh` reports `speckit_installed:true`.
- If `speckit_installed` is true and `latest` is non-empty and `version` is older than
  `latest`: mention it once and offer to upgrade (re-run `install.sh`). Skippable.

## Step 2 — Route to the right phase

Re-run `detect.sh` if you just installed. Resolve a phase's command file as
`.claude/commands/<cmd_prefix><phase>.md` (e.g. `.claude/commands/speckit.specify.md` when
`cmd_prefix` is `"speckit."`). Then route:

| State | Action |
|---|---|
| `has_constitution` false, fresh project | Offer (don't force) the `constitution` phase to set project principles. Skippable. |
| no active `feature`, or user wants a new one | Run **Intake challenge**, then the `specify` phase. |
| spec exists, no plan | Review the spec with the user, surface gaps; offer the `clarify` phase if ambiguous, then the `plan` phase. |
| plan exists, no tasks | Run the `tasks` phase; then offer the `analyze` phase for cross-artifact consistency. |
| tasks exist | Confirm readiness, then run the `implement` phase (explicit gate before large execution). |
| `feature_count` > 1 and ambiguous | Show a short menu of the directories under `specs/` and ask which feature to work on. |

## Intake challenge (the heart of this command)

Before running `specify`, extract the REAL need. If `$ARGUMENTS` is non-empty, use it as the
starting idea. Ask, ONE AT A TIME, only what's still unknown:
1. The problem behind the request — who hurts, and how, today?
2. Who are the users, and what are the top jobs-to-be-done?
3. Hard constraints (tech, time, integrations, compliance)?
4. What does success look like — observable and measurable?
5. Explicit non-goals / out of scope?
6. Scope check — one feature or several? If several, help split and tackle the first.

Challenge vague or weak answers; reflect back what you heard. When you have enough, distill a
tight feature brief (problem · users · requirements · success criteria · non-goals) and use
that text as the message for the `specify` phase.

## Running a phase (inline-follow mechanism)

There is no programmatic slash-command tool. To run phase `<phase>` with message `<msg>`:
1. Resolve its command file path using `cmd_prefix` (Step 2).
2. Show the preview-and-confirm block with `/speckit.<phase>` and `<msg>`.
3. On confirm: **Read that command file and execute its instructions exactly as written,
   treating `<msg>` as the command's `$ARGUMENTS`.** Run any helper scripts it references.
   Follow the installed speckit command — do not improvise its behavior.
4. When it finishes, summarize what it produced in plain language, flag gaps/risks, and
   confirm before advancing to the next phase.

## After implement

When the `implement` phase is done: summarize what was built, suggest running the project's
tests/verification, and remind the user they can re-run `/speckit-brainstorm` anytime to
continue or start a new feature.
````

- [ ] **Step 4: Run test to verify it passes**

Run: `bash tests/test_command.sh`
Expected: all `ok:` lines, exit 0.

- [ ] **Step 5: Lint the test**

Run: `shellcheck tests/test_command.sh`
Expected: no output (clean).

- [ ] **Step 6: Commit**

```bash
git add commands/speckit-brainstorm.md tests/test_command.sh
git commit -m "feat: implement orchestrator command prompt

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: README + test runner + end-to-end verification

**Files:**
- Create: `tests/run.sh` (runs all `tests/test_*.sh` + shellcheck)
- Modify: `README.md`

**Interfaces:**
- Consumes: all prior tasks. Produces no new runtime interface; this task documents and verifies the whole.

- [ ] **Step 1: Write the test runner**

`tests/run.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

echo "== shellcheck =="
shellcheck "$ROOT"/scripts/*.sh "$ROOT"/tests/*.sh || fail=1

for t in "$ROOT"/tests/test_*.sh; do
  echo "== $(basename "$t") =="
  bash "$t" || fail=1
done

if [ "$fail" -eq 0 ]; then echo "ALL GREEN"; else echo "FAILURES ABOVE"; fi
exit $fail
```

- [ ] **Step 2: Run the full suite**

Run: `bash tests/run.sh`
Expected: `ALL GREEN`, exit 0. (Fix any failure before continuing.)

- [ ] **Step 3: Write the README**

Replace `README.md` with install + usage docs:
````markdown
# speckit-brainstorm

A Claude Code command that walks you through the entire [GitHub Spec Kit](https://github.com/github/spec-kit)
workflow by **conversation** instead of memorizing commands. It challenges your idea like a
brainstorming partner, then runs each speckit step (`specify → clarify → plan → tasks →
analyze → implement`) at the right moment — always showing you the exact command and message
before it runs. If speckit isn't installed in your project, it offers to install the latest
release and initialize it for you.

## Install

```
/plugin marketplace add Azurioh/speckit-brainstorm
/plugin install speckit-brainstorm@speckit-brainstorm
```

## Use

```
/speckit-brainstorm
```
Or seed it with an idea:
```
/speckit-brainstorm a CLI that tracks my running workouts
```

The command is phase-aware: re-run it anytime and it resumes where you left off (or starts a
new feature).

## Requirements

- [`uv`](https://docs.astral.sh/uv/) and Python ≥ 3.11 (only needed the first time, to
  install speckit).
- macOS / Linux (bash). Windows/PowerShell support is planned.

## Development

Run the test suite:
```
bash tests/run.sh
```
````

- [ ] **Step 4: Manual end-to-end verification**

Perform and record the result of each (this plan's scripts are unit-tested; this step
exercises the real plugin):
1. In a scratch git repo with no speckit: `/plugin marketplace add <local path>` then
   `/plugin install speckit-brainstorm@speckit-brainstorm`; confirm `/speckit-brainstorm`
   appears in the command list.
2. Run `/speckit-brainstorm` → confirm it detects "not installed", previews the install
   command, and (on approval) installs + inits speckit; confirm `.specify/` and
   `.claude/commands/` now exist.
3. Continue through the intake challenge → confirm the preview-and-confirm block appears
   before `specify` runs.
4. Re-run `/speckit-brainstorm` mid-flow → confirm it resumes at the correct phase.

If a viewport/environment prevents any check, state so explicitly rather than claiming success.

- [ ] **Step 5: Commit**

```bash
git add tests/run.sh README.md
git commit -m "docs: add README and full test runner

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review (completed during planning)

- **Spec coverage:** §1 purpose → Task 5 prompt; §3 approach (thin orchestrator, inline-follow) → Task 5; §4 layout → Tasks 1–6; §5 flow/§6 gate → Task 5; §7 detect → Task 3; §8 install → Task 4; §9 edge cases → handled across detect.sh (partial/offline/multi-feature/cmd_prefix), install.sh (uv/python/api-down), and the prompt (not-a-repo confirm, edited-message re-show, menu); §10 testing → Tasks 1–6 tests + `tests/run.sh`. Shared tag-resolution logic is centralized in `lib.sh` (Task 2) — no duplication. No gaps.
- **Placeholder scan:** none — all scripts, tests, manifests, and the command prompt are given in full.
- **Type/contract consistency:** the `detect.sh` JSON keys defined in Task 3 are the exact keys referenced by Task 5's prompt and `tests/test_detect.sh`; `resolve_latest_tag`/`have` signatures in Task 2 match their use in Tasks 3–4; install argument strings asserted in Task 4's test match `install.sh` verbatim.

## Build-time confirmations (low-risk, verify while implementing)

- `marketplace.json` `source: "."` for a repo that is its own single plugin — if Claude Code rejects it, move plugin files under a `plugin/` subdir and set `source: "./plugin"` (Task 1 + the manifest test still apply).
- `${CLAUDE_PLUGIN_ROOT}` substitution inside a command markdown body — if it is not expanded there, fall back to resolving scripts relative to the project or document the absolute cache path. Verified during Task 6 step 4.
