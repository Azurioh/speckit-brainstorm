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
check "plugin.json valid JSON"    "python3 -c 'import json;json.load(open(\"$PJ\"))'"
check "marketplace.json valid"    "python3 -c 'import json;json.load(open(\"$MK\"))'"
check "plugin name correct"       "python3 -c 'import json;assert json.load(open(\"$PJ\"))[\"name\"]==\"speckit-brainstorm\"'"
check "marketplace has owner"     "python3 -c 'import json;assert json.load(open(\"$MK\"))[\"owner\"][\"name\"]'"
check "marketplace lists plugin"  "python3 -c 'import json;p=json.load(open(\"$MK\"))[\"plugins\"];assert any(x[\"name\"]==\"speckit-brainstorm\" for x in p)'"
check "command has description"   "grep -q '^description:' '$CMD'"

exit $fail
