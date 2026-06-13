#!/usr/bin/env bash
#
#  install.sh
#  mlx-diff
#
#  Created by Michel Storms on 12/06/2026.
#
#  Idempotent installer: verifies the host, installs mlx-lm, lets you pick a
#  coder model that fits this machine's RAM, pre-pulls it, and symlinks the CLI
#  onto PATH. Safe to re-run.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_SRC="$REPO_DIR/bin/mlx-diff"
BIN_DEST="${MLXDIFF_BIN_DIR:-$HOME/.local/bin}/mlx-diff"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/mlx-diff"

# Curated coder models, smallest → largest, as "repo<TAB>fallback-size-GiB".
# The real size is fetched live from HuggingFace; the fallback is used offline.
CURATED=(
  "mlx-community/Qwen2.5-Coder-3B-Instruct-8bit	3"
  "mlx-community/Qwen2.5-Coder-7B-Instruct-8bit	8"
  "mlx-community/Qwen2.5-Coder-14B-Instruct-8bit	15"
  "mlx-community/Qwen3-Coder-30B-A3B-Instruct-4bit	16"
  "mlx-community/Qwen2.5-Coder-32B-Instruct-4bit	17"
  "mlx-community/Qwen3-Coder-30B-A3B-Instruct-8bit	30"
  "mlx-community/Qwen2.5-Coder-32B-Instruct-8bit	33"
)

# Frontier tier: state-of-the-art open models (GLM-5, Kimi K2.7) that rival the
# top proprietary US models — but need ~400-600 GB RAM (a 512 GB+ Mac Studio).
# Listed so the picker acknowledges them; never recommended, always flagged.
FRONTIER=(
  "mlx-community/GLM-5-4bit	390"
  "mlx-community/Kimi-K2.7-Code-4bit	597"
)

# Colors (only when stdout is a terminal).
if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RST=$'\033[0m'
  RED=$'\033[31m'; GREEN=$'\033[32m'; BLUE=$'\033[34m'; ORANGE=$'\033[38;5;208m'; MAGENTA=$'\033[38;5;201m'
else
  BOLD=""; DIM=""; RST=""; RED=""; GREEN=""; BLUE=""; ORANGE=""; MAGENTA=""
fi

say() { printf '%s==>%s %s\n' "$BOLD" "$RST" "$1"; }
die() { printf '%serror:%s %s\n' "$RED" "$RST" "$1" >&2; exit 1; }

# HuggingFace auth: a token (HF_TOKEN env, or a cached `hf auth login` token)
# avoids rate limits and the "unauthenticated requests" warning on downloads.
hf_token() {
  if [[ -n "${HF_TOKEN:-}" ]]; then printf '%s' "$HF_TOKEN"; return; fi
  local f="${HF_HOME:-$HOME/.cache/huggingface}/token"
  [[ -r "$f" ]] && tr -d '[:space:]' < "$f"
}
hf_get() {                          # $1 = url → body (authenticated if a token exists)
  local tok; tok="$(hf_token)"
  if [[ -n "$tok" ]]; then curl -sS -m 20 -H "Authorization: Bearer $tok" "$1" 2>/dev/null
  else curl -sS -m 20 "$1" 2>/dev/null; fi
}

# size_gib <repo> <fallback> — echo the .safetensors weight size in GiB (integer).
size_gib() {
  local bytes=""
  if command -v curl >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    bytes="$(hf_get "https://huggingface.co/api/models/$1?blobs=true" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    print(sum(s.get("size", 0) for s in d.get("siblings", [])
              if s.get("rfilename", "").endswith(".safetensors")))
except Exception:
    print(0)' 2>/dev/null)"
  fi
  if [[ -n "$bytes" && "$bytes" -gt 0 ]]; then
    echo $(( bytes / 1073741824 ))
  else
    echo "$2"
  fi
}

# classify <size_gib> <ram_gib> — echo "COLOR<TAB>LABEL". Bigger model = smarter,
# so the target is ~half RAM (room for the OS, other apps, and the KV cache).
classify() {
  local pct=$(( $1 * 100 / $2 ))
  if   (( pct > 75 )); then printf '%s\tBAD'     "$RED"
  elif (( pct > 60 )); then printf '%s\tTOUGH'   "$ORANGE"
  elif (( pct >= 45 )); then printf '%s\tPERFECT' "$GREEN"
  else                      printf '%s\tROOMY'   "$BLUE"; fi
}

