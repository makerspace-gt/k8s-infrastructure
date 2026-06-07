# Makerspace GT Infrastructure

GitOps repository for managing the Makerspace GT Kubernetes infrastructure using FluxCD on Talos Linux.

- [docs/setup.md](docs/setup.md) — cluster bootstrap (Talos image, schematic, install flow)
- [docs/setup-guide.md](docs/setup-guide.md) — local CLI tool install for Arch and Fedora
- [docs/procedures.md](docs/procedures.md) — common operational procedures (sealed secrets, ingress, etc.)
- [NEXT-STEPS.md](NEXT-STEPS.md) — working punch list for the bare-metal rebuild

## Accessing the apps

Services are reachable via public DNS at `*.makerspace-gt.de`, served by Traefik with TLS issued by Let's Encrypt.

## Later / roadmap

Operational follow-ups, not blocking day-to-day use:

- **Cilium LoadBalancer IP pool + L2 announcement** — removed during simplification; without it Traefik's `LoadBalancer` service has no external IP. Re-add `CiliumLoadBalancerIPPool` (`192.168.0.201–210`) + `CiliumL2AnnouncementPolicy`, and re-enable `l2announcements`/`externalIPs` in `cilium-install-config/values.yaml` (Traefik target `.202`). Needed before apps are reachable on the LAN.
- **Traefik ServiceMonitor** — the chart's inline ServiceMonitor is disabled (it hard-fails without the Prometheus operator CRD, which kube-prometheus-stack provides *after* traefik). Re-add a standalone `ServiceMonitor` in `monitoring/kube-prometheus-stack-config/` (CRD present there) with the label kube-prometheus-stack's `serviceMonitorSelector` expects.
- **kubelet-csr-approver** — kubelets use `rotate-server-certificates`, so each node's `kubernetes.io/kubelet-serving` CSR must be approved by hand (it recurs on reboots/cert rotation; see `docs/setup.md` step 4). Deploy [kubelet-csr-approver](https://github.com/postfinance/kubelet-csr-approver) to auto-approve them with node-name/IP checks.
- **Longhorn upgrade 1.9.0 → 1.12.0** — pinned at 1.9.0 because Renovate jumped it 3 minors at once (illegal; the pre-upgrade hook fails). Must be done **manually, one minor at a time** (1.9 → 1.10 → 1.11 → 1.12), waiting for healthy between each — see `docs/setup.md` "Upgrading Longhorn". Renovate is pinned to patch-only for Longhorn; ignore any minor/major Longhorn entry it shows on the dependency dashboard (it would re-propose the skip).
