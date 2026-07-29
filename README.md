# Makerspace GT Infrastructure

GitOps repository for managing the Makerspace GT Kubernetes infrastructure using FluxCD on Talos Linux. Single bare-metal cluster (3 control planes that also schedule workloads + 1 worker), Longhorn storage, Cilium networking.

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

Pending work, rough priority. Detailed rationale lives in `docs/` + project notes.

**Phase 2 — access & multi-user**

- [ ] **Forward-auth SSO** (Authelia / authentik / oauth2-proxy) — before public exposure;
      tailnet identity does NOT protect the public Traefik path.
- [ ] **Public exposure + TLS cutover** — edge firewall + public DNS `makerspace-gt.de` +
      Let's Encrypt; flip ingress issuer from `cluster-ca-issuer` to the ACME issuer.
- [ ] **Distributed nodes across members** — feasibility discussion (etcd/Longhorn locality
      vs WAN). Unique makerspace constraints; needs a dedicated design session.

**Later / hardening**

- [ ] **Git PR workflow + protected `main`** — deferred while solo (CI gate ready).
- [ ] **Trivy image-scan CI job** — restore the image vulnerability scan (dropped with the
      old Kyverno setup; Kyverno Audit→Enforce itself is now done — enforcing on app
      namespaces, audit on platform/system via `failureActionOverrides`).
- [x] **Default-deny network policy** — `CiliumClusterwideNetworkPolicy`; roll out with
      Hubble first. Stage 1 (apps) DONE — all 5 apps default-deny egress (DNS + intra-ns +
      apiserver as needed). **Stage 2 (platform namespaces) DONE**, using a coarse
      "trusted-but-contained" pattern: `toEntities: [cluster]` (allow all in-cluster) + deny
      world, punching a narrow `world` hole only where needed — see `docs/procedures.md`.
      Done: sealed-secrets, kyverno, mariadb-operator, cert-manager, cnpg-system, alloy,
      loki, longhorn-system (all deny-world); flux-system (world :22/:443; required
      deleting Flux's default allow-all `allow-egress`); monitoring (world :443 —
      Alertmanager→Discord); tailscale (world :443 — control + DERP relays). longhorn-system
      also disabled the phone-home upgrade checker. **traefik still deferred** — it's the
      ingress controller, so it needs world *ingress* (LAN clients today via the LB IP,
      public later); the coarse cluster-only template doesn't fit. Revisit when we design
      ingress policy alongside public exposure + forward-auth. Leave kube-system open.
      **Stage 3 DONE** — cluster-wide `default-deny-backstop` CCNP (excludes
      kube-system/traefik/cilium-test; `enableDefaultDeny` both directions + shared
      DNS-allow). Applied directly, NOT via Cilium audit mode (that flag is global and
      would've un-enforced Stage 1/2). Rollout complete except traefik's own policy,
      folded into the public-exposure item above.
- [ ] **Control-plane API VIP** — DEFERRED to the cluster redesign (VMs etc.); endpoint
      topology changes then, so hold. Findings (2026-07 investigation): in-cluster comms are
      already HA via Talos **KubePrism** (`localhost:7445` → all CPs), and `talosconfig` already
      lists all 3 CP IPs. So the only SPOF is the `kubeconfig` server (`https://192.168.0.68:6443`,
      towercp01), and only for *external* clients (local kubectl; future Tailscale/public API).
      Plan when revisited: Talos L2 VIP (etcd leader-elected) across all CPs + add VIP to
      `cluster.apiServer.certSANs`; keep the VIP OUT of `talosconfig`. Does NOT fix etcd quorum
      loss (2-of-3 CPs down) — that's node reliability, a separate concern.
- [ ] **Traefik ServiceMonitor** — re-add a standalone ServiceMonitor in
      `monitoring/kube-prometheus-stack-config/` (chart's inline one hard-fails pre-CRD).
- [ ] **GPU enablement (towercp02, GTX 1080 Ti)** — NVIDIA Talos extensions + device plugin +
      RuntimeClass/node label.
- [ ] **Backups** — Longhorn backup-to-S3; pick a target.
- [ ] **Apps to (re)add** — Authelia, CryptPad, Postiz, Zammad rework (CNPG wiring).
