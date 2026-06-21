# Cluster Setup Guide

Bare-metal bring-up for the 3-node cluster: **3 control planes, all also scheduling workloads (no dedicated workers)** — `towercp01` (`192.168.0.68`), `towercp02` (`192.168.0.157`), `laptopcp03` (`192.168.0.21`). Bring nodes up **one at a time**, and **always `--dry-run` before a real apply**.

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

Each node's disks/NICs live in its own patch (`controlplane-patch.yaml` = towercp01,
`controlplane-towercp02-patch.yaml`, `controlplane-laptopcp03-patch.yaml`).

**towercp01** (`192.168.0.68`) — Intel Xeon, the weakest box (carries a
`workload: avoid:PreferNoSchedule` taint so regular pods avoid it):
- OS: 80 GB Intel SSD, `install.diskSelector.wwid: naa.5001517959454aa6`.
- Longhorn data: 2 TB aacraid array. It exposes **no WWID/serial**, so it's selected by
  `disk.transport == "aacraid"` (the only aacraid disk in the box), as a `UserVolumeConfig`
  mounted at `/var/mnt/longhorn`. Separate disk from the OS → no EPHEMERAL cap needed.
- NIC: onboard `eth0` (hardcoded — stable here, unlike the other two).

**towercp02** (`192.168.0.157`) — has the GTX 1080 Ti (future GPU node):
- OS: first 1 TB NVMe, `wwid: eui.0000000624042128caf25b03100005b3`.
- Longhorn data: second 1 TB NVMe, `wwid: eui.0000000624042128caf25b038a000392`. Two
  **identical** Lexar NM710 disks ⇒ `/dev/nvmeXn1` order is not stable, WWID is mandatory.
  Separate disk → no EPHEMERAL cap.
- NIC: onboard `eno1`, selected by `deviceSelector: { physical: true }`.

**laptopcp03** (`192.168.0.21`) — ex-worker, converted worker → control plane:
- OS **and** Longhorn share the single 512 GB NVMe, `wwid: eui.ace42e00053e630c2ee4ac0000000001`.
- Single disk ⇒ EPHEMERAL must be capped so a user volume fits (see **Single-disk node**
  under Gotchas). EPHEMERAL is capped at 100 GiB; the `UserVolumeConfig` (`grow: true`,
  pinned by the same WWID) carves `/var/mnt/longhorn` from the remainder.
- NIC: **USB ethernet adapter** (AX88179A on the USB-C port), not `eth0`, selected by
  `deviceSelector` — the bus-path name is unstable. This link now carries an etcd member;
  keep it on the reliable USB-C port. See **USB NIC** under Gotchas.

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
once; no merging into `~/.talos` or `~/.kube`. Set **all three control planes** as Talos
API endpoints (never the worker, never a node) so `talosctl` still reaches the cluster if
one CP — especially the weak `towercp01` — is down; it tries endpoints in turn, then
proxies to the `-n` target:

```bash
talosctl config endpoint 192.168.0.68 192.168.0.157 192.168.0.21
```

This is the **Talos API** endpoint list in the local talosconfig — distinct from the
**Kubernetes** API endpoint (`https://192.168.0.68:6443`) baked into every machine config,
which is still a single IP / SPOF (a VIP or LB for it is a future item). During first
bring-up only `towercp01` exists, so start with that one and add the other two once up.

**Always pass `-n <ip>` explicitly** on every `talosctl` command. A node baked into
the config means a forgotten `-n` could reboot/reset the wrong node — or all of them.

## Bring-up

### 1. Generate each node's config

Each node has its own multi-doc patch — machine patch + `HostnameConfig` + Longhorn
`UserVolumeConfig` (plus a capped `EPHEMERAL` `VolumeConfig` on the single-disk laptop) —
folded in at generation time via `--config-patch-control-plane`, so there's no separate
patch step:

| Node | Patch | Generated config |
|------|-------|------------------|
| towercp01 | `controlplane-patch.yaml` | `controlplane.yaml` |
| towercp02 | `controlplane-towercp02-patch.yaml` | `controlplane-towercp02.yaml` |
| laptopcp03 | `controlplane-laptopcp03-patch.yaml` | `controlplane-laptopcp03.yaml` |

Secrets (and `talosconfig`) are generated **once** and shared by all three nodes — all
three configs share the same PKI/etcd trust:

