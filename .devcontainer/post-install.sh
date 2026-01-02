#!/bin/bash
set -e

# Install Tetragon CLI (tetra)
echo "Installing Tetragon CLI..."
ARCH=$(uname -m)
case $ARCH in
x86_64) ARCH="amd64" ;;
aarch64) ARCH="arm64" ;;
esac

curl -L "https://github.com/cilium/tetragon/releases/latest/download/tetra-linux-${ARCH}.tar.gz" |
  sudo tar -xz -C /usr/local/bin

echo "Tetragon CLI installed successfully"
tetra version || echo "Tetra installed (version check requires cluster connection)"

# Install kubeconform
echo "Installing kubeconform..."
KUBE_VERSION="v0.7.0"
ARCH=$(uname -m)
case $ARCH in
x86_64) ARCH="amd64" ;;
aarch64) ARCH="arm64" ;;
esac
curl -L "https://github.com/yannh/kubeconform/releases/download/${KUBE_VERSION}/kubeconform-linux-${ARCH}.tar.gz" |
  sudo tar -xz -C /usr/local/bin
echo "kubeconform installed successfully"

# Install pre-commit and detect-secrets
echo "Installing pre-commit and detect-secrets..."
pip install --user pre-commit detect-secrets

# Install pre-commit hooks
if [ -f .pre-commit-config.yaml ]; then
  echo "Installing git hooks..."
  ~/.local/bin/pre-commit install
  echo "Pre-commit hooks installed successfully"
else
  echo "Warning: .pre-commit-config.yaml not found, skipping hook installation"
fi
