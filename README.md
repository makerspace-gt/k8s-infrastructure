# Makerspace GT Infrastructure

GitOps repository for managing the Makerspace GT Kubernetes infrastructure using FluxCD.

See [docs/setup.md](docs/setup.md) for cluster setup instructions (Talos image, Proxmox VM config, bootstrap).

## Todo for Staging

- Define RBAC - [setup access and permissions via Tailscale operator mapping to RBAC](https://youtu.be/3VpOYn_GfAY?si=AJBxcYTgCbwWxqwE&t=1926)
- Finish monitoring and observability (dashboards, Loki, alerts)
- Cilium - use Hubble and setup basic firewall rules:
  - [Basic Guide](https://datavirke.dk/posts/bare-metal-kubernetes-part-2-cilium-and-firewalls/) (also see next part!)
  - [Talos Install Cilium Docs](https://docs.siderolabs.com/kubernetes-guides/cni/deploying-cilium)
- Rook Ceph dashboard authentication
- Backup/snapshot configuration (Velero, CephObjectStore, etc.)
- Ceph performance tuning (sysctls, file limits)
- Talos image rebuild (upgrade to 1.12.6, remove unused Longhorn extensions)

## Apps to add later

- Authelia
- CryptPad
- [Stirling PDF](https://github.com/Stirling-Tools/Stirling-PDF)
- Netbox
- Postiz - official helm-chart has issues:
  - bad secret handling
  - outdated - 1 year old, using bitnami images still
