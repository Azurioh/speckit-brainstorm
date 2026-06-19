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

# resolve_latest_tag falls back to grep/sed when jq is absent
bin="$(mktemp -d)"
printf '#!/bin/sh\necho "{\\"tag_name\\":\\"v8.8.8\\"}"\n' > "$bin/curl"
chmod +x "$bin/curl"
for t in grep sed head; do p="$(command -pv "$t" 2>/dev/null || true)"; [ -n "$p" ] && ln -sf "$p" "$bin/$t"; done
out="$(PATH="$bin" resolve_latest_tag)"
chk "grep fallback parses tag when jq absent" "$out" "v8.8.8"
rm -rf "$bin"

exit $fail
