# Cluster rebuild — next steps

Living plan for the move from the OpenNebula/Ceph testing setup to the new bare-metal cluster. This file lives in the repo on purpose: the devcontainer (and its Claude memory) will be wiped before the rebuild, so anything not captured here is lost. Update it as we go.

## Decisions locked in

- **Hardware**: 2 local bare-metal machines to start, single cluster. Scaling to 3+ is a follow-up discussion — see *Scaling and 2-node trade-offs* below.
- **OS**: Talos, installed via PXE from a separate repo (treat as opaque here — image + schematic in `docs/setup.md`).
- **Storage**: Longhorn replaces Rook Ceph. Lighter footprint, fits bare-metal scale.
- **Networking**: Cilium installed out-of-band via `cilium install -f`. WireGuard encryption stays on.
- **TLS**: Real Let's Encrypt certs via ACME (HTTP-01 through Traefik) on `*.makerspace-gt.de`.
- **Ingress**: Internet-reachable, single edge firewall, no public IPs per machine.

## Open questions (need values before the rebuild)

- **LAN subnet** for the new cluster — currently `192.168.0.0/24` is baked into `talos/*-patch.yaml` (`kubelet.nodeIP.validSubnets`) and the Cilium LB IP pool.
- **Hostnames + static IPs** for the two machines (or commit to DHCP + reservations).
- **Per-machine specs**: CPU cores / RAM / disks. Drives the sizing table in README and whether to dedicate a data disk vs share OS disk for Longhorn.
- **Install disk**: bare-metal is most likely `/dev/sda` or `/dev/nvme0n1`; verify before `talosctl apply-config`.

## Scaling and 2-node trade-offs

Discuss after the cluster is up. Two machines means no real HA on either the control plane or storage; both come into play when a 3rd machine arrives.

- **Control plane**: 2 etcd members is a worst-of-both — no quorum survival if either node fails, vs. 1 CP where a single node failure just means the cluster is down (no split-brain risk). Recommend 1 CP + 1 worker for now; promote the worker to CP-also when the 3rd machine joins (target: 3 CPs for proper HA).
- **Longhorn**: replica count must be ≤ node count. Run with 2 replicas now (one per node); bump to 3 after the 3rd machine joins. Until then, losing a node means volumes lose redundancy until the node is back.
- **Compute**: any node loss means surviving node must hold everything — sizing should account for this if uptime through reboots matters.

## Work remaining (in rough order)

### 1. Finish simplification (this branch)

WIP diff from before the break — these are good to commit:

- L2 announcement + LB pool files removed from `infrastructure/networking/cilium/` (will be re-added once new subnet known).
- `cilium-install-config/values.yaml`: L2 + externalIPs blocks dropped.
- `cluster/infrastructure.yaml`: `cilium` now depends on `traefik` + `cert-manager`.
- `cluster/monitoring.yaml`: `loki` now depends on `rook-ceph` (will switch to `longhorn` later).
- App sizing applied (Vikunja, Wiki.js, NetBox, Zammad CNPG instances/storage; Stirling-PDF, NetBox, Homepage-WordPress container resources).
- Rook Ceph values set to prod: `mon: 3`, `mgr: 2`, `replicated.size: 3`, no CP toleration, OSD requests bumped.
- Prometheus 14d / 50Gi, Loki 14d / 50Gi.
- `docs/procedures.md`: removed the self-signed CA trust section.
- `README.md`: restructured pending list, dropped stale resource targets.

### 2. Drop Kyverno + Trivy from CI

- Remove the `kyverno-validation` and `security-scan` jobs from `.github/workflows/validate.yaml`.
- Keep `policies/` on disk for later re-enablement (TODO below).

### 3. Remove devcontainer, add CLI install guide

- Delete `.devcontainer/`.
- New `docs/setup-guide.md`: CLI install commands for Arch + Fedora (kubectl, helm, flux, k9s, kustomize, kubeseal, talosctl, kubectx/kubens, cilium-cli, direnv, claude-code, yamllint, kubeconform, pre-commit, detect-secrets). Skip minikube, tetra, kyverno, trivy.

### 4. Storage: Ceph → Longhorn (separate branch, after the above lands)

