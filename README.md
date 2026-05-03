# Makerspace GT Infrastructure

GitOps repository for managing the Makerspace GT Kubernetes infrastructure using FluxCD.

See [docs/setup.md](docs/setup.md) for cluster setup instructions (Talos image, VM config, bootstrap).

## Todo

- Define RBAC
- Backup/snapshot configuration (Velero, CephObjectStore, etc.)

## Production Cluster Sizing

Target: ~600 GB usable data, Ceph `replicated.size: 3`, conservative estimates with headroom.

### Node Layout

| Role | Count | vCPU | RAM | OS disk | Data disk | OSDs |
|---|---|---|---|---|---|---|
| Control plane | 3 | 4 | 8 GB | 50 GB | — | — |
| Worker | 4 | 8 | 24–32 GB | 60 GB | 1 TB | 1 each |

- One worker per hypervisor (OpenNebula anti-affinity) for failure-domain isolation
- 32 GB preferred over 24 GB for Ceph page cache performance
- Dedicated data disk per worker, separate from OS disk

### Storage

- 600 GB × 3 replicas ÷ 0.70 fill target = ~2.6 TB raw; 4 × 1 TB disks = ~930 GB usable (~50% growth headroom)
- 4 OSDs total (1 per worker), `failureDomain: host`
- Change `replicated.size` from 2 → 3 before production

### Application Resource Targets (requests → limits)

| Component | CPU | Memory | Storage (PVC) | Notes |
|---|---|---|---|---|
| **Zammad** (per component: rails, websocket, scheduler) | 500m → 2 | 1 Gi → 2 Gi | — | Set explicit limits on all subcharts |
| Zammad Elasticsearch | 250m → 1 | 512 Mi → 2 Gi | — | Already partially configured |
| Zammad Redis / Memcached | 100m → 500m | 128–256 Mi → 512 Mi | — | |
| Zammad CNPG | — | — | 50 Gi, instances: 2 | HA + room for tickets/attachments |
| **Netbox** (main) | 100m → 1 | 512 Mi → 1 Gi | — | Current values OK |
| Netbox worker/housekeeping | 50m → 500m | 256 Mi → 1 Gi | — | Bump for bulk imports |
| Netbox CNPG | — | — | 20 Gi, instances: 2 | |
| **WordPress** | 100m → 1 | 256 Mi → 1 Gi | 10 Gi | Currently missing resources block |
| WordPress MySQL | 100m → 1 | 256 Mi → 1 Gi | 2 Gi | Consider migrating to CNPG |
| **Stirling-PDF** | 100m → 1 | 256 Mi → 3 Gi | — | High limit for batch OCR |
| **Vaultwarden** | 50m → 500m | 128 Mi → 512 Mi | 1 Gi | Current values OK |
| **Vikunja** + CNPG | 100m → 500m | 256 Mi → 512 Mi | 1 Gi app + 10 Gi DB, instances: 2 | |
| **Wiki.js** + CNPG | 100m → 500m | 256 Mi → 768 Mi | 10 Gi DB, instances: 2 | |
| **Prometheus** | 1 → 2 | 2 Gi → 4 Gi | 50 Gi | 30d retention (up from 7d/5Gi) |
| **Grafana** | 100m → 500m | 128 Mi → 512 Mi | — | Current values OK |
| **Loki** | 500m → 1 | 512 Mi → 2 Gi | 50 Gi | Up from 10 Gi |
| **Rook-Ceph OSD** (per node) | 500m (no limit) | 2 Gi req (no limit) | — | Real usage ~6–8 Gi; no CPU limit intentional |

### Per-Node Overhead (each worker)

~1.3 cores / ~7–9 Gi actual (OSD + DaemonSets + kubelet). At 8 vCPU / 24 GB per worker, expect ~60% memory utilization with workloads spread evenly.

## Apps to add later

- Authelia
- CryptPad
- Postiz - official helm-chart has issues:
  - bad secret handling
  - outdated - 1 year old, using bitnami images still
- Zammad - needs rework:
  - Chart bundles its own PostgreSQL; to use CNPG instead, set `postgresql.enabled: false` and configure `zammadConfig.postgresql.*` values (host, user, db) + wire CNPG secret
  - Do NOT use raw `DATABASE_URL` env override — chart entrypoint builds its own from `POSTGRESQL_*` vars
  - Fresh DB might require the `zammad-init` Job to run `rake db:migrate db:seed` against the correct DB

# Accessing the apps locally
Right now, apps are accessible through the traffic service, which has a LoadBalancer IP from Cilium; Cilium answers ARP requests for this IP via the L2-announcement feature.
Edit your `/etc/hosts` to resolve the hosts:
```
<...>
<lb-ip> makerspace.local ceph.makerspace.local vault.makerspace.local vikunja.makerspace.local grafana.makerspace.local hubble.makerspace.local traefik.makerspace.local netbox.makerspace.local pdf.makerspace.local wiki.makerspace.local
```
