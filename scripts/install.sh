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
