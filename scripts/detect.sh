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
  # shellcheck disable=SC2012
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
