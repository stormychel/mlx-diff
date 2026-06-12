# mlx-diff

A zero-dependency CLI that reviews a **git diff** (or a **GitHub PR**) with a **local [MLX](https://github.com/ml-explore/mlx) model** on Apple Silicon — defaulting to `Qwen3-Coder-30B-A3B-Instruct-8bit`. Fully offline, quota-free, and private: nothing leaves the machine.

It slots in as the **`mlx`** rung of a `codex / claude / mlx` review choice — the fast, free, local-first pass.

> **Apple Silicon only.** MLX does not run on Intel Macs or Linux. `mlx-diff` runs on bare-metal Apple-Silicon Macs and on **macOS-on-Apple-Silicon VMs** (Tart, UTM, Virtualization.framework). It hard-errors with a clear message anywhere else.

## Install

```bash
git clone https://github.com/stormychel/mlx-diff.git
cd mlx-diff
./install.sh
```

`install.sh` is idempotent: it verifies the host is Apple Silicon, installs `mlx-lm` via `pipx`, lets you **pick a model that fits this machine's RAM**, pre-pulls it, and symlinks `mlx-diff` into `~/.local/bin`. Re-run it any time to update or change model.

Skip the (large) model pre-pull with `MLXDIFF_SKIP_PULL=1 ./install.sh` — the model then downloads on first review.

## Choosing a model

On install, `mlx-diff` detects your system RAM, fetches the real (`.safetensors`) size of each curated coder model from HuggingFace, and color-ranks how well each fits — flagging the ones you already have downloaded. Bigger model = smarter, so the target is ~half your RAM (leaving room for the OS, other apps, and MLX's KV cache):

```text
==> Detected 64 GB system RAM. Sizing coder models (fetching live sizes)…

   1) ROOMY     3 GB  Qwen2.5-Coder-3B-Instruct-8bit
   2) ROOMY     7 GB  Qwen2.5-Coder-7B-Instruct-8bit
   3) ROOMY    14 GB  Qwen2.5-Coder-14B-Instruct-8bit
   4) ROOMY    16 GB  Qwen3-Coder-30B-A3B-Instruct-4bit
   5) ROOMY    17 GB  Qwen2.5-Coder-32B-Instruct-4bit
   6) PERFECT  30 GB  Qwen3-Coder-30B-A3B-Instruct-8bit    ✓ installed
   7) PERFECT  32 GB  Qwen2.5-Coder-32B-Instruct-8bit      ← recommended

  BAD >¾ RAM   TOUGH >½   PERFECT ≈½   ROOMY <½ (safe, smaller)

Pick a model [7]:
```

Each fit label is color-coded in a real terminal, and `✓ installed` marks models already in your HuggingFace cache (no download needed). Press Enter to take the recommendation, or type a number.

| Fit | Size vs RAM | Meaning |
|-----|-------------|---------|
| 🔴 **BAD** | > ¾ | Won't fit comfortably; risks swapping/OOM |
| 🟠 **TOUGH** | ½ – ¾ | Fits but tight, little headroom |
| 🟢 **PERFECT** | ≈ ½ | Sweet spot — biggest model with comfortable headroom |
| 🔵 **ROOMY** | < ½ | Safe and fast, but leaves capability on the table |

The recommendation is the **largest model that still fits comfortably** (≤ 60% of RAM). Your pick is saved to `~/.config/mlx-diff/model` and used as the default. Model resolution order: `--model` flag → `$MLXDIFF_MODEL` → that config file → built-in default.

## Usage

```bash
# Review the local branch against its base (auto-detects main/master)
mlx-diff --base main

# Use a different MLX model
mlx-diff --model mlx-community/Qwen2.5-Coder-32B-Instruct-8bit

# Review a GitHub PR and post the result as a comment
mlx-diff --pr 42 --comment

# Only ship-blockers and should-fixes, as JSON
mlx-diff --base main --min-severity P2 --json

# Smaller/faster 4-bit model
mlx-diff --base main --fast
```

| Option | Description |
|--------|-------------|
| `--base <branch>` | Base branch to diff against (default: auto-detect `main`/`master`) |
| `--pr <number>`   | Review a GitHub PR diff instead of the local branch |
| `--comment`       | Post the review as a single PR comment (requires `--pr`) |
| `--inline`        | Post findings as inline PR review comments (requires `--pr`; best-effort line anchoring) |
| `--json`          | Emit findings as a JSON array instead of text |
| `--min-severity <P1\|P2\|P3>` | Drop findings below this severity (default `P3` = keep all) |
| `--model <repo>`  | MLX model repo |
| `--fast`          | Use the 4-bit model (smaller/faster), or rewrite `8bit`→`4bit` in `--model` |
| `--server [url]`  | Use an OpenAI-compatible MLX server (default `http://127.0.0.1:8080`) |
| `--serve`         | Start `mlx_lm.server` for the current model and exit |
| `--no-chunk`      | Don't split large diffs into per-file reviews |
| `--update`        | Update mlx-diff to the latest release (`git pull`) and exit |
| `--version` / `-h`, `--help` | Print version / show help |

### Environment

| Variable | Default | Purpose |
|----------|---------|---------|
| `MLXDIFF_MODEL`        | `…Qwen3-Coder-30B-A3B-Instruct-8bit` | Default model repo |
| `MLXDIFF_MAX_TOKENS`   | `1200` | Max generated tokens |
| `MLXDIFF_TEMP`         | `0.2`  | Sampling temperature |
| `MLXDIFF_MIN_SEVERITY` | `P3`   | Minimum severity to report |
| `MLXDIFF_CHUNK_BYTES`  | `60000` | Diff size above which it reviews per-file |
| `MLXDIFF_SERVER_URL`   | —      | Use this OpenAI-compatible server |
| `MLXDIFF_PROMPT_FILE`  | —      | Use a custom system prompt from this file |
| `MLXDIFF_NO_UPDATE_CHECK` | —   | Set to `1` to disable the daily update check |
| `MLXDIFF_LOG`          | `$XDG_STATE_HOME/mlx-diff/runs.jsonl` | Run-trace log path |

## Configuration

Defaults can be set in a config file instead of flags/env. Precedence (low→high): built-in → `~/.config/mlx-diff/config` → repo-local `./.mlx-diffrc` → `MLXDIFF_*` env → flags.

```ini
# ~/.config/mlx-diff/config  (or ./.mlx-diffrc)
model = mlx-community/Qwen2.5-Coder-32B-Instruct-8bit
min_severity = P2
max_tokens = 1500
prompt_file = ~/.config/mlx-diff/prompt.txt   # custom reviewer prompt
```

The install-time model choice is stored at `~/.config/mlx-diff/model`.

## Large diffs & server mode

- **One-shot by default** — each review is a single fresh `mlx_lm.generate` call. Qwen3-Coder's 256k context handles realistic diffs in one pass, and the hardened prompt curbs repetition, so chunking is rarely needed.
- **Chunking** — only diffs over `MLXDIFF_CHUNK_BYTES` (250 KB) are split and reviewed **one file at a time**, each in its own fresh process. Disable with `--no-chunk`.
- **Server mode** (`--server` / `--serve`) — opt-in, for pointing reviews at your own `mlx_lm.server`. Note: `mlx_lm.server` reuses KV-cache state across requests and the review quality can degrade after the first request, so one-shot (the default) is recommended for reliability.

## Updating

```bash
mlx-diff --update    # git pull --ff-only on the install checkout
```
mlx-diff also checks for a newer release at most once/day and prints a one-line notice (disable with `MLXDIFF_NO_UPDATE_CHECK=1`).

## CI / GitHub Actions

`mlx-diff` can review PRs automatically on a **self-hosted Apple-Silicon runner** (MLX won't run on GitHub-hosted Linux). See [`.github/workflows/pr-review.yml.example`](.github/workflows/pr-review.yml.example) and [docs/vm-provisioning.md](docs/vm-provisioning.md).

## Traceability

Every review appends one JSON line to `~/.local/state/mlx-diff/runs.jsonl`:

```json
{"ts":"2026-06-12T09:40:00Z","engine":"mlx","model":"…Qwen3-Coder-30B-A3B-Instruct-8bit","source":"main...HEAD","repo":"/Users/you/Source/app","findings":3,"posted":false}
```

Tail it (`tail -f`) or pipe it through `jq` to audit what was reviewed, when, and with which model.

## Requirements

- Apple-Silicon macOS (bare metal or VM) — runs under the system `bash` 3.2
- `pipx` (the installer adds it via Homebrew if missing) → `mlx-lm`
- `git`; `gh` only for `--pr` / `--comment` / `--inline`; `curl` + `python3` for server mode and update checks

## Caveats

- A local 30B is a fast **first-pass triage** — strong on obvious-to-medium issues, weaker than a frontier cloud model on subtle correctness/concurrency bugs.
- `--inline` anchors comments to the line the model reports; findings without a parseable line fall back to a summary comment.

## Status

See [issues](https://github.com/stormychel/mlx-diff/issues) for tracked work.