# Resolve the HuggingFace hub cache dir and report whether a model is present.
hf_hub_dir() {
  if   [[ -n "${HF_HUB_CACHE:-}" ]]; then printf '%s' "$HF_HUB_CACHE"
  elif [[ -n "${HF_HOME:-}" ]];      then printf '%s/hub' "$HF_HOME"
  else printf '%s/.cache/huggingface/hub' "$HOME"; fi
}
model_cached() {  # $1 repo
  local d; d="$(hf_hub_dir)/models--${1//\//--}/snapshots"
  [[ -d "$d" ]] || return 1
  local s; for s in "$d"/*/; do [[ -e "$s" ]] && return 0; done
  return 1
}

# 1. Host check — MLX is Apple-Silicon-only.
[[ "$(uname -s)/$(uname -m)" == "Darwin/arm64" ]] || \
  die "mlx-diff requires Apple Silicon macOS — MLX is unsupported on $(uname -s)/$(uname -m)."
say "Host OK: $(uname -s) $(uname -m)"

# HuggingFace token nudge (downloads are rate-limited / warn without one).
if [[ -n "$(hf_token)" ]]; then
  say "HuggingFace token detected — authenticated downloads."
else
  say "No HuggingFace token — downloads may be slow/rate-limited."
  say "  Optional: export HF_TOKEN=hf_…  (or run: hf auth login)  then re-run."
fi

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

# 4. Pick a model that fits this machine's RAM.
RAM_GIB=$(( $(sysctl -n hw.memsize 2>/dev/null || echo 0) / 1073741824 ))
(( RAM_GIB > 0 )) || RAM_GIB=8
say "Detected ${RAM_GIB} GB system RAM. Sizing coder models (fetching live sizes)…"
printf '\n'

repos=(); sizes=(); labels=(); colors=(); cached=()
rec=0; rec_size=-1
i=0
for entry in "${CURATED[@]}"; do
  repo="${entry%%$'\t'*}"; fb="${entry##*$'\t'}"
  s="$(size_gib "$repo" "$fb")"
  IFS=$'\t' read -r color label <<<"$(classify "$s" "$RAM_GIB")"
  repos+=("$repo"); sizes+=("$s"); labels+=("$label"); colors+=("$color")
  if model_cached "$repo"; then cached+=("1"); else cached+=("0"); fi
  # Recommend the largest model that still fits comfortably (<= top of PERFECT).
  if (( s * 100 / RAM_GIB <= 60 )) && (( s > rec_size )); then rec=$i; rec_size=$s; fi
  i=$(( i + 1 ))
done
# If nothing fits comfortably (low-RAM machine), recommend the smallest model.
(( rec_size < 0 )) && rec=0

short() { printf '%s' "${1##*/}"; }
for j in "${!repos[@]}"; do
  mark=""
  (( j == rec )) && mark="${mark} ${BOLD}← recommended${RST}"
  [[ "${cached[$j]}" == 1 ]] && mark=" ${GREEN}✓ installed${RST}${mark}"
  printf '  %s%2d%s) %s%-7s%s %3s GB  %s%-36s%s%s\n' \
    "$BOLD" "$(( j + 1 ))" "$RST" \
    "${colors[$j]}" "${labels[$j]}" "$RST" "${sizes[$j]}" \
    "$DIM" "$(short "${repos[$j]}")" "$RST" "$mark"
done
printf '\n  %sBAD%s >¾ RAM   %sTOUGH%s >½   %sPERFECT%s ≈½   %sROOMY%s <½ (safe, smaller)\n\n' \
  "$RED" "$RST" "$ORANGE" "$RST" "$GREEN" "$RST" "$BLUE" "$RST"

