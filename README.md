# Makerspace GT Infrastructure

GitOps repository for managing the Makerspace GT Kubernetes infrastructure using FluxCD on Talos Linux. Longhorn storage, Cilium networking.

## Docs

- [docs/cluster-bootstrap.md](docs/cluster-bootstrap.md) — Talos cluster bootstrap (image, schematic, install flow)
- [docs/local-tools.md](docs/local-tools.md) — local CLI tool install for Arch and Fedora
- [docs/procedures.md](docs/procedures.md) — operational procedures (sealed secrets, ingress, etcd metrics)

## Accessing the services

- **Tailscale access is the near-term plan** so members reach services remotely over the
  tailnet (MagicDNS `*.ts.net`), without public exposure.
- **Public exposure is future**: edge firewall + public DNS (`makerspace-gt.de`) + Let's
  Encrypt certs. Not set up yet.

## Roadmap / Todos

Pending work, rough priority.

- [ ] **Forward-auth SSO** (Authelia / authentik / oauth2-proxy) — before public exposure;
      tailnet identity does NOT protect the public Traefik path.

**Later / hardening**

- [ ] **Git PR workflow + protected `main`**
- [ ] **Trivy image-scan CI job** — image vulnerability scan
- [ ] **Apps to (re)add** — Authelia, CryptPad, Postiz, Zammad rework (CNPG wiring).
