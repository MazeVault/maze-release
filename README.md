# MazeVault — Customer Releases

Enterprise Secrets Management & PKI Platform.

## Quick Start (Rocky Linux 9)

### Prerequisites

```bash
sudo dnf update -y
sudo dnf install -y podman podman-compose curl jq openssl
```

### Install (Online)

```bash
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"

curl -fsSL https://raw.githubusercontent.com/MazeVault/maze-release/main/install-mazevault.sh \
    -o install-mazevault.sh
chmod +x install-mazevault.sh

# Latest version:
./install-mazevault.sh

# Specific version:
MAZEVAULT_VERSION=v1.0.0 ./install-mazevault.sh
```

### Install (Offline / Air-gapped)

```bash
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"

curl -fsSL https://raw.githubusercontent.com/MazeVault/maze-release/main/install-mazevault-offline.sh \
    -o install-mazevault-offline.sh
chmod +x install-mazevault-offline.sh
MAZEVAULT_VERSION=v1.0.0 ./install-mazevault-offline.sh
```


### Configure & Start

```bash
nano /opt/mazevault/.env       # Fill in license credentials
# Start all services (systemd recommended):
sudo systemctl start mazevault
# Or, for manual compose:
cd /opt/mazevault && docker compose up -d
curl -k https://localhost:8443/api/v1/health
```

### Boot Resilience & Auto-Start

MazeVault now installs a systemd service (`mazevault.service`) automatically. This ensures all services start on every VM/server reboot. Docker is also enabled to start on boot. To check status:

```bash
sudo systemctl status mazevault
sudo systemctl status docker
```

**Note:** The install script must be run as root (sudo) to set up systemd and Docker auto-start.

### Custom TLS Certificate (Optional)

```bash
curl -fsSL https://raw.githubusercontent.com/MazeVault/maze-release/main/import-cert.sh \
    -o /opt/mazevault/import-cert.sh && chmod +x /opt/mazevault/import-cert.sh
/opt/mazevault/import-cert.sh /path/to/certificate.pfx
```

## Upgrade / Rollback

```bash
cd /opt/mazevault
./upgrade-mazevault.sh v1.1.0
./rollback-mazevault.sh          # if needed
```

## Files

| File | Description |
|------|-------------|
| `install-mazevault.sh` | Online installer (GHCR) |
| `install-mazevault-offline.sh` | Offline installer (tar.gz) |
| `upgrade-mazevault.sh` | Upgrade with backup |
| `rollback-mazevault.sh` | Rollback to previous version |
| `mirror-to-registry.sh` | Mirror to Nexus/Harbor |
| `import-cert.sh` | Import custom TLS cert (PFX/PEM/DER) |
| `renew-certs.sh` | Renew/rotate TLS certificates |
| `docker-compose.yml` | Production compose (HTTPS-first) |
| `.env.example` | Environment config template |

## Helm Chart

This repository also exposes the public customer Helm chart source in `helm/mazevault-customer`.

Partner onboarding and release readiness checklist is available in `CUSTOMER_RELEASE_CHECKLIST.md`.

MazeVault publishes this chart automatically as an OCI artifact to GHCR on each release tag (`vX.Y.Z`).

Primary distribution channel:

- `oci://ghcr.io/mazevault/charts/mazevault-customer`

If needed, customers can still clone this repository and install from local path.

### Consume Published Chart (Recommended)

```bash
echo "$GITHUB_TOKEN" | helm registry login ghcr.io -u YOUR_GITHUB_USER --password-stdin

helm pull oci://ghcr.io/mazevault/charts/mazevault-customer --version 1.2.3

helm upgrade --install mazevault oci://ghcr.io/mazevault/charts/mazevault-customer \
    --version 1.2.3 \
    --namespace mazevault \
    --create-namespace \
    -f ./values.customer.yaml
```

### Update Policy

- Every product release tag (`vX.Y.Z`) publishes matching chart version `X.Y.Z`.
- Chart breaking changes require a major chart version bump and release note.
- Customers should pin `--version` in their CI/CD and upgrade intentionally.

### Local Source Install (Fallback)

```bash
git clone https://github.com/MazeVault/maze-release.git
cd maze-release

helm lint ./helm/mazevault-customer
helm install mazevault ./helm/mazevault-customer \
    --namespace mazevault \
    --create-namespace \
    -f ./helm/mazevault-customer/values.yaml
```

For real deployments, replace the placeholder values from `helm/mazevault-customer/values.yaml` with customer-specific overrides in your own values file or GitOps repository.
