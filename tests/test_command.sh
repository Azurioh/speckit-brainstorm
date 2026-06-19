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
need "taskstoissues step"           'taskstoissues'
need "issue quality rules block"    'Issue quality rules'
need "acceptance criteria rule"     'acceptance criteria'

# stub marker must be gone
if grep -q 'full orchestrator prompt added in Task 5' "$CMD"; then echo "FAIL: still a stub"; fail=1; else echo "ok: stub replaced"; fi
exit $fail
