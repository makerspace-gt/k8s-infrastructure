# Developer Procedures

## Sealed Secrets

All secrets in this repo are encrypted using [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets). The public cert is at `clusters/staging/certs/staging-sealed-secrets-public-cert.pem`.

### Creating a Sealed Secret

```bash
# 1. Create a regular Kubernetes secret (dry-run, not applied)
kubectl create secret generic my-secret \
  --namespace=<namespace> \
  --from-literal=key=value \
  --dry-run=client -o yaml > secret.yaml

# 2. Seal it using the cluster's public cert
kubeseal \
  --cert clusters/staging/certs/staging-sealed-secrets-public-cert.pem \
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

## TLS — Trusting the Staging CA

The staging cluster uses a self-signed CA (managed by cert-manager) to issue TLS certs for all `*.staging.local` services. To avoid browser warnings, install the CA cert on your machine.

### Export the CA cert

From the devcontainer or any machine with kubectl access:

```bash
kubectl get secret staging-ca-secret -n cert-manager -o jsonpath='{.data.tls\.crt}' | base64 -d > staging-ca.crt
```

### Install on your host machine

**Arch Linux:**
```bash
sudo trust anchor staging-ca.crt
```

**Ubuntu/Debian:**
```bash
sudo cp staging-ca.crt /usr/local/share/ca-certificates/staging-ca.crt
sudo update-ca-certificates
```

**macOS:**
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain staging-ca.crt
```

Then **restart your browser** — it caches the trust store.

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

**Apply and reboot:**
```bash
talosctl apply-config --file talos/staging/controlplane-01.yaml --nodes 192.168.0.22 --mode staged
talosctl reboot --nodes 192.168.0.22 --wait
```

**Verify:** `curl 192.168.0.22:2381/metrics`

## Metrics Server

Enables `kubectl top` and HPA. Requires kubelet cert rotation on all nodes. See [Talos docs](https://docs.siderolabs.com/kubernetes-guides/monitoring-and-observability/deploy-metrics-server).

**Config change** in all patch files (`controlplane-patch.yaml`, `worker-*-patch.yaml`):
```yaml
machine:
  kubelet:
    extraArgs:
      rotate-server-certificates: true
```

**Apply, reboot one at a time, then deploy:**
```bash
talosctl apply-config --file talos/staging/controlplane-01.yaml --nodes 192.168.0.22 --mode staged
talosctl apply-config --file talos/staging/worker-01.yaml --nodes 192.168.0.40 --mode staged
talosctl apply-config --file talos/staging/worker-02.yaml --nodes 192.168.0.71 --mode staged

talosctl reboot --nodes 192.168.0.22 --wait
talosctl reboot --nodes 192.168.0.40 --wait
talosctl reboot --nodes 192.168.0.71 --wait

kubectl apply -f https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/main/deploy/standalone-install.yaml
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
```

**Verify:** `kubectl top nodes`

---

**Warning:** The baseline is a blind whitelist — `detect-secrets` cannot distinguish encrypted data from plaintext passwords. When updating the baseline, review what was flagged before accepting it. Use `detect-secrets audit .secrets.baseline` to interactively review each entry. Never blindly run `scan --baseline` after adding non-sealed-secret files.
