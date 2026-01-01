#!/bin/bash
set -e

# Install Tetragon CLI (tetra)
echo "Installing Tetragon CLI..."
ARCH=$(uname -m)
case $ARCH in
  x86_64) ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
esac

curl -L "https://github.com/cilium/tetragon/releases/latest/download/tetra-linux-${ARCH}.tar.gz" | \
  sudo tar -xz -C /usr/local/bin

echo "Tetragon CLI installed successfully"
tetra version || echo "Tetra installed (version check requires cluster connection)"
