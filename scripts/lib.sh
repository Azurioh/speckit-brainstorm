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
