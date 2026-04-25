# Makerspace GT Infrastructure

GitOps repository for managing the Makerspace GT Kubernetes infrastructure using FluxCD.

See [docs/setup.md](docs/setup.md) for cluster setup instructions (Talos image, VM config, bootstrap).

## Todo

- Define RBAC
- Backup/snapshot configuration (Velero, CephObjectStore, etc.)

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
