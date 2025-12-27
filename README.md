# Makerspace GT Infrastructure
GitOps repository for managing the Makerspace GT Kubernetes infrastructure using FluxCD.

## Todo for Staging
- add secrets with sealed-secrets as required per app
- Zammad needs email SMTP setup - the other apps too, configure
- configure Longhorn w/ backups and define PVC sizes
- setup traefik & cert-manager with domain
- add Authelia for SSO
- define RBAC - [setup access and permissions via Tailscale operator mapping to RBAC](https://youtu.be/3VpOYn_GfAY?si=AJBxcYTgCbwWxqwE&t=1926)
- finish monitoring and observability (dashboards, loki, alerts, add UptimeKuma on raspberry)

## Apps to add later
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
talosctl gen config talos-proxmox-cluster https://192.168.1.145:6443 \
  --with-secrets secrets.yaml \
  --install-image <installer-link>
```

Create the patches with network and the `/dev/vda`-disk-part, then apply them like `talosctl machineconfig patch controlplane.yaml \
  --patch @controlplane-patch.yaml -o controlplane-01.yaml`

Next, apply them with `--insecure`, wait ~3-5min until rebooted, then:

```
talosctl config endpoint 192.168.1.145
talosctl config node 192.168.1.145
talosctl bootstrap

talosctl kubeconfig .
kubectl get nodes  # Should show NotReady (no CNI yet)

cilium install \
  --version 1.16.5 \
  --set kubeProxyReplacement=true \
  --set k8sServiceHost=192.168.1.145 \
  --set k8sServicePort=6443 \
  --set securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
  --set securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
  --set cgroup.autoMount.enabled=false \
  --set cgroup.hostRoot=/sys/fs/cgroup
```

cilium status --watch
kubectl get nodes
```

## Security Notes
- `secrets.yaml` - **CRITICAL** - Contains all cluster CAs and keys
- `talosconfig` - Admin access to Talos nodes
- `kubeconfig` - Admin access to Kubernetes
