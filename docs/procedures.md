# Developer Procedures

## Sealed Secrets

All secrets in this repo are encrypted using [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets). The public cert is at `cluster/certs/sealed-secrets-public-cert.pem`.

### Creating a Sealed Secret

Pipe the dry-run secret straight into `kubeseal` — the plaintext lives only in the pipe
between the two commands and never touches disk, so there's no temp file to forget to
delete:

```bash
kubectl create secret generic my-secret \
  --namespace=<namespace> \
  --from-literal=key=value \
  --dry-run=client -o yaml \
| kubeseal \
    --cert cluster/certs/sealed-secrets-public-cert.pem \
    --controller-name=sealed-secrets \
    --controller-namespace=sealed-secrets \
    --format yaml > sealed-secret.yaml

# Then commit sealed-secret.yaml (encrypted data is safe to commit).
```

For secrets with a generated random value you also need to store elsewhere (e.g. a DB
password going into Vaultwarden), capture it in a shell variable first so you can read it
back without it ever hitting a file:

```bash
PW=$(openssl rand -base64 24)   # copy $PW into Vaultwarden now
kubectl create secret generic my-secret \
  --namespace=<namespace> \
  --from-literal=password="$PW" \
  --dry-run=client -o yaml \
| kubeseal --cert cluster/certs/sealed-secrets-public-cert.pem \
    --controller-name=sealed-secrets --controller-namespace=sealed-secrets \
    --format yaml > sealed-secret.yaml
```

### Creating a Basic Auth Sealed Secret (for Traefik)

Traefik's `basicAuth` middleware expects a secret with an `users` key containing htpasswd-formatted entries.

```bash
# 1. Generate htpasswd entry
`htpasswd -nb username <enter, paste password>`

# 2. Create the secret and pipe straight into kubeseal (see above — no temp file)
kubectl create secret generic <name> \
  --namespace=<namespace> \
  --from-literal=users='<htpasswd-output>' \
  --dry-run=client -o yaml \
| kubeseal --cert cluster/certs/sealed-secrets-public-cert.pem \
    --controller-name=sealed-secrets --controller-namespace=sealed-secrets \
    --format yaml > sealed-secret.yaml
```

### Restoring the controller key (all SealedSecrets fail to decrypt)

**Symptom:** every SealedSecret shows `SYNCED=False` and the controller logs
`no key could decrypt secret`. Apps that depend on a SealedSecret get stuck
(`CreateContainerConfigError`, missing-secret); apps that don't (e.g. CNPG, which
generates its own secrets) are unaffected.

**Cause:** the running controller's key no longer matches the cert the repo's
secrets were sealed with. This happens after a cluster rebuild — a fresh
controller generates a brand-new key instead of the original. Confirm by
comparing fingerprints:

```bash
# what the repo's secrets were sealed with
openssl x509 -in cluster/certs/sealed-secrets-public-cert.pem -noout -fingerprint -sha256
# what the live controller actually holds (active key)
kubeseal --fetch-cert --controller-namespace sealed-secrets --controller-name sealed-secrets \
  | openssl x509 -noout -fingerprint -sha256
```

If they differ, the original signing key is missing. The fix is to **restore it,
not re-seal everything** — the controller holds multiple keys and tries them all,
so adding the old key back is additive and non-destructive.

