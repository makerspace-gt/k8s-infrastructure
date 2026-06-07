# Cluster Setup Guide

Bare-metal bring-up for the 2-node home cluster: **1 control plane (tower, `192.168.0.68`) + 1 worker (laptop, TBD)**. Bring nodes up **one at a time**, and **always `--dry-run` before a real apply**.

## Talos Image

**Version**: Talos v1.13.3 · platform `metal`

[Image Factory configuration](https://factory.talos.dev/?arch=amd64&platform=metal&target=metal&version=1.13.3) — schematic built in the separate PXE/image repo (`~/Projects/heim-pxe-server`).

Extensions (Longhorn needs the first two; the rest are quality-of-life):
```yaml
customization:
  systemExtensions:
    officialExtensions:
      - siderolabs/iscsi-tools      # Longhorn: iscsid / iscsiadm (volume attach)
      - siderolabs/util-linux-tools # Longhorn: fstrim (volume trim)
      - siderolabs/nfs-utils        # Longhorn RWX volumes (NFS share-manager)
      - siderolabs/intel-ucode      # CPU microcode (tower is Intel Xeon)
      - siderolabs/amd-ucode        # harmless on Intel; covers future AMD nodes
```

**Schematic ID**: `cc6abef19f4a24ca6c2fdf9e51fbc66a5c43350670f0660c77a6909d0c0c6479`

Installer image (used in `machine.install.image` and `talosctl upgrade`):
```
factory.talos.dev/metal-installer/cc6abef19f4a24ca6c2fdf9e51fbc66a5c43350670f0660c77a6909d0c0c6479:v1.13.3
```

## Disks

Identify disks per node **while it sits in maintenance mode** and pin by **WWID** (device names like `/dev/sda` are not stable across reboots):

```bash
talosctl get disks --insecure --nodes <node-ip>
talosctl get disk <id> --insecure --nodes <node-ip> -o yaml   # full spec incl. wwid
```

**Tower (CP)** — confirmed:
- OS: 80 GB Intel SSD, `install.diskSelector.wwid: naa.5001517959454aa6`
- Longhorn data: 2 TB aacraid array. It exposes **no WWID/serial**, so it's selected by `disk.transport == "aacraid"` (unique in the box). This lives as a `UserVolumeConfig` document (second doc) inside `controlplane-patch.yaml`, mounted at `/var/mnt/longhorn`.

**Laptop (worker)** — TODO once cabled: read its OS-disk WWID and create a matching `UserVolumeConfig` carving `/var/mnt/longhorn` from its single disk (Longhorn's `defaultDataPath` is global).

### Reused disks with old data

A `UserVolumeConfig` won't provision onto a disk that already has filesystem/LVM
signatures — the volume sits in `PHASE: waiting` (`talosctl -n <ip> get volumestatus`).
If the data disk held a previous system (the tower's 2 TB array had old LVM + Ceph
OSDs), Talos auto-activates that LVM at boot, so a plain `talosctl wipe disk` fails
with "in use". Wipe it via a **user-disks-only reset**, which runs before LVM
activates and keeps the OS install intact:

```bash
talosctl reset -n <node-ip> --user-disks-to-wipe /dev/sdc \
  --wipe-mode user-disks --graceful=false --reboot
```

(`--graceful=false` because there's no etcd/cluster to leave yet.) After reboot the
disk is empty and the user volume provisions automatically.

## talosctl / kubectl access

`.envrc` (direnv) sets repo-local `TALOSCONFIG` and `KUBECONFIG` — run `direnv allow`
once; no merging into `~/.talos` or `~/.kube`. Set only the **endpoint** in the
talosconfig, never a node:

```bash
talosctl config endpoint 192.168.0.68
```

**Always pass `-n <ip>` explicitly** on every `talosctl` command. A node baked into
the config means a forgotten `-n` could reboot/reset the wrong node — or all of them.

## Bring-up

### 1. Generate everything in one shot

The patches are baked in at generation time via `--config-patch-*`, so there's no
separate patch step. `controlplane-patch.yaml` is a multi-doc file (machine patch
+ Longhorn `UserVolumeConfig`); both get folded into `controlplane.yaml`. The worker
is left untouched by the CP patch.

```bash
cd talos
talosctl gen secrets -o secrets.yaml          # CRITICAL, gitignored — back this up
talosctl gen config makerspace-gt https://192.168.0.68:6443 \
  --with-secrets secrets.yaml --force \
  --config-patch-control-plane @controlplane-patch.yaml \
  --config-patch-worker @worker-01-patch.yaml
# → ready-to-apply controlplane.yaml, worker.yaml, talosconfig
```

### 2. Dry-run, then apply (node in maintenance mode → `--insecure`)

```bash
# ALWAYS dry-run first — prints the diff, changes nothing
talosctl apply-config --insecure --nodes 192.168.0.68 --file controlplane.yaml --dry-run

# Real apply: installs to disk and reboots into the configured system (~3–5 min)
talosctl apply-config --insecure --nodes 192.168.0.68 --file controlplane.yaml
```

### 3. Bootstrap etcd, fetch kubeconfig

Endpoint is set once (see **talosctl / kubectl access** above); pass `-n` every time.

```bash
talosctl -n 192.168.0.68 bootstrap                        # ONCE, control plane only
talosctl -n 192.168.0.68 kubeconfig .kube/config --force  # repo-local kubeconfig
kubectl get nodes                                         # NotReady — no CNI yet
```

### 4. Approve the kubelet serving CSR (per node)

`rotate-server-certificates: true` makes each kubelet submit a `kubernetes.io/kubelet-serving`
CSR that is **not** auto-approved (only the client-kubelet CSR is). Until it's approved,
the apiserver can't open TLS to the kubelet — `kubectl logs/exec`, metrics-server, and
Prometheus kubelet scraping fail with `tls: internal error`. Approve it **on each new node**:

```bash
kubectl get csr     # look for a Pending kubernetes.io/kubelet-serving request
kubectl get csr --field-selector spec.signerName=kubernetes.io/kubelet-serving -o name \
  | xargs -r kubectl certificate approve
```

### 5. Install Cilium (CNI — out-of-band, not Flux)

> The AUR package installs the binary as **`cilium-cli`**, not `cilium`.

```bash
cilium-cli install -f cilium-install-config/values.yaml   # from repo root
cilium-cli status --wait
kubectl get nodes                          # Ready
talosctl -n 192.168.0.68 health
```

### 6. Add the worker

Move the ethernet to the laptop, identify its disks (step **Disks**), fill the real WWID into `worker-01-patch.yaml` and add its `UserVolumeConfig` document, regenerate (step 1), then dry-run + apply (step 2) against `192.168.0.<laptop>`. No second `bootstrap` — the node joins automatically once Cilium is running. **Approve its kubelet serving CSR (step 4).**

After both nodes are up, bootstrap Flux (see `docs/procedures.md`). Restore the old sealed-secrets controller key before infra reconciles, or the 7 SealedSecrets won't decrypt.

## Upgrading Talos

One node at a time. Stage config changes so they land in the same reboot:

```bash
talosctl apply-config --file <node>.yaml --mode=staged --nodes <node-ip>   # dry-run first
talosctl upgrade \
  --image factory.talos.dev/metal-installer/cc6abef19f4a24ca6c2fdf9e51fbc66a5c43350670f0660c77a6909d0c0c6479:v1.13.3 \
  --nodes <node-ip>
```

## Security Notes

- `talos/secrets.yaml` — **CRITICAL** — all cluster CAs/keys. Gitignored. Back it up.
- `talos/talosconfig` — admin access to Talos nodes.
- `kubeconfig` — admin access to Kubernetes.

## Gotchas / lessons learned

Hard-won during the bare-metal bring-up. Read this before touching Talos config or Flux.

### Talos

- **Hostname: use the `HostnameConfig` document, not `machine.network.hostname`.** `talosctl gen config` already emits a `HostnameConfig` (default `auto: stable`). Also setting the legacy v1alpha1 `machine.network.hostname` makes the whole apply fail validation with `static hostname is already set in v1alpha1 config`. Pin it like this (`auto: "off"` overrides the default; quoted so YAML/yamllint doesn't read `off` as a boolean):
  ```yaml
  apiVersion: v1alpha1
  kind: HostnameConfig
  auto: "off"
  hostname: towercp01
  ```
  `auto: stable` is what caused a **ghost node**: with DHCP up the router name was used, but during a DHCP outage Talos fell back to an auto name (`talos-xxxx-xxxx`), the node re-registered under a new identity, and pods stranded on the dead one.
- **`apply-config` validates the entire config atomically.** One bad field (e.g. the hostname conflict above) aborts the *whole* apply — including unrelated documents like `UserVolumeConfig` — before any diff is shown.
- **Applying a config that omits a `UserVolumeConfig` destroys that user volume.** Talos user volumes are declarative; if the doc isn't in the applied config, Talos tears the volume down (unmounts `/var/mnt/longhorn`), which faults every Longhorn volume on it. Always apply the full `controlplane.yaml` that includes the `UserVolumeConfig`.
- **Recovering a Longhorn disk after the volume was torn down:** re-apply the config (volume returns), then if `nodes.longhorn.io` shows `DiskFilesystemChanged` (fresh filesystem UUID ≠ recorded), re-adopt the disk (remove/re-add it in `spec.disks` of `kubectl -n longhorn-system edit nodes.longhorn.io <node>`) and delete the empty faulted PVCs so apps recreate them.

### Flux

- **Never put custom resources in the same Kustomization as the Helm chart that provides their CRDs.** On a fresh cluster the CRD doesn't exist at apply time, the CR fails the dry-run (`no matches for kind "X"`), and because apply is atomic it *also* blocks the HelmRelease → permanent deadlock. Split the CRs into their own Kustomization with `dependsOn` the chart's. Done here for `cert-manager-issuers`, `traefik-config`, `kube-prometheus-stack-config` (and the pre-existing `etcd-metrics`).
- **A chart that renders a `ServiceMonitor` can hard-fail if the Prometheus-operator CRD is absent** (`You have to deploy monitoring.coreos.com/v1 first`). If that chart is a dependency *of* kube-prometheus-stack, disable its inline ServiceMonitor and add a standalone one in `kube-prometheus-stack-config`.
- **`flux reconcile` "hanging" = the CLI is waiting for `Ready=True`, not the work hanging.** With `wait: true` it blocks on resource health (up to the timeout). When stuck, read the controller logs (`kubectl -n flux-system logs deploy/kustomize-controller|helm-controller | grep <name>`) — the real error lives there, not in the Kustomization status.
- **Parent vs child:** reconciling `flux-system` (or the Git source) only re-applies the *Kustomization objects*. To re-apply a component's resources, reconcile **that** Kustomization (`flux reconcile kustomization <name> --with-source`).

### Discovering resources

- **Talos:** `talosctl -n <ip> get rd` lists every queryable resource type (that's how you find `mountstatus`, `volumestatus`, `hostnamestatus`, …).
- **Kubernetes:** `kubectl api-resources` (all types incl. CRDs), `kubectl get crd | grep <x>`. For `explain` on a CRD whose name collides with a built-in (e.g. `nodes`), disambiguate with `--api-version`: `kubectl explain nodes.status.diskStatus --api-version=longhorn.io/v1beta2` (plain `explain nodes.longhorn.io` fails — `explain` treats dots after the first as a field path).
