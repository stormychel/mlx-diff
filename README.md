# OllamaReviewer

A zero-dependency CLI that reviews a git diff (or a GitHub PR) with a **local Ollama model** — defaulting to `qwen3-coder`. It exists to be a fully offline, quota-free rung in a code-review fallback chain (Codex → antigravity → Claude → **OllamaReviewer**), useful when cloud reviewers are rate-limited or unavailable.

The runner (Ollama) is fixed; the model is a one-word knob. Swap `qwen3-coder:latest` for any pulled model and nothing else about the invocation changes.

## Requirements

- [`ollama`](https://ollama.com) installed and running, with at least one model pulled:
  ```
  ollama pull qwen3-coder:latest
  ```
- `git` (always) and `gh` (only for `--pr` / `--comment`).

## Install

```bash
git clone git@github.com:stormychel/OllamaReviewer.git
ln -s "$PWD/OllamaReviewer/bin/ollama-review" /usr/local/bin/ollama-review
```

## Usage

```bash
# Review the local branch against its base
ollama-review --base main

# Use a different local model
ollama-review --model deepseek-coder-v2:latest

# Review a GitHub PR and post the result as a comment
ollama-review --pr 42 --comment
```

| Option | Description |
|--------|-------------|
| `--base <branch>` | Base branch to diff against (default: auto-detect `main`/`master`) |
| `--model <name>`  | Ollama model (default: `$OLLAMA_REVIEW_MODEL` or `qwen3-coder:latest`) |
| `--pr <number>`   | Review a GitHub PR diff instead of the local branch |
| `--comment`       | Post the review as a PR comment (requires `--pr`) |
| `-h, --help`      | Show help |

Set a persistent default model via the `OLLAMA_REVIEW_MODEL` env var.

## Caveats (v0.1)

- **Context window** — `ollama run` uses each model's default context, so large diffs get silently truncated. Bumping `num_ctx` for big PRs is tracked as an issue.
- Quality is below cloud reviewers (Codex) for subtle bugs; this is a *fallback*, not a replacement.

## Status

Early scaffold. See the [issues](https://github.com/stormychel/OllamaReviewer/issues) for the work needed to make it production-ready.