- Add `infrastructure/storage/longhorn/` HelmRelease; set its StorageClass as cluster default. Set `defaultSettings.defaultReplicaCount: 2` for the 2-node start (raise to 3 when the 3rd machine joins — see scaling notes).
- Delete `infrastructure/storage/rook-ceph/` (operator + cluster charts).
- Update `cluster/infrastructure.yaml`: drop the `rook-ceph` Kustomization, add `longhorn`.
- Update `cluster/monitoring.yaml`: switch the `loki` `dependsOn` from `rook-ceph` → `longhorn`.
- Drop `extraMounts: /var/lib/rook` from `talos/*-patch.yaml`.
- Apps don't pin `storageClassName` anywhere (verified) — default-class swap is enough.
- Replace `cephBlockPoolsVolumeSnapshotClass` usage with Longhorn's snapshot class.
- Greenfield cluster — no data migration.

### 5. Talos machineconfigs for the new cluster (separate branch)

- Regenerate `talos/secrets.yaml` (fresh install).
- Update `talos/controlplane-patch.yaml` + `talos/worker-*-patch.yaml`:
  - Drop `extraMounts: /var/lib/rook` (after Longhorn swap).
  - Update `kubelet.nodeIP.validSubnets` to the new LAN CIDR.
  - Verify/update `install.disk`.
  - 2-node layout (per scaling notes): 1 CP + 1 worker recommended. Untaint the CP so workloads can run on it (`cluster.allowSchedulingOnControlPlanes: true` or `kubelet.registerWithTaints: []`).
  - Decide DHCP vs static; if static, add `interfaces.addresses` + `routes`.
- Update `monitoring/etcd-metrics/etcd-endpoints.yaml` to list the CP IP(s) for whatever topology lands.

### 6. Networking re-add (separate branch)

- Re-add `CiliumLoadBalancerIPPool` + `CiliumL2AnnouncementPolicy` with the new LAN IP range (or pick BGP if the network admin can peer).
- Re-enable `l2announcements.enabled` + `externalIPs.enabled` in `cilium-install-config/values.yaml`.

### 7. TLS cutover (separate branch)

- Add ACME `ClusterIssuer` (Let's Encrypt prod) for `*.makerspace-gt.de`, HTTP-01 via Traefik.
- Flip every Ingress's `cert-manager.io/cluster-issuer` annotation to the new issuer.
- Delete `infrastructure/certificates/cert-manager/self-signed-cluster-setup.yaml` once ingresses are reissued.

### 8. Later (won't block the rebuild)

- **Re-add Kyverno + Trivy CI**: `policies/` still on disk; restore the two jobs in `.github/workflows/validate.yaml`.
- **Default-deny CiliumClusterwideNetworkPolicy** in its own branch. Roll out with Hubble in observe/audit mode first.
- **Metrics-server** into Flux (`infrastructure/controllers/metrics-server/`), off the manual `kubectl apply` flow in `docs/procedures.md`.
- **RBAC** definitions.
- **Backups**: Longhorn has built-in backup-to-S3 — pick a target.
- **Apps to (re)add**: Authelia, CryptPad, Postiz (chart issues — bad secret handling, outdated), Zammad rework.
- **Zammad rework**: chart bundles its own Postgres; to use CNPG, set `postgresql.enabled: false` and configure `zammadConfig.postgresql.*` (host, user, db) + wire CNPG secret. Do NOT override raw `DATABASE_URL`. Fresh DB may need `zammad-init` Job to `rake db:migrate db:seed`.

## Gotchas worth re-reading after the break

- Cilium is installed via `cilium install -f ./cilium-install-config/values.yaml`, **not** by Flux. Don't expect it in `flux get hr`.
- Talos `HostnameConfig`: must set explicit `hostname:`, never `auto: stable`.
- Alertmanager Discord: must use `AlertmanagerConfig` CRD with `apiURL` SecretKeySelector — Prometheus Operator rejects inline `webhook_url_file`.
- Talos etcd metrics on port 2381 bind `0.0.0.0` and have no auth — acceptable on private LAN, document if exposure model changes.
- kube-prometheus-stack: cross-namespace resources (e.g. etcd Endpoints in `kube-system`) need a separate Flux Kustomization (see `monitoring/etcd-metrics/`).
- Grafana dashboards: provisioned via ConfigMaps with `grafana_dashboard: "1"` label — sidecar discovers from all namespaces.
- Talos upgrade flow: `talosctl apply-config --mode=staged` + `talosctl upgrade --image` = one reboot.
