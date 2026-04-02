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

**Warning:** The baseline is a blind whitelist — `detect-secrets` cannot distinguish encrypted data from plaintext passwords. When updating the baseline, review what was flagged before accepting it. Use `detect-secrets audit .secrets.baseline` to interactively review each entry. Never blindly run `scan --baseline` after adding non-sealed-secret files.
