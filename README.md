# localreview

A zero-dependency CLI that reviews a **git diff** (or a **GitHub PR**) with a **local [MLX](https://github.com/ml-explore/mlx) model** on Apple Silicon — defaulting to `Qwen3-Coder-30B-A3B-Instruct-8bit`. Fully offline, quota-free, and private: nothing leaves the machine.

It slots in as the **`mlx`** rung of a `codex / claude / mlx` review choice — the fast, free, local-first pass.

> **Apple Silicon only.** MLX does not run on Intel Macs or Linux. `localreview` runs on bare-metal Apple-Silicon Macs and on **macOS-on-Apple-Silicon VMs** (Tart, UTM, Virtualization.framework). It hard-errors with a clear message anywhere else.

## Install

```bash
git clone https://github.com/stormychel/localreview.git
cd localreview
./install.sh
```

`install.sh` is idempotent: it verifies the host is Apple Silicon, installs `mlx-lm` via `pipx`, pre-pulls the default model, and symlinks `localreview` into `~/.local/bin`. Re-run it any time to update.

Skip the (large) model pre-pull with `LOCALREVIEW_SKIP_PULL=1 ./install.sh` — the model then downloads on first review.

## Usage

```bash
# Review the local branch against its base (auto-detects main/master)
localreview --base main

# Use a different MLX model
localreview --model mlx-community/Qwen2.5-Coder-32B-Instruct-8bit

# Review a GitHub PR and post the result as a comment
localreview --pr 42 --comment
```

| Option | Description |
|--------|-------------|
| `--base <branch>` | Base branch to diff against (default: auto-detect `main`/`master`) |
| `--pr <number>`   | Review a GitHub PR diff instead of the local branch |
| `--comment`       | Post the review as a PR comment (requires `--pr`) |
| `--model <name>`  | MLX model repo (default: `$LOCALREVIEW_MODEL` or the bundled Qwen3-Coder) |
| `--version`       | Print version |
| `-h, --help`      | Show help |

### Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `LOCALREVIEW_MODEL`      | `mlx-community/Qwen3-Coder-30B-A3B-Instruct-8bit` | Default model repo |
| `LOCALREVIEW_MAX_TOKENS` | `2000` | Max generated tokens |
| `LOCALREVIEW_TEMP`       | `0.2`  | Sampling temperature |
| `LOCALREVIEW_LOG`        | `$XDG_STATE_HOME/localreview/runs.jsonl` | Run-trace log path |

## Traceability

Every review appends one JSON line to `~/.local/state/localreview/runs.jsonl`:

```json
{"ts":"2026-06-12T09:40:00Z","engine":"mlx","model":"mlx-community/Qwen3-Coder-30B-A3B-Instruct-8bit","source":"main...HEAD","repo":"/Users/you/Source/app","review_chars":612,"posted":false}
```

Tail it (`tail -f`) or pipe it through `jq` to audit what was reviewed, when, and with which model.

## Requirements

- Apple-Silicon macOS (bare metal or VM)
- `pipx` (the installer adds it via Homebrew if missing) → `mlx-lm`
- `git`; `gh` only for `--pr` / `--comment`

## Caveats

- A local 30B is a fast **first-pass triage** — strong on obvious-to-medium issues, weaker than a frontier cloud model on subtle correctness/concurrency bugs.
- Very large diffs (>200 KB) are slow and may exceed the model's context; `localreview` warns past that threshold.

## Status

See [issues](https://github.com/stormychel/localreview/issues) for tracked work.