# Frontier models, listed separately and never recommended: huge open models that
# only a 512 GB+ Mac Studio can run. Appended to the selectable list so a user on
# such hardware can still pick one by number.
if (( ${#FRONTIER[@]} > 0 )); then
  printf '  %sFRONTIER%s — open models rivaling top US models; need a 512 GB+ Mac Studio:\n' "$MAGENTA" "$RST"
  for entry in "${FRONTIER[@]}"; do
    frepo="${entry%%$'\t'*}"; ffb="${entry##*$'\t'}"
    fs="$(size_gib "$frepo" "$ffb")"
    repos+=("$frepo"); sizes+=("$fs"); labels+=("FRONTIER"); colors+=("$MAGENTA")
    if model_cached "$frepo"; then cached+=("1"); else cached+=("0"); fi
    fj=$(( ${#repos[@]} - 1 )); fmark=""
    [[ "${cached[$fj]}" == 1 ]] && fmark=" ${GREEN}✓ installed${RST}"
    printf '  %s%2d%s) %s%-7s%s %3s GB  %s%-36s%s%s\n' \
      "$BOLD" "$(( fj + 1 ))" "$RST" "$MAGENTA" "FRONTIER" "$RST" "$fs" \
      "$DIM" "$(short "$frepo")" "$RST" "$fmark"
  done
  printf '\n'
fi

choice=$(( rec + 1 ))
if [[ -t 0 ]]; then
  read -r -p "Pick a model [${choice}]: " reply || true
  if [[ -n "${reply:-}" ]]; then
    if ! [[ "$reply" =~ ^[0-9]+$ ]] || (( reply < 1 || reply > ${#repos[@]} )); then
      die "invalid choice: $reply"
    fi
    choice="$reply"
  fi
fi
CHOSEN="${repos[$(( choice - 1 ))]}"

# A frontier pick is a 400-600 GB download that needs a 512 GB+ Mac — confirm it.
for entry in "${FRONTIER[@]}"; do
  [[ "${entry%%$'\t'*}" == "$CHOSEN" ]] || continue
  say "${MAGENTA}FRONTIER${RST} model: ${CHOSEN##*/} — needs a 512 GB+ Mac Studio; the download is hundreds of GB."
  if [[ -t 0 ]]; then
    read -r -p "Select and pre-pull it anyway? [y/N]: " yn || true
    [[ "${yn:-}" =~ ^[Yy] ]] || die "Frontier selection aborted."
  fi
  break
done

say "Selected: $CHOSEN"

# Persist the choice so the CLI uses it as the default model.
mkdir -p "$CONFIG_DIR"
printf '%s\n' "$CHOSEN" > "$CONFIG_DIR/model"

# 5. Pre-pull the chosen model — but only if it isn't already cached. (Loading a
#    30 GB model just to warm it up is pointless when it's already downloaded.)
#    stderr stays attached so HuggingFace's download bars are visible; only the
#    throwaway generation on stdout is discarded.
if model_cached "$CHOSEN"; then
  say "$CHOSEN is already installed — nothing to download."
elif [[ "${MLXDIFF_SKIP_PULL:-0}" == "1" ]]; then
  say "Skipping model download (MLXDIFF_SKIP_PULL=1) — it will download on first review."
else
  say "Pre-pulling $CHOSEN (set MLXDIFF_SKIP_PULL=1 to skip)…"
  if mlx_lm.generate --model "$CHOSEN" --prompt "ok" --max-tokens 1 --verbose False >/dev/null; then
    say "Model ready."
  else
    say "Model pull/warm-up failed or was interrupted — it will download on first real review."
  fi
fi

# 5b. Lifeboat: keep the smallest curated model cached as a guaranteed-fits
#     fallback, so a low-RAM machine always has something to fall back to when
#     the chosen model won't fit. Skip with MLXDIFF_SKIP_LIFEBOAT=1.
LIFEBOAT="${repos[0]}"
if [[ "${MLXDIFF_SKIP_LIFEBOAT:-0}" != "1" && "$CHOSEN" != "$LIFEBOAT" ]]; then
  if model_cached "$LIFEBOAT"; then
    say "Lifeboat model already cached: ${LIFEBOAT##*/}"
  elif [[ "${MLXDIFF_SKIP_PULL:-0}" != "1" ]]; then
    say "Pulling lifeboat model ${LIFEBOAT##*/} (~${sizes[0]} GB) — your offline fallback…"
    if mlx_lm.generate --model "$LIFEBOAT" --prompt "ok" --max-tokens 1 --verbose False >/dev/null 2>&1; then
      say "Lifeboat ready."
    else
      say "Lifeboat pull skipped/failed — fetch it later with: MLXDIFF_MODEL=$LIFEBOAT mlx-diff --base main"
    fi
  fi
fi

# 6. Symlink the CLI onto PATH.
mkdir -p "$(dirname "$BIN_DEST")"
ln -sf "$BIN_SRC" "$BIN_DEST"
chmod +x "$BIN_SRC"
say "Linked $BIN_DEST -> $BIN_SRC"

case ":$PATH:" in
  *":$(dirname "$BIN_DEST"):"*) ;;
  *) say "NOTE: $(dirname "$BIN_DEST") is not on your PATH — add it to your shell profile." ;;
esac

say "Done. Try:  mlx-diff --help"
