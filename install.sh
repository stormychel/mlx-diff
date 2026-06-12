#!/usr/bin/env bash
#
#  install.sh
#  mlx-diff
#
#  Created by Michel Storms on 12/06/2026.
#
#  Idempotent installer: verifies the host, installs mlx-lm, pre-pulls the
#  default model, and symlinks the CLI onto PATH. Safe to re-run.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_SRC="$REPO_DIR/bin/mlx-diff"
BIN_DEST="${MLXDIFF_BIN_DIR:-$HOME/.local/bin}/mlx-diff"
DEFAULT_MODEL="${MLXDIFF_MODEL:-mlx-community/Qwen3-Coder-30B-A3B-Instruct-8bit}"

say() { printf '\033[1m==>\033[0m %s\n' "$1"; }
die() { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

# 1. Host check — MLX is Apple-Silicon-only.
[[ "$(uname -s)/$(uname -m)" == "Darwin/arm64" ]] || \
  die "mlx-diff requires Apple Silicon macOS — MLX is unsupported on $(uname -s)/$(uname -m)."
say "Host OK: $(uname -s) $(uname -m)"

# 2. pipx
if ! command -v pipx >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    say "Installing pipx via Homebrew…"
    brew install pipx
    pipx ensurepath
  else
    die "pipx not found and Homebrew unavailable. Install pipx, then re-run."
  fi
fi
say "pipx: $(command -v pipx)"

# 3. mlx-lm
if ! command -v mlx_lm.generate >/dev/null 2>&1; then
  say "Installing mlx-lm via pipx…"
  pipx install mlx-lm
else
  say "mlx-lm already installed: $(command -v mlx_lm.generate)"
fi

# 4. Pre-pull the default model (so first review isn't a cold multi-GB download).
#    stderr is left attached so HuggingFace's download progress bars are visible;
#    only stdout (the throwaway generation) is discarded.
if [[ "${MLXDIFF_SKIP_PULL:-0}" != "1" ]]; then
  say "Pre-pulling model: $DEFAULT_MODEL (this can be large; set MLXDIFF_SKIP_PULL=1 to skip)…"
  if mlx_lm.generate --model "$DEFAULT_MODEL" --prompt "ok" --max-tokens 1 --verbose False >/dev/null; then
    say "Model ready."
  else
    say "Model pull/warm-up failed or was interrupted — it will download on first real review."
  fi
fi

# 5. Symlink the CLI onto PATH.
mkdir -p "$(dirname "$BIN_DEST")"
ln -sf "$BIN_SRC" "$BIN_DEST"
chmod +x "$BIN_SRC"
say "Linked $BIN_DEST -> $BIN_SRC"

case ":$PATH:" in
  *":$(dirname "$BIN_DEST"):"*) ;;
  *) say "NOTE: $(dirname "$BIN_DEST") is not on your PATH — add it to your shell profile." ;;
esac

say "Done. Try:  mlx-diff --help"
