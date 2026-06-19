#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/install.sh"
fail=0

make_shim() { # dir name body
  # shellcheck disable=SC2016  # single-quoted body is intentional: we want literals in the shim
  printf '#!/usr/bin/env bash\necho "%s $*" >> "$SHIM_LOG"\n%s\n' "$2" "$3" > "$1/$2"
  chmod +x "$1/$2"
}

# --- Happy path: all prereqs present, API returns a tag ---
bin="$(mktemp -d)"; proj="$(mktemp -d)"; export SHIM_LOG="$bin/calls.log"; : > "$SHIM_LOG"
mkdir -p "$proj/.specify"   # so the post-init verification passes
make_shim "$bin" uv      'exit 0'
make_shim "$bin" python3 'echo "Python 3.11.5"'
# shellcheck disable=SC2016  # single-quoted body is intentional: $1 must expand inside the shim, not here
make_shim "$bin" specify 'if [ "$1" = version ]; then echo "specify 0.11.2"; fi; exit 0'
make_shim "$bin" curl    'echo "{\"tag_name\":\"v0.11.2\"}"'
if PATH="$bin:/usr/bin:/bin" CLAUDE_PROJECT_DIR="$proj" bash "$SCRIPT" >/dev/null 2>&1; then
  echo "ok: happy path exits 0"
else echo "FAIL: happy path should exit 0"; fail=1; fi
# shellcheck disable=SC2015  # &&...|| is intentional assertion pattern in tests
grep -qF 'uv tool install --force specify-cli --from git+https://github.com/github/spec-kit.git@v0.11.2' "$SHIM_LOG" \
  && echo "ok: uv install args" || { echo "FAIL: uv install args"; cat "$SHIM_LOG"; fail=1; }
# shellcheck disable=SC2015
grep -qF 'specify init . --force --integration claude --script sh' "$SHIM_LOG" \
  && echo "ok: specify init args" || { echo "FAIL: specify init args"; fail=1; }
rm -rf "$bin" "$proj"

# --- Offline: API skipped, fallback tag used ---
bin="$(mktemp -d)"; proj="$(mktemp -d)"; export SHIM_LOG="$bin/calls.log"; : > "$SHIM_LOG"
mkdir -p "$proj/.specify"
make_shim "$bin" uv      'exit 0'
make_shim "$bin" python3 'echo "Python 3.11.5"'
# shellcheck disable=SC2016  # single-quoted body is intentional: $1 must expand inside the shim, not here
make_shim "$bin" specify 'if [ "$1" = version ]; then echo "specify 0.11.2"; fi; exit 0'
if PATH="$bin:/usr/bin:/bin" CLAUDE_PROJECT_DIR="$proj" SPECKIT_BRAINSTORM_OFFLINE=1 bash "$SCRIPT" >/dev/null 2>&1; then
  echo "ok: offline exits 0"
else echo "FAIL: offline should exit 0"; fail=1; fi
# shellcheck disable=SC2015
grep -qF 'specify-cli --from git+https://github.com/github/spec-kit.git@v0.11.2' "$SHIM_LOG" \
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

# --- Bad CLAUDE_PROJECT_DIR: exit non-zero with ERROR ---
bin="$(mktemp -d)"; export SHIM_LOG="$bin/calls.log"; : > "$SHIM_LOG"
make_shim "$bin" uv      'exit 0'
make_shim "$bin" python3 'echo "Python 3.11.5"'
if PATH="$bin:/usr/bin:/bin" CLAUDE_PROJECT_DIR="/no/such/dir/xyz123" bash "$SCRIPT" >/dev/null 2>&1; then
  echo "FAIL: bad project dir should exit non-zero"; fail=1
else echo "ok: rejects bad project dir"; fi
err="$(PATH="$bin:/usr/bin:/bin" CLAUDE_PROJECT_DIR="/no/such/dir/xyz123" bash "$SCRIPT" 2>&1 >/dev/null || true)"
case "$err" in ERROR:*) echo "ok: bad project dir emits ERROR" ;; *) echo "FAIL: no ERROR for bad dir (got: $err)"; fail=1 ;; esac
rm -rf "$bin"

exit $fail
