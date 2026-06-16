# Developer Procedures

## Sealed Secrets

All secrets in this repo are encrypted using [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets). The public cert is at `cluster/certs/sealed-secrets-public-cert.pem`.

### Creating a Sealed Secret

```bash
# 1. Create a regular Kubernetes secret (dry-run, not applied)
kubectl create secret generic my-secret \
  --namespace=<namespace> \
  --from-literal=key=value \
  --dry-run=client -o yaml > secret.yaml

# 2. Seal it using the cluster's public cert
kubeseal \
  --cert cluster/certs/sealed-secrets-public-cert.pem \
  --controller-name=sealed-secrets \
  --controller-namespace=sealed-secrets \
  --format yaml < secret.yaml > sealed-secret.yaml

# 3. Delete the unencrypted secret
rm secret.yaml

# 4. Commit sealed-secret.yaml (encrypted data is safe to commit)
```

### Creating a Basic Auth Sealed Secret (for Traefik)

Traefik's `basicAuth` middleware expects a secret with an `users` key containing htpasswd-formatted entries.

```bash
# 1. Generate htpasswd entry
`htpasswd -nb username <enter, paste password>`

# 2. Create secret with the htpasswd output
kubectl create secret generic <name> \
  --namespace=<namespace> \
  --from-literal=users='<htpasswd-output>' \
  --dry-run=client -o yaml > secret.yaml

# 3. Seal and clean up as above
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

**Warning:** The baseline is a blind whitelist — `detect-secrets` cannot distinguish encrypted data from plaintext passwords. When updating the baseline, review what was flagged before accepting it. Use `detect-secrets audit .secrets.baseline` to interactively review each entry. Never blindly run `scan --baseline` after adding non-sealed-secret files.
