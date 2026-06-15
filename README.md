# Makerspace GT Infrastructure

GitOps repository for managing the Makerspace GT Kubernetes infrastructure using FluxCD on Talos Linux. Single bare-metal cluster (3 control planes, all also scheduling workloads), Longhorn storage, Cilium networking.

## Docs

- [docs/cluster-bootstrap.md](docs/cluster-bootstrap.md) — Talos cluster bootstrap (image, schematic, install flow)
- [docs/local-tools.md](docs/local-tools.md) — local CLI tool install for Arch and Fedora
- [docs/procedures.md](docs/procedures.md) — operational procedures (sealed secrets, ingress, etcd metrics)
- [talos/schematics.md](talos/schematics.md) — Talos Image Factory schematic registry (extensions + kernel args)

## Accessing the services

**Currently an internal test cluster, single physical location.** There is one on-site
operator; all other members and the makerspace office are on different networks, so
on-LAN access is not the access path for them.

- Services are exposed via Traefik on `*.makerspace.local`, with TLS from the internal
  CA (`cluster-ca-issuer`). On-LAN only today.
- **Tailscale access is the near-term plan** so members reach services remotely over the
  tailnet (MagicDNS `*.ts.net`), without public exposure.
- **Public exposure is future**: edge firewall + public DNS (`makerspace-gt.de`) + Let's
  Encrypt certs. Not set up yet.

## Roadmap / Todos

Rough priority order. Phase 1 finishes the basic setup; Phase 2 is the access/RBAC build-out.

**Phase 1 — finish basic setup**

- [ ] **Longhorn 1.9 → 1.12**, one minor at a time (1.9→1.10→1.11→1.12), waiting for
      healthy between each. Renovate is pinned patch-only for Longhorn; ignore minor/major
      entries it shows. See `docs/cluster-bootstrap.md` "Upgrading Longhorn".
- [ ] **Refresh `docs/cluster-bootstrap.md`** to the real 3-CP topology (currently stale
      2-node text + old IPs).

**Phase 2 — access & multi-user**

- [ ] **Tailscale access** — Tailscale K8s operator + MagicDNS so members reach services
      over the tailnet. Decide L2/LB-IPPool re-add vs Tailscale-only. The one hardcoded LAN
      IP (`infrastructure/networking/traefik/helmrelease.yaml` → `.202`) is resolved here.
- [ ] **RBAC** — roles for admins / normal members so members can deploy their own apps.
- [ ] **Public exposure + TLS cutover** — edge firewall + public DNS `makerspace-gt.de` +
      Let's Encrypt; flip ingress issuer from `cluster-ca-issuer` to the ACME issuer.
- [ ] **Distributed nodes across members** — feasibility discussion (etcd/Longhorn locality
      vs WAN). Unique makerspace constraints; needs a dedicated design session.

**Later / hardening**

- [ ] **Re-enable Kyverno** — policies still in `policies/` (not wired to Flux); install
      Kyverno + restore the Kyverno/Trivy CI jobs.
- [ ] **Default-deny network policy** — `CiliumClusterwideNetworkPolicy`; roll out with
      Hubble in audit/observe mode first (currently per-namespace opt-in, several namespaces open).
- [ ] **Control-plane API VIP** — kubeconfig/talosconfig point at a single CP (`192.168.0.68`);
      add a Talos shared VIP across all CPs + cert SANs so API access survives that node dying.
- [ ] **kubelet-csr-approver** — auto-approve `kubernetes.io/kubelet-serving` CSRs (recurs on
      reboot/rotation; see `docs/cluster-bootstrap.md` step 4).
- [ ] **Traefik ServiceMonitor** — re-add a standalone ServiceMonitor in
      `monitoring/kube-prometheus-stack-config/` (chart's inline one hard-fails pre-CRD).
- [ ] **GPU enablement (towercp02, GTX 1080 Ti)** — NVIDIA Talos extensions + device plugin +
      RuntimeClass/node label.
- [ ] **Backups** — Longhorn backup-to-S3; pick a target.
- [ ] **Apps to (re)add** — Authelia, CryptPad, Postiz, Zammad rework (CNPG wiring).
