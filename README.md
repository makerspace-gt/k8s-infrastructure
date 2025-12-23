# Makerspace GT Infrastructure

GitOps repository for managing the Makerspace GT Kubernetes infrastructure using FluxCD.

## Todo for Staging
- add secrets with sealed-secrets as required per app
- Zammad needs email SMTP setup - the other apps too, configure
- configure Longhorn w/ backups and define PVC sizes
- setup traefik & cert-manager with domain
- add Authelia for SSO
- define RBAC
- finish monitoring and observability (dashboards, loki, alerts, add UptimeKuma on raspberry)

## Apps to add later
- CryptPad
- Netbox
- Postiz - official helm-chart has issues:
  - bad secret handling
  - outdated - 1 year old, using bitnami images still
