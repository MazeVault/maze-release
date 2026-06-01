# MazeVault Customer Helm Chart

Public source chart for customer-managed MazeVault Kubernetes deployments.

MazeVault does not currently publish a hosted Helm repository. The supported public source is this chart in the release repository. Customers can vendor it into their own GitOps repository, package it internally, or install it directly from a checked-out copy of `maze-release`.

## Scope

This chart deploys the core MazeVault workloads:

- backend
- frontend
- docs
- OCSP responder

The default model is Azure-oriented Kubernetes with:

- external PostgreSQL
- external Redis
- Azure Key Vault through External Secrets Operator
- Workload Identity for secret access

## Quick Start

```bash
git clone https://github.com/MazeVault/maze-release.git
cd maze-release

helm lint ./helm/mazevault-customer
helm template mazevault ./helm/mazevault-customer \
  --namespace mazevault \
  -f ./helm/mazevault-customer/values.yaml
```

For a real installation, create an override file and replace the placeholder values from `values.yaml`.

```bash
cp ./helm/mazevault-customer/values.yaml ./values.customer.yaml

helm install mazevault ./helm/mazevault-customer \
  --namespace mazevault \
  --create-namespace \
  -f ./values.customer.yaml
```

## Secret Delivery

By default, the chart expects to materialize runtime secrets through External Secrets Operator.

- `global.keyVault.enabled=true` creates a `SecretStore`/`ExternalSecret` pair backed by Azure Key Vault
- workloads then read the generated runtime Kubernetes Secret

If you disable `global.keyVault.enabled`, pre-create the runtime Secret yourself with the keys expected by the workloads.

## Ingress Modes

`global.ingress.enabled=true` creates a Kubernetes `Ingress` for the application, docs, and optional OCSP host.

If the cluster uses a shared ingress layer managed outside this chart, set `global.ingress.enabled=false` and route traffic to the generated ClusterIP services instead.

## Notes

- Backend remains single-replica by default to avoid multi-writer migration and locking hazards.
- The chart ships generic placeholders only. No customer tenant IDs, vault URLs, registries, or personal contacts are included in this public copy.
- If you prefer to package the chart for an internal registry, use standard `helm package` / `helm repo index` tooling in your own delivery pipeline.