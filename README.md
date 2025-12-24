# Makerspace GT Infrastructure

GitOps repository for managing the Makerspace GT Kubernetes infrastructure using FluxCD.

## Todo for Staging
- add secrets with sealed-secrets as required per app
- Zammad needs email SMTP setup - the other apps too, configure
- configure Longhorn w/ backups and define PVC sizes
- setup traefik & cert-manager with domain
- add Authelia for SSO
- define RBAC
- finish monitoring and observability (dashboards, loki, alerts, add UptimeKuma on raspberry)

## Apps to add later
- CryptPad
- Netbox
- Postiz - official helm-chart has issues:
  - bad secret handling
  - outdated - 1 year old, using bitnami images still

##
[Staging-cluster Talos-Image from generator](https://factory.talos.dev/?arch=amd64&board=undefined&bootloader=auto&cmdline-set=true&extensions=-&extensions=siderolabs%2Fintel-ucode&extensions=siderolabs%2Fiscsi-tools&extensions=siderolabs%2Fqemu-guest-agent&platform=nocloud&secureboot=undefined&target=cloud&version=1.12.0):
`bb0ba48a52352c699781aeeb4aa1983b80ccc778c2eac94590fe6b4ab3c0fd00`

With:
```
customization:
    systemExtensions:
        officialExtensions:
            - siderolabs/intel-ucode
            - siderolabs/iscsi-tools
            - siderolabs/qemu-guest-agent
```


## VM Configuration
Create VMs in Proxmox like so: https://docs.siderolabs.com/talos/v1.8/platform-specific-installations/virtualized-platforms/proxmox#qemu-guest-agent-support

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
