# MazeVault Customer Release Checklist

Partner onboarding checklist for customer-managed Kubernetes deployments using the MazeVault customer Helm chart.

Use this document before onboarding a new partner and before each customer-facing chart update.

## 1. Version and Compatibility

- [ ] Confirm release tag format: `vX.Y.Z`.
- [ ] Confirm chart version equals product release version (`X.Y.Z`).
- [ ] Confirm image tags used by customer values are intentional (`latest` only for non-production).
- [ ] Confirm partner CI/CD pins explicit chart version (`--version X.Y.Z`).
- [ ] Confirm release notes include any breaking chart or values changes.

## 2. Environment and Secret Mapping

- [ ] Confirm all required runtime configuration is present in partner values file.
- [ ] Confirm secret-only settings are not committed in plaintext values files.
- [ ] Confirm `global.keyVault.secretKeys.*` mapping matches partner key names.
- [ ] Confirm secret-driven values are available in runtime secret:
  - `DATABASE_URL`
  - `REDIS_URL`
  - `MAZEVAULT_MASTER_KEY`
  - `MAZEVAULT_JWT_KEY`
  - `MAZEVAULT_SESSION_SECRET`
- [ ] Confirm optional secrets are configured only when required:
  - `O365_CLIENT_SECRET`
  - `ENTRA_CLIENT_SECRET`
  - `AGENT_BINARY_GITHUB_TOKEN`
  - `SMTP_PASSWORD`

## 3. Cluster Prerequisites (AKS / ESO / Ingress)

- [ ] Kubernetes cluster is reachable from partner CI/CD and has target namespace policy approved.
- [ ] External Secrets Operator is installed and healthy.
- [ ] Workload Identity (or equivalent access model) is configured for Key Vault access.
- [ ] Ingress controller is available and class name in values matches cluster setup.
- [ ] TLS strategy is agreed (`clusterIssuer` and `secretName` or external certificate management).

## 4. Upgrade and Rollback Runbook

- [ ] Partner has a tested `helm upgrade --install` step with pinned chart version.
- [ ] Partner has rollback command documented (`helm rollback`).
- [ ] Partner stores previous values file and release revision metadata.
- [ ] Maintenance window and rollback decision owner are defined.

Reference commands:

```bash
helm upgrade --install mazevault oci://ghcr.io/mazevault/charts/mazevault-customer \
  --version X.Y.Z \
  --namespace mazevault \
  --create-namespace \
  -f values.customer.yaml

helm history mazevault -n mazevault
helm rollback mazevault <REVISION> -n mazevault
```

## 5. Smoke Tests and Health Verification

- [ ] Pods are healthy: `kubectl get pods -n <namespace>`.
- [ ] Services exist and endpoints are ready.
- [ ] Backend health endpoint returns success.
- [ ] Frontend and docs are reachable via ingress (or internal route if ingress disabled).
- [ ] Basic secret-backed flow works (database + redis connectivity).

Reference checks:

```bash
kubectl get pods -n mazevault
kubectl get ingress -n mazevault
kubectl get externalsecret -n mazevault
kubectl get secretstore -n mazevault
```

## 6. Security Verification (Signatures and Checksums)

- [ ] Release artifact checksums are available and validated.
- [ ] Required images are pulled from approved registry namespace.
- [ ] If required by partner policy, verify image signatures before promotion.
- [ ] Any registry mirroring preserves digest pinning and provenance records.

## 7. Documentation Release Gate (Documentation-Only)

Before publishing a customer-facing chart release, confirm:

- [ ] [README.md](README.md) reflects current distribution channel and install flow.
- [ ] [helm/mazevault-customer/README.md](helm/mazevault-customer/README.md) reflects current upgrade and maintainer process.
- [ ] Values/secret mapping changes are documented with examples.
- [ ] Any behavior-breaking changes are called out in release notes.

## 8. Partner Handover Package

- [ ] Pinned chart version to deploy.
- [ ] Partner values template (without secrets).
- [ ] Secret key mapping contract.
- [ ] Upgrade and rollback command set.
- [ ] Post-deploy smoke test checklist.

---

Owner: MazeVault release maintainer

Last updated: 2026-06-08
