# Local CLI setup

Tools needed to work with this repo. Pick the section for your distro, then run the post-install steps.

## Arch Linux

Most tools are in the official repos or AUR (install via your AUR helper of choice, e.g. `paru`/`yay`):

```bash
# Official repos
sudo pacman -S kubectl helm k9s kustomize kubectx direnv yamllint python python-pip nodejs npm

# AUR
paru -S kubeseal flux-bin talosctl-bin cilium-cli-bin kubeconform-bin
```

## Fedora

```bash
# Most tools have Fedora packages
sudo dnf install kubernetes-client helm kustomize direnv yamllint python3 python3-pip nodejs npm

# Flux: official one-liner
curl -s https://fluxcd.io/install.sh | sudo bash

# Talosctl, k9s, kubeseal, cilium-cli, kubectx/kubens, kubeconform:
# download the latest release binary from GitHub for each, then move to /usr/local/bin.
# Upstream links:
#   talosctl    — https://github.com/siderolabs/talos/releases
#   k9s         — https://github.com/derailed/k9s/releases
#   kubeseal    — https://github.com/bitnami-labs/sealed-secrets/releases
#   cilium-cli  — https://github.com/cilium/cilium-cli/releases
#   kubectx     — https://github.com/ahmetb/kubectx (kubectx + kubens scripts)
#   kubeconform — https://github.com/yannh/kubeconform/releases
```

## All distros — language toolchains

```bash
# Python tools used by pre-commit hooks
pip install --user pre-commit detect-secrets

# Claude Code CLI
npm install -g @anthropic-ai/claude-code
```

## Post-install

In the repo root:

```bash
pre-commit install      # installs git hooks for yamllint + detect-secrets
direnv allow            # if any .envrc is added later
```

## What each tool is for

| Tool | Use |
|---|---|
| `kubectl` | Talking to the cluster |
| `helm` | Inspecting Helm charts; not used to deploy (Flux does that) |
| `flux` | Reconciling, suspending, debugging Flux Kustomizations / HelmReleases |
| `kustomize` | Previewing rendered manifests (`kubectl kustomize <path>`) |
| `talosctl` | Talos node admin (config apply, upgrade, etcd, logs) |
| `cilium` | Installing Cilium (out-of-band, not via Flux), `cilium status` |
| `kubeseal` | Encrypting secrets against the cluster's sealed-secrets public key |
| `k9s` | TUI for browsing cluster state |
| `kubectx` / `kubens` | Switch contexts and namespaces |
| `kubeconform` | Schema-validate manifests locally (mirrors CI) |
| `yamllint` | YAML linting (mirrors CI) |
| `pre-commit` | Runs yamllint + detect-secrets on commit |
| `detect-secrets` | Catches accidental secrets in commits |
| `direnv` | Auto-loads per-directory env vars |
