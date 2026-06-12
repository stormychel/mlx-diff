# Running mlx-diff on a macOS-on-Apple-Silicon VM

MLX is Apple-Silicon-only, so `mlx-diff` runs on bare-metal Macs **or** macOS VMs running on Apple-Silicon hosts. Linux VMs are not supported. This covers provisioning such a VM and (optionally) wiring it up as a GitHub Actions self-hosted runner for [#8](https://github.com/stormychel/mlx-diff/issues/8).

## 1. Create the VM

Any Apple-Virtualization-based tool works. [Tart](https://tart.run) is the simplest for headless/CI use:

```bash
brew install cirruslabs/cli/tart
tart clone ghcr.io/cirruslabs/macos-sequoia-base:latest mlx-diff-vm
tart set mlx-diff-vm --cpu 8 --memory 24576        # 24 GB RAM → fits a 14B-8bit / 30B-4bit model
tart run mlx-diff-vm
```

UTM or `Virtualization.framework` directly work too — the only requirement is **macOS guest on an Apple-Silicon host**.

### Sizing

The model is held in RAM, so size the VM's memory to the model (see the fit table in the README — target ~½ of guest RAM). Rough guide:

| Guest RAM | Comfortable model |
|-----------|-------------------|
| 16 GB | `Qwen2.5-Coder-7B-Instruct-8bit` (~8 GB) |
| 24 GB | `Qwen2.5-Coder-14B-8bit` / `Qwen3-Coder-30B-A3B-4bit` (~16 GB) |
| 48 GB+ | `Qwen3-Coder-30B-A3B-8bit` (~30 GB) |

Disk: allow **~2× the model size** (HuggingFace keeps blobs + a snapshot). The cache lives in `~/.cache/huggingface`.

## 2. Install mlx-diff in the guest

```bash
git clone https://github.com/stormychel/mlx-diff.git
cd mlx-diff
./install.sh          # picks a model that fits the guest's RAM
```

For headless installs, skip the interactive picker and pre-pull a specific model:

```bash
MLXDIFF_MODEL=mlx-community/Qwen2.5-Coder-14B-Instruct-8bit ./install.sh </dev/null
```

## 3. Headless usage

```bash
# keep a server warm so repeated reviews are instant (no per-run reload)
mlx-diff --serve &

# review a PR and post the result
GH_TOKEN=… mlx-diff --pr 42 --server --comment --min-severity P2
```

## 4. As a GitHub Actions self-hosted runner

Register the VM as a runner (Settings → Actions → Runners → New self-hosted runner) with labels `self-hosted, macOS, ARM64`, then copy
[`.github/workflows/pr-review.yml.example`](../.github/workflows/pr-review.yml.example) into your repo's `.github/workflows/` and rename it to `pr-review.yml`.

The workflow runs `mlx-diff --pr <n> --comment` on each PR. Because the runner is self-hosted, no model weights leave your machine and there are no API costs.
