# Cluster Setup Guide

## Talos Image

**Current version**: Talos v1.12.6

[Image Factory configuration page](https://factory.talos.dev/?arch=amd64&board=undefined&bootloader=auto&cmdline-set=true&extensions=-&extensions=siderolabs%2Fintel-ucode&extensions=siderolabs%2Fqemu-guest-agent&platform=nocloud&secureboot=undefined&target=cloud&version=1.12.6)

Extensions:
```yaml
customization:
  systemExtensions:
    officialExtensions:
      # or amd-ucode for AMD CPUs
      - siderolabs/intel-ucode
      # Proxmox/QEMU integration (clean shutdown, IP reporting)
      - siderolabs/qemu-guest-agent
```

**Schematic ID**: `e3fab82b561b5e559cdf1c0b1e5950c0e52700b9208a2cfaa5b18454796f3a7e`

Installer image (for both initial install and `talosctl upgrade`):
```
factory.talos.dev/nocloud-installer/e3fab82b561b5e559cdf1c0b1e5950c0e52700b9208a2cfaa5b18454796f3a7e:v1.12.6
```

> **Note**: `rbd` and `ceph` kernel modules are compiled directly into the Talos kernel — no extensions needed for Rook Ceph storage.

### Upgrading Talos

Upgrade one node at a time. If config changes are pending (e.g., new kubelet mounts), stage them first so they take effect in the same reboot:

```bash
# 1. Stage config changes (applied on next reboot, no reboot yet)
talosctl apply-config --file <node-config>.yaml --mode=staged --nodes <node-ip>

# 2. Upgrade Talos image (reboots, picks up staged config)
talosctl upgrade --image factory.talos.dev/nocloud-installer/<schematic-id>:v1.12.6 --nodes <node-ip>
```

## VM Configuration

Create VMs in Proxmox: https://docs.siderolabs.com/talos/v1.8/platform-specific-installations/virtualized-platforms/proxmox

Note: as they say in the guide, the patches should use `/dev/vda`, not `sda`, since that's what Proxmox uses here.

### Ceph OSD Disks

Each VM needs a second virtual disk for Ceph OSD storage. Add via Proxmox GUI → VM → Hardware → Add → Hard Disk:

| Setting | Value | Why |
|---------|-------|-----|
| **Controller** | VirtIO SCSI single | Per-disk IO threads, discard support, stable device ID |
| **Cache** | none | Ceph (BlueStore) manages its own caching |
| **Discard** | enabled | Reclaims freed space on thin-provisioned host storage |
| **IO Thread** | enabled | Dedicated I/O thread per disk, reduces latency |
| **Size** | ~30 GB | 3 nodes × 30 GB ≈ 45 GB usable (replication size 2) |

Disks must be **raw, unformatted, unpartitioned** — Rook auto-discovers empty disks. With VirtIO SCSI, the OSD disk appears as `/dev/sdb` (OS disk is `/dev/sda`).

## Bootstrap

```bash
talosctl gen secrets -o secrets.yaml
```

```bash
talosctl gen config talos-proxmox-cluster https://<CP_IP>:6443 \
  --with-secrets secrets.yaml --install-image <installer-link>
```

Create patches with network and disk (check disk name based on Proxmox storage: VirtIO Block = `/dev/vda`, SCSI = `/dev/sda`):
```bash
talosctl machineconfig patch controlplane.yaml --patch @controlplane-patch.yaml -o controlplane-01.yaml
```

Apply configs with `--insecure`, wait ~3-5min until rebooted, then:
```bash
talosctl config endpoint <CP_IP>
talosctl config node <CP_IP>
talosctl bootstrap
talosctl kubeconfig .
kubectl get nodes  # Should show NotReady (no CNI yet)

# Install Cilium CNI
# - ipam.mode=kubernetes: Use podCIDRs from Talos config (10.244.0.0/16)
# - k8sServiceHost=localhost:7445: KubePrism - Talos local API proxy on every node
cilium install \
  --set ipam.mode=kubernetes \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=localhost \
  --set k8sServicePort=7445 \
  --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
  --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
  --set cgroup.autoMount.enabled=false \
  --set cgroup.hostRoot=/sys/fs/cgroup

cilium status --wait
kubectl get nodes  # Should show Ready
```

## Security Notes

- `secrets.yaml` — **CRITICAL** — Contains all cluster CAs and keys
- `talosconfig` — Admin access to Talos nodes
- `kubeconfig` — Admin access to Kubernetes
