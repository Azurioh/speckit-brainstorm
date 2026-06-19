#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

echo "== shellcheck =="
shellcheck -x "$ROOT"/scripts/*.sh "$ROOT"/tests/*.sh || fail=1

for t in "$ROOT"/tests/test_*.sh; do
  echo "== $(basename "$t") =="
  bash "$t" || fail=1
done

if [ "$fail" -eq 0 ]; then echo "ALL GREEN"; else echo "FAILURES ABOVE"; fi
exit $fail
