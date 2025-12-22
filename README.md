# Makerspace GT Infrastructure

GitOps repository for managing the Makerspace GT Kubernetes infrastructure using FluxCD.

## Current Setup

- **Local Development**: k3d cluster on local machine
- **GitOps**: FluxCD for continuous deployment
- **Apps**: Vaultwarden, Uptime Kuma, WordPress, Wiki.js, Vikunja, Zammad, and more

## TODO

### 1. Secrets Management

Before moving to staging/production, configure required secrets for each application:

#### Vaultwarden
- `ADMIN_TOKEN` - Admin panel access
- `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_FROM` - Email for verification/password resets
- Database credentials (if using PostgreSQL instead of SQLite)
- Optional: `YUBICO_CLIENT_ID`, `YUBICO_SECRET_KEY` - Hardware key support

#### Uptime Kuma
- SMTP credentials - Email alerts for downtime
- Notification webhook URLs (Discord, Slack, etc.)

#### WordPress (Homepage)
- Database credentials
- WordPress salts: `WORDPRESS_AUTH_KEY`, `WORDPRESS_SECURE_AUTH_KEY`, etc.
- SMTP credentials - Email notifications
- Optional: S3 credentials for media storage

#### Wiki.js
- Database credentials
- SMTP credentials
- Optional: OAuth/OIDC credentials for SSO

#### Vikunja
- Database credentials
- SMTP credentials
- Optional: OAuth/OIDC credentials

#### Zammad
- Database credentials
- Elasticsearch credentials
- SMTP credentials
- Optional: OAuth/OIDC for SSO

#### General
- Consider using **Sealed Secrets** or **External Secrets Operator** for secret management
- Different secret sets for staging vs production environments

### 2. Domain and Certificate Management

- [ ] Register/configure domain names for services
- [ ] Set up DNS records (A/CNAME records)
- [ ] Configure cert-manager for automatic TLS certificates
  - Let's Encrypt for production
  - Consider DNS-01 challenge for wildcard certs
- [ ] Configure Traefik IngressRoutes with TLS
- [ ] Plan domain structure:
  - `vault.makerspace.example.com`
  - `uptime.makerspace.example.com`
  - `wiki.makerspace.example.com`
  - etc.

### 3. Authentication & Authorization

#### Authelia Setup
- [ ] Deploy Authelia for centralized authentication
- [ ] Configure LDAP/Active Directory integration (if applicable)
- [ ] Set up 2FA/MFA requirements
- [ ] Configure access policies per application
- [ ] Integrate with applications supporting SSO (Wiki.js, Vikunja, etc.)

#### Kubernetes RBAC
- [ ] Define access levels for makerspace members:
  - **Viewers**: Read-only access to resources
  - **Developers**: Deploy to dev namespaces, view logs
  - **Operators**: Manage applications, no cluster-wide changes
  - **Admins**: Full cluster access
- [ ] Create ClusterRoles and RoleBindings
- [ ] Set up kubeconfig contexts for different user roles
- [ ] Document how to grant/revoke access
- [ ] Consider using OIDC provider for kubectl authentication

### 4. Storage Configuration (Talos/Proxmox Staging)

- [ ] Plan persistent storage strategy:
  - Local storage vs distributed storage (Longhorn, Rook-Ceph)
  - Backup and disaster recovery plan
  - Storage classes for different performance tiers
- [ ] Configure Talos Linux on Proxmox VMs
- [ ] Set up storage provider (e.g., Longhorn for replicated storage)
- [ ] Define PersistentVolume retention policies
- [ ] Plan backup strategy (Velero, native database backups)
- [ ] Size storage appropriately per application

### 5. Monitoring & Observability

- [ ] Finalize Prometheus/Grafana configuration
- [ ] Set up alerting rules (AlertManager)
- [ ] Configure Loki for log aggregation
- [ ] Create dashboards for key metrics
- [ ] Set up notification channels (email, Slack, etc.)
- [ ] Deploy Uptime Kuma on separate infrastructure (Raspberry Pi + MicroK8s)

### 6. Network & Security

- [ ] Network policies between namespaces
- [ ] Pod Security Standards/Policies
- [ ] Regular security scanning (Trivy, Falco)
- [ ] Firewall rules for Proxmox cluster
- [ ] VPN access for remote management (if needed)

### 7. Deployment Strategy

- [ ] Define promotion workflow: local → staging → production
- [ ] Set up staging environment (Talos on Proxmox)
- [ ] Production environment planning
- [ ] CI/CD integration (automated testing before promotion)
- [ ] Rollback procedures

### 8. Documentation

- [ ] Document application-specific configuration
- [ ] Create runbooks for common operations
- [ ] Disaster recovery procedures
- [ ] Onboarding guide for new makerspace members
- [ ] Architecture diagrams

### 9. Remaining App Deployments

- [ ] Deploy Postiz (fix dependency issue)
- [ ] Deploy Cryptpad
- [ ] Deploy Netbox
- [ ] Test all applications thoroughly in local environment

### 10. Known Issues / Tech Debt

#### Zammad Database Configuration
- **Current state (local)**: Uses built-in PostgreSQL from Helm chart
- **Issue**: Setting `postgresql.enabled: false` doesn't properly disable the built-in database
- **Attempted fix**: Overriding `DATABASE_URL` env var doesn't work - chart sets it internally
- **For staging/prod**: Need to investigate proper Helm chart configuration for external PostgreSQL
  - Check chart documentation for version >=11.0.0
  - May need to use different configuration method (not just env vars)
  - Alternative: Accept that Zammad uses its own managed PostgreSQL
- **SMTP requirement**: Zammad setup wizard requires working SMTP configuration
  - Cannot complete initial setup in local dev without SMTP server
  - For staging/prod: Configure SMTP credentials before deploying

## Quick Start

```bash
# Bootstrap FluxCD
flux bootstrap github \
  --owner=nielsfechtel \
  --repository=makerspace-gt-infrastructure \
  --branch=main \
  --path=./clusters/local \
  --personal

# Watch reconciliation
flux get kustomizations --watch

# Check application status
kubectl get helmreleases -A
```

## Troubleshooting

### Flux source-controller read-only filesystem
If you see "read-only file system" errors in source-controller:
```bash
kubectl delete pod -n flux-system -l app=source-controller
```

### CNPG database won't start after PVC deletion
Delete the entire Cluster resource to reset state:
```bash
kubectl delete cluster -n <namespace> <cluster-name>
```

### Disk pressure issues
- Move Docker data directory to larger partition
- Update `/etc/docker/daemon.json` with new data-root
- Be careful with `chown` - it can cause permission issues with Kubernetes pods
