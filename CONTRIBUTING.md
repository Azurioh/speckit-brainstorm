# Contributing to speckit-brainstorm

Thanks for your interest in improving **speckit-brainstorm** — a Claude Code plugin that
guides users through the GitHub Spec Kit workflow by conversation.

This project is small and shell-based. The rules below keep it consistent, tested, and easy
to review.

## Ground rules

- **Language: English.** All code, comments, commit messages, issues, and pull requests are
  written in English, regardless of the language used to discuss them.
- **Be respectful.** Assume good faith, keep feedback constructive, and focus on the change.
- **Keep changes focused.** One concern per pull request. Split unrelated work.

## Project layout

| Path                          | What it is                                              |
| ----------------------------- | ------------------------------------------------------ |
| `commands/speckit-brainstorm.md` | The command prompt — the heart of the plugin.       |
| `scripts/`                    | Bundled bash helpers (`lib.sh`, `detect.sh`, `install.sh`). |
| `tests/`                      | Test suite; `run.sh` is the entry point.               |
| `.claude-plugin/`             | Plugin and marketplace manifests.                      |
| `docs/`                       | Specs and plans.                                       |

## Getting set up

You need `bash` and the dev tools the suite relies on:

- [`shellcheck`](https://www.shellcheck.net/) — every script and test must pass it.
- `curl` and (optionally) `jq` — used by `scripts/lib.sh` at runtime.
- [`uv`](https://docs.astral.sh/uv/) and Python ≥ 3.11 — only to exercise the speckit install path.

Clone, then run the suite to confirm a clean baseline:

```bash
bash tests/run.sh
```

A passing run ends with `ALL GREEN`.

## Development workflow

1. **Branch** off `main`. Use a descriptive name (`feat/windows-detect`, `fix/install-guard`).
2. **Make the change**, following the conventions below.
3. **Add or update tests** for any behavior you change (see [Testing](#testing)).
4. **Run `bash tests/run.sh`** and make sure it is green before pushing.
5. **Open a pull request** against `main` with a clear description of *what* and *why*.

Never mark work done while `tests/run.sh` reports failures or shellcheck warnings.

## Shell conventions

The scripts are intentionally portable and defensive. Match the existing style:

- Start every script with `#!/usr/bin/env bash`.
- Set strict mode at the top: `set -uo pipefail` (add `-e` only where the script is meant to
  abort on the first error).
- `scripts/lib.sh` is **sourced, not executed** — keep it side-effect free (function
  definitions only).
- Quote all expansions (`"$var"`), prefer `[ ... ]`/`[[ ... ]]` consistently with nearby code.
- Comment the *why*, not the *what*. Each helper gets a one-line header comment describing
  its contract (see `have()` / `resolve_latest_tag()` for the pattern).
- Helpers must be **best-effort and never fail their caller** unless failure is the point.
  Honor existing escape hatches like `SPECKIT_BRAINSTORM_OFFLINE=1`.
- No magic values — give constants meaningful names.
- Every script and test **must pass `shellcheck -x`**.

## Editing the command prompt

`commands/speckit-brainstorm.md` is a prompt, not code, but it has hard invariants:

- The YAML frontmatter (`description`, `argument-hint`, `allowed-tools`) must stay valid.
- The **preview-and-confirm gate** is non-negotiable: the command must never run a speckit
  phase or a shell/install command without first showing exactly what will run and waiting
  for the user's go-ahead.
- If you change the user-facing description, keep the `description` in
  `commands/speckit-brainstorm.md` and `.claude-plugin/plugin.json` aligned
  (`.claude-plugin/marketplace.json` intentionally carries a shorter one-liner).
  `tests/test_manifests.sh` validates the manifests' structure and names.

## Testing

- Tests live in `tests/test_*.sh` and are plain bash — no framework.
- `tests/run.sh` runs `shellcheck` first, then every `test_*.sh`, and prints `ALL GREEN`
  or `FAILURES ABOVE`.
- Follow the existing harness style: a `chk "name" "$got" "$want"` helper, `ok:` / `FAIL:`
  lines, and `fail=1` on mismatch.
- Keep tests **hermetic**: stub external commands (e.g. a `curl` shim in a temp `PATH`)
  instead of hitting the network. Clean up temp dirs you create.
- Any new behavior in `scripts/` needs a matching test; any bug fix should come with a test
  that fails before the fix.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>: <imperative summary in the present tense>
```

Common types in this repo: `feat`, `fix`, `docs`, `test`, `refactor`, `chore`, and `harden`
(for robustness/security improvements). Keep the subject under ~72 characters; add a body
when the *why* isn't obvious from the diff.

Examples:

```
feat: add taskstoissues step with issue quality rules
fix: guard bad project dir and tighten install.sh tests
harden: legible plugin-path failure + jq-absent fallback test
docs: add README and full test runner
```

## Pull requests

- Title in Conventional Commit style; description explains the change and how you verified it.
- Confirm `bash tests/run.sh` is green and paste the result if relevant.
- Reference related issues (`Closes #123`).
- Bump `version` in `.claude-plugin/plugin.json` when the change is user-facing, following
  [semantic versioning](https://semver.org/).
- Keep diffs minimal and on-topic; unrelated cleanup goes in its own PR.

## Reporting bugs and proposing features

Open an issue with:

- **Bugs:** what you did, what you expected, what happened, and your OS/shell. Include the
  exact command output (quoted verbatim).
- **Features:** the problem you're trying to solve before the proposed solution.

## License

By contributing, you agree that your contributions are licensed under the project's
[MIT License](LICENSE).