```bash
cd talos
talosctl gen secrets -o secrets.yaml          # ONCE — CRITICAL, gitignored, back this up
talosctl gen config makerspace-gt https://192.168.0.68:6443 \
  --with-secrets secrets.yaml --output-types talosconfig --output talosconfig

# One control-plane config per node, each with its own patch:
for node in controlplane controlplane-towercp02 controlplane-laptopcp03; do
  talosctl gen config makerspace-gt https://192.168.0.68:6443 \
    --with-secrets secrets.yaml --force \
    --config-patch-control-plane @${node}-patch.yaml \
    --output-types controlplane --output ${node}.yaml
done
```

The endpoint is always towercp01 (`192.168.0.68`) — see **talosctl / kubectl access**.

### 2. Dry-run, then apply (node in maintenance mode → `--insecure`)

Start with the **first** control plane (towercp01, `.68`); the other two join in step 6.
Each node takes its own config against its own IP:

| Node | Config | IP |
|------|--------|----|
| towercp01 | `controlplane.yaml` | 192.168.0.68 |
| towercp02 | `controlplane-towercp02.yaml` | 192.168.0.157 |
| laptopcp03 | `controlplane-laptopcp03.yaml` | 192.168.0.21 |

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

### 6. Join the other two control planes

With towercp01 up and Cilium running, bring up **towercp02** (`.157`) then **laptopcp03**
(`.21`), one at a time. For each: confirm its disks/WWIDs (step **Disks**) are filled into
its patch, generate its config (step 1), then dry-run + apply (step 2) against its IP.
**No second `bootstrap`** — each node joins etcd automatically once it's up. **Approve each
node's kubelet serving CSR (step 4).** laptopcp03 is the converted ex-worker (single disk →
EPHEMERAL cap; USB NIC → keep it on the USB-C port).

After all three nodes are up, bootstrap Flux (see `docs/procedures.md`). Restore the old sealed-secrets controller key before infra reconciles, or the 7 SealedSecrets won't decrypt.

## Joining an additional node (worker)

Adding compute later is simpler than the initial bring-up — **no `bootstrap`, no etcd**.
**Prefer a worker:** workers don't join etcd, so they don't touch quorum; a 4th *control
plane* would make etcd a 4-member cluster that still tolerates only one failure (an
even-membered quorum buys nothing). The worker config is generated from `secrets.yaml` +
a committed **`worker-patch.yaml`** (same pattern as the CP patches). For a second worker,
copy it to a per-node patch with its own `hostname` + disk selectors.

1. **Identify disks in maintenance mode** and pin by stable ID (see **Disks**):
   ```bash
   talosctl -n <node-ip> get disks --insecure
   talosctl -n <node-ip> get disk <id> --insecure -o yaml   # full spec
   ```
   Fill `install.diskSelector` (OS) and the `longhorn` `UserVolumeConfig` (data) in the
   patch. **`diskSelector` fields are glob-matched** — if a disk exposes no `serial` and
   its `wwid` carries embedded padding spaces (some SATA SSDs do), match the WWID's unique
   tail: `wwid: "*<unit-id>"`. Separate OS/data disks ⇒ **no EPHEMERAL cap** (unlike the
   single-disk laptop).

2. **Generate, dry-run, apply** (node in maintenance mode → `--insecure`):
   ```bash
   cd talos
   talosctl gen config makerspace-gt https://192.168.0.68:6443 \
     --with-secrets secrets.yaml --force \
     --config-patch-worker @worker-patch.yaml \
     --output-types worker --output worker.yaml
   talosctl apply-config --insecure --nodes <node-ip> --file worker.yaml --dry-run  # always first
   talosctl apply-config --insecure --nodes <node-ip> --file worker.yaml
   ```
   Installs to the OS disk and reboots into Talos. **No `bootstrap`** — the node joins on
   its own. The patch sets `cluster.network.cni.name: none` + `proxy.disabled: true` to
   match the Cilium / no-kube-proxy cluster; `gen` won't add these for a worker on its own.

3. **Approve the kubelet-serving CSR** (step 4 above) — same as any node.

4. **Cilium auto-schedules** its agent on the new node; it stays `NotReady` (agent
   `Init:0/5`) for a minute, then goes `Ready`. **Longhorn auto-discovers**
   `/var/mnt/longhorn` and registers the node + disk
   (`kubectl -n longhorn-system get nodes.longhorn.io <node>`). Optional role label:
   `kubectl label node <node> node-role.kubernetes.io/worker=`.

Verify: `kubectl get nodes -o wide` (Ready), `talosctl -n <node-ip> get extensions`
(`iscsi-tools` + `util-linux-tools` present for Longhorn), `talosctl -n 192.168.0.68 health`.

