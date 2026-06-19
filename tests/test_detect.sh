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

# Fixture D: a feature dir name containing a double quote must not break JSON
tmp="$(mktemp -d)"
mkdir -p "$tmp/.specify" "$tmp/specs/00\"x"
echo '{}' > "$tmp/.specify/feature.json"
OUT="$(CLAUDE_PROJECT_DIR="$tmp" SPECKIT_BRAINSTORM_OFFLINE=1 bash "$SCRIPT")"
if printf '%s' "$OUT" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null; then
  echo "ok: valid JSON when feature name has a quote"
else
  echo "FAIL: invalid JSON when feature name has a quote"; echo "  got: $OUT"; fail=1
fi
got_feature="$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["feature"])')"
if [ "$got_feature" = '00"x' ]; then echo "ok: feature round-trips with quote"; else echo "FAIL: feature='$got_feature'"; fail=1; fi
rm -rf "$tmp"

exit $fail
