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