## Upgrading Talos

One node at a time. Stage config changes so they land in the same reboot:

```bash
talosctl apply-config --file <node>.yaml --mode=staged --nodes <node-ip>   # dry-run first
talosctl upgrade \
  --image factory.talos.dev/metal-installer/cc6abef19f4a24ca6c2fdf9e51fbc66a5c43350670f0660c77a6909d0c0c6479:v1.13.3 \
  --nodes <node-ip>
```

## Upgrading Longhorn

**Longhorn does not support skipping minor versions** — upgrade one minor at a time
(1.9 → 1.10 → 1.11 → …), waiting for healthy between each. A multi-minor jump makes
the chart's `longhorn-pre-upgrade` hook job fail, which leaves the Flux HelmRelease
`Stalled` (the running Longhorn keeps working on the old version; only the *upgrade*
fails). This bit us when Renovate bumped the chart 1.9.0 → 1.12.0 in one PR (#134).

Renovate is now pinned to **patch-only auto-bumps for Longhorn** (minor/major need
manual approval via the dependency dashboard) so it can't leapfrog minors again —
see the `longhorn` rule in `renovate.json`.

To move one minor:
1. Bump `version:` in `infrastructure/storage/longhorn/helmrelease.yaml` by **one**
   minor (latest patch of that minor), commit, push.
2. `flux reconcile kustomization longhorn --with-source`.
3. Verify before the next minor: `kubectl -n longhorn-system get helmrelease longhorn`
   → `Ready=True`, and `kubectl -n longhorn-system get volumes.longhorn.io` → all
   `healthy`.

Recovering a `Stalled` HR from a bad jump: set `version:` back to the **deployed**
minor (`kubectl -n longhorn-system get ds longhorn-manager -o jsonpath='{..image}'`)
and reconcile — the spec change resets the stalled retry and helm-controller
succeeds. Note the `longhorn` Kustomization `dependsOn snapshot-controller`, so
snapshot-controller must reach the current Git revision first; reconcile it
(`flux reconcile kustomization snapshot-controller --with-source`) if it lags.

**Engines don't auto-roll by default.** The manager upgrades live, but each volume's
*engine* stays on the old image until upgraded. We set
`concurrentAutomaticEngineUpgradePerNodeLimit: 3` in the helmrelease values so engines
self-roll to the default after every manager bump. Confirm convergence with:

```
kubectl -n longhorn-system get volumes.longhorn.io \
  -o jsonpath='{range .items[*]}{.status.currentImage}{"\n"}{end}' | sort | uniq -c
```

until every volume's `currentImage` is the new version. Don't start the next minor
until all engines have rolled (Longhorn supports only one minor of manager/engine skew).

> The UI accepts a *lower* engine version without warning, but the controller silently
> no-ops the downgrade (stuck "upgrading" spinner). Always pick a version ≥ `currentImage`;
> to cancel a bad request, patch `spec.image` back to the running image.

### One-time 1.9 → 1.10 CRD failure (Flux server-side apply)

The 1.9 → 1.10 hop failed the Helm upgrade at the CRD apply with
`spec.conversion.strategy: Required value` / `webhookClientConfig: Forbidden`. Cause:
Flux 2.8's helm-controller uses Helm-v4 server-side apply and had co-grabbed ownership
of the CRD `spec.conversion` block that longhorn-manager injects at runtime (the
caBundle), so its apply dropped `strategy: Webhook` → invalid CRD. One-time fix:

```
# 1. apply the target CRDs out-of-band, forcing field-ownership conflicts
helm template longhorn longhorn/longhorn --version <X.Y.Z> -n longhorn-system \
  | yq 'select(.kind=="CustomResourceDefinition")' > /tmp/lh-crds.yaml
kubectl apply --server-side --force-conflicts -f /tmp/lh-crds.yaml
# 2. reset stale ownership on the CRDs helm-controller wrongly co-owns
for c in backingimages backuptargets engineimages nodes volumes; do
  kubectl patch crd $c.longhorn.io --type=merge -p '{"metadata":{"managedFields":[{}]}}'
done
# 3. retry the release
flux reconcile helmrelease longhorn --force -n longhorn-system
```

A one-time SSA-migration artifact — 1.10→1.11→1.12 applied cleanly afterward. Also note:
1.9 → 1.10 first requires migrating CRD storage versions `v1beta1` → `v1beta2` (per the
Longhorn 1.10 important-notes) — run it if any CRD still lists `v1beta1` in
`status.storedVersions`.

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
- **USB ethernet adapter, not `eth0`.** laptopcp03's NIC is a USB dongle; Talos names it from the USB bus path (e.g. `enp58s0u1u1u3`), and that name **changes** when you swap the adapter or move ports. Don't hardcode an interface name — select the single physical NIC:
  ```yaml
  machine:
    network:
      interfaces:
        - deviceSelector:
            physical: true
          dhcp: true
  ```
  Talos ships every mainstream USB-NIC driver **in-kernel** (`r8152`, `ax88179_178a`, `cdc_ether`/`cdc_ncm`, …) — no extension needed; only CH9200 and RTL8150 are not compiled (verify against the running node: `talosctl -n <ip> read /proc/config.gz | gunzip | grep -iE 'RTL8152|AX88179|CDCETHER'`). If a USB NIC never enumerates (`new SuperSpeed USB device …` with **no** following `New USB device found, idVendor=…`), it's a USB3 link/power problem, not a driver one — try a USB2 port, a different cable, or the USB-C port. AX88179A (driverless CDC-NCM) is the safe adapter; avoid anything with a bundled "driver CD" (USB mode-switch, which Talos lacks).
- **Single-disk node (OS + Longhorn on one disk): cap EPHEMERAL or it eats the whole disk.** `EPHEMERAL` (`/var`) grows to fill all free space by default, leaving nothing for a user volume. **Volume layout is applied only at first provision** — get it right on install or wipe + reinstall. Cap EPHEMERAL and let the user volume grow into the remainder (system volumes provision first; `grow: true` volumes provision last):
  ```yaml
  ---
  apiVersion: v1alpha1
  kind: VolumeConfig
  name: EPHEMERAL
  provisioning:
    maxSize: 100GiB
  ---
  apiVersion: v1alpha1
  kind: UserVolumeConfig
  name: longhorn
  provisioning:
    diskSelector:
      match: disk.wwid == "<nvme-wwid>"
    grow: true        # takes whatever EPHEMERAL's cap leaves
  ```
- **`talosctl reset --wipe-mode all` (the default) scrubs the whole system disk, including the bootloader** — the node then can't boot and needs install media/PXE to get back to maintenance mode (learned converting the laptop worker→CP). To reprovision a node *in place* while keeping it bootable straight into maintenance, wipe only the config + data partitions: `talosctl reset --system-labels-to-wipe STATE,EPHEMERAL --graceful=false --reboot`. Reserve `--wipe-mode all` for when you actually want the disk fully scrubbed and will boot from media afterward.

### Flux

- **Never put custom resources in the same Kustomization as the Helm chart that provides their CRDs.** On a fresh cluster the CRD doesn't exist at apply time, the CR fails the dry-run (`no matches for kind "X"`), and because apply is atomic it *also* blocks the HelmRelease → permanent deadlock. Split the CRs into their own Kustomization with `dependsOn` the chart's. Done here for `cert-manager-issuers`, `traefik-config`, `kube-prometheus-stack-config`.
- **A chart that renders a `ServiceMonitor` can hard-fail if the Prometheus-operator CRD is absent** (`You have to deploy monitoring.coreos.com/v1 first`). If that chart is a dependency *of* kube-prometheus-stack, disable its inline ServiceMonitor and add a standalone one in `kube-prometheus-stack-config`.
- **`flux reconcile` "hanging" = the CLI is waiting for `Ready=True`, not the work hanging.** With `wait: true` it blocks on resource health (up to the timeout). When stuck, read the controller logs (`kubectl -n flux-system logs deploy/kustomize-controller|helm-controller | grep <name>`) — the real error lives there, not in the Kustomization status.
- **Parent vs child:** reconciling `flux-system` (or the Git source) only re-applies the *Kustomization objects*. To re-apply a component's resources, reconcile **that** Kustomization (`flux reconcile kustomization <name> --with-source`).

### Discovering resources

- **Talos:** `talosctl -n <ip> get rd` lists every queryable resource type (that's how you find `mountstatus`, `volumestatus`, `hostnamestatus`, …).
- **Kubernetes:** `kubectl api-resources` (all types incl. CRDs), `kubectl get crd | grep <x>`. For `explain` on a CRD whose name collides with a built-in (e.g. `nodes`), disambiguate with `--api-version`: `kubectl explain nodes.status.diskStatus --api-version=longhorn.io/v1beta2` (plain `explain nodes.longhorn.io` fails — `explain` treats dots after the first as a field path).
