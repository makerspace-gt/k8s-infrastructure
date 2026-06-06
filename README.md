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

- **kubelet-csr-approver** — kubelets use `rotate-server-certificates`, so each node's `kubernetes.io/kubelet-serving` CSR must be approved by hand (it recurs on reboots/cert rotation; see `docs/setup.md` step 4). Deploy [kubelet-csr-approver](https://github.com/postfinance/kubelet-csr-approver) to auto-approve them with node-name/IP checks.