```bash
# 1. From your password-manager backup (the kubernetes.io/tls key Secret), get the
#    cert + key into real PEM files. If stored as escaped strings, strip quotes and
#    un-escape newlines:
yq '."tls.crt"' backup-key.yaml | tr -d '"' | sed 's/\\n/\n/g' > /tmp/sealed.crt
yq '."tls.key"' backup-key.yaml | tr -d '"' | sed 's/\\n/\n/g' > /tmp/sealed.key

# 2. Verify it's the right key: fingerprint must match the repo cert above, and the
#    cert/key modulus md5s must be equal.
openssl x509 -in /tmp/sealed.crt -noout -fingerprint -sha256
openssl x509 -in /tmp/sealed.crt -noout -modulus | openssl md5
openssl rsa  -in /tmp/sealed.key -noout -modulus | openssl md5

# 3. Recreate the key Secret with the label the controller scans for, then restart it.
kubectl -n sealed-secrets create secret tls sealed-secrets-key-restored \
  --cert=/tmp/sealed.crt --key=/tmp/sealed.key
kubectl -n sealed-secrets label secret sealed-secrets-key-restored \
  sealedsecrets.bitnami.com/sealed-secrets-key=active
kubectl -n sealed-secrets rollout restart deployment sealed-secrets

# 4. All SealedSecrets flip to SYNCED=True; dependent pods recover on their own
#    (CreateContainerConfigError auto-retries once the Secret exists).
kubectl get sealedsecret -A
rm -f /tmp/sealed.crt /tmp/sealed.key
```

The backup key is the only thing that can decrypt the repo's secrets — keep it in
the password manager, never in the repo. Re-sealing onto a new controller key is
the fallback **only** if the original is truly lost (requires every secret's
plaintext, and updating `cluster/certs/sealed-secrets-public-cert.pem`).

### Retrieving/Decoding a Secret

In k9s or:
```bash
kubectl get secret <name> -n <namespace> -o yaml
kubectl get secret <name> -n <namespace> -o jsonpath='{.data.key}' | base64 -d
```

## detect-secrets Baseline

