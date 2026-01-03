# Makerspace GT Infrastructure
GitOps repository for managing the Makerspace GT Kubernetes infrastructure using FluxCD.

## Todo for Staging
- define RBAC - [setup access and permissions via Tailscale operator mapping to RBAC](https://youtu.be/3VpOYn_GfAY?si=AJBxcYTgCbwWxqwE&t=1926)
- finish monitoring and observability (dashboards, loki, alerts)
- Cilium - use Hubble and setup basic firewall rules:
  - [Basic Guide](https://datavirke.dk/posts/bare-metal-kubernetes-part-2-cilium-and-firewalls/) (also see next part!)
  - [Talos Install Cilium Docs](https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium)

## Apps to add later
- Authelia
- CryptPad
- [Stirling PDF](https://github.com/Stirling-Tools/Stirling-PDF)
- Netbox
- Postiz - official helm-chart has issues:
  - bad secret handling
  - outdated - 1 year old, using bitnami images still

##
Staging-cluster Talos-Image from generator with:
```
# or amd-ucode
- siderolabs/intel-ucode
# both are required (!) by Longhorn
- siderolabs/iscsi-tools
- siderolabs/util-linux-tools
# Proxmox/Qemu integration
- siderolabs/qemu-guest-agent
```

## VM Configuration
Create VMs in Proxmox like so: https://docs.siderolabs.com/talos/v1.8/platform-specific-installations/virtualized-platforms/proxmox

Note: as they say in the guide, the patches should use `/dev/vda`, not `sda`, since that's what Proxmox uses here.

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
- `secrets.yaml` - **CRITICAL** - Contains all cluster CAs and keys
- `talosconfig` - Admin access to Talos nodes
- `kubeconfig` - Admin access to Kubernetes