The repo uses [detect-secrets](https://github.com/Yelp/detect-secrets) as a pre-commit hook. Sealed secrets contain encrypted data that triggers false positives.

After adding a new sealed secret, update the baseline:

```bash
detect-secrets scan --baseline .secrets.baseline
```

This rescans and marks the new entries as known/expected.

---

## Etcd Metrics

Exposes etcd's Prometheus metrics on port 2381 (control plane only). See [Talos docs](https://docs.siderolabs.com/kubernetes-guides/monitoring-and-observability/etcd-metrics).

**Config change** in `controlplane-patch.yaml`:
```yaml
cluster:
  etcd:
    extraArgs:
      listen-metrics-urls: http://0.0.0.0:2381
```

**Apply and reboot** (per node — the setting lives in each CP's patch):
```bash
talosctl apply-config --file talos/controlplane.yaml --nodes <cp-ip> --mode staged
talosctl reboot --nodes <cp-ip> --wait
```

**Verify:** `curl <cp-ip>:2381/metrics`

> **Security note:** Port 2381 listens on `0.0.0.0`, so it's reachable from the local network. Acceptable here; if exposing more broadly, restrict via Talos `networkRules` or Cilium host firewall.

**Prometheus scraping.** etcd runs *outside* Kubernetes (a Talos-managed process, not a
pod), so kube-prometheus-stack's default `kubeEtcd` Service — which has a
`component=etcd` selector — gets **empty** Endpoints from the endpoint-controller (no
matching pods) and scrapes nothing. A hand-written `Endpoints` of the same name does not
help: the controller owns it and keeps blanking it. The working wiring is the chart's
external-etcd path — set `kubeEtcd.endpoints` (all CP IPs) in
`monitoring/kube-prometheus-stack/helmrelease.yaml`, which renders a **selector-less**
Service plus a static `Endpoints`:

```yaml
kubeEtcd:
  enabled: true
  service: { enabled: true, port: 2381, targetPort: 2381 }
  endpoints: [192.168.0.68, 192.168.0.157, 192.168.0.21]
```

Verify: `up{job="kube-etcd"}` should show one `up` series per CP in Prometheus.

## Storage Access Modes (RWO vs RWX)

Choosing the wrong access mode for an app's PVC causes a `Multi-Attach` deadlock: an RWO
(ReadWriteOnce) volume attaches to **one node at a time**, so the moment a second pod that
needs it lands on a *different* node — a rolling update, a reschedule, or a second
Deployment sharing the same PVC — it can never attach and the new pod hangs in `Init`
forever. This is not configurable via the StorageClass: `accessMode` is requested
**per-PVC** by the chart/manifest, and a StorageClass cannot force or override it. So it is
always a per-workload decision. **RWX is not a safe blanket default** — it is served by a
per-volume Longhorn NFS share-manager pod (extra failure surface, slower than block), and
it is *actively wrong* for databases.

Pick the access mode by what owns the volume:

| Volume belongs to… | Access mode |
|---|---|
| A database / self-replicating workload (CNPG Postgres, valkey, anything using StatefulSet `volumeClaimTemplates`) | **RWO** — each replica has its own volume, no sharing. **Never RWX** (NFS + concurrent writers = corruption; these engines assume exclusive block storage). |
| One volume mounted by **multiple pods at once** — multiple Deployments sharing it (e.g. NetBox `web` + `worker`, WordPress, Vikunja media) or a multi-replica Deployment | **RWX** (`ReadWriteMany`) |
| A single-replica **Deployment** whose PVC outlives rollouts and you've hit multi-attach on a node move | **RWX** if you might ever scale out, otherwise `strategy: Recreate` (old pod dies before the new one starts — no NFS overhead) |

Set it in the HelmRelease values, e.g. `persistence.accessMode: ReadWriteMany` (Longhorn
is RWX-capable, so no StorageClass change is needed).

**Converting an existing RWO PVC to RWX.** `accessMode` is **immutable on a bound PVC**, so
Flux/Helm cannot change it in place — the PVC must be recreated, which **destroys its data**.
Only do this on empty/disposable volumes; otherwise back up (or `velero`/Longhorn-snapshot)
first and restore after. With the RWX value already committed and reconciled (so the
recreated PVC comes back RWX):

```bash
# 1. Release the volume — removes the pods holding it (old + any stuck Init pods)
kubectl scale deploy <app> [<app>-worker ...] -n <ns> --replicas=0
# 2. Delete the RWO PVC (Longhorn reclaims the backing volume; reclaim policy is Delete)
kubectl delete pvc <pvc-name> -n <ns>
# 3. Let Helm recreate it as RWX and scale the Deployments back itself
flux reconcile helmrelease <app> -n <ns> --with-source
```

Then verify a `share-manager-pvc-...` pod reaches Running in `longhorn-system` and the app
pods leave `Init`. If a pod sticks on mount, check its events for an **NFS** failure — the
one Talos-specific spot to watch on a cluster's first RWX volume.

**Warning:** The baseline is a blind whitelist — `detect-secrets` cannot distinguish encrypted data from plaintext passwords. When updating the baseline, review what was flagged before accepting it. Use `detect-secrets audit .secrets.baseline` to interactively review each entry. Never blindly run `scan --baseline` after adding non-sealed-secret files.

---

## MariaDB for an App (mariadb-operator)

MariaDB-backed apps (WordPress, etc.) use **mariadb-operator** (the MariaDB analogue of CNPG) in
`infrastructure/databases/mariadb-operator/`. CRDs ship as a separate chart installed first; the
webhook cert uses the operator's built-in controller, not cert-manager.

Provision a DB with one `MariaDB` CR — inline `database` + `username` + `passwordSecretKeyRef` +
`rootPasswordSecretKeyRef` make the operator create the database, user, and grant. Watch for:

- The operator **auto-creates a ClusterIP Service** named after the CR on :3306 — point the app at
  that name and share the same sealed secret (no `Connection` CRD needed).
- **NetworkPolicy:** a blanket-ingress namespace also selects the DB pod and silently drops the
  operator's connection, so the DB/user never get created. Allow the `mariadb-operator` namespace
  in on 3306. Signature: `MariaDB` CR `READY=True` but child `Database`/`User` show `i/o timeout`
  (timeout = policy drop, not a dead DB).
- TLS is enabled but **not enforced** — plaintext clients connect fine.
