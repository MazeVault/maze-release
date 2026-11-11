#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# MazeVault — Upgrade Script
# Usage: sudo ./upgrade-mazevault.sh [--version v1.3.0] [--dir /opt/mazevault]
#
# Performs: pre-flight checks → verified backup → pull/load images → rolling restart → health check
#
# The database backup is mandatory: the upgrade stops when the dump cannot be
# taken or does not verify, because the backup is the only way back (database
# migrations are forward-only). Use --skip-db-backup only when the database is
# backed up by other means that you have verified yourself.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

INSTALL_DIR="${MAZEVAULT_INSTALL_DIR:-/opt/mazevault}"
TARGET_VERSION="${1:-}"
COMPOSE_PROJECT="mazevault"
BACKUP_DIR="${INSTALL_DIR}/backups"
SKIP_DB_BACKUP=false
ACCEPT_LEGACY_EXTERNAL_CA_LOSS=false

# ── Parse args ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) TARGET_VERSION="$2"; shift 2 ;;
    --dir)     INSTALL_DIR="$2"; BACKUP_DIR="${INSTALL_DIR}/backups"; shift 2 ;;
    --offline) OFFLINE_BUNDLE="$2"; shift 2 ;;
    --skip-db-backup) SKIP_DB_BACKUP=true; shift ;;
    --accept-legacy-external-ca-loss) ACCEPT_LEGACY_EXTERNAL_CA_LOSS=true; shift ;;
    --help|-h)
      echo "Usage: $0 --version TAG [--dir PATH] [--offline /path/to/bundle.tar.gz]"
      echo "          [--skip-db-backup] [--accept-legacy-external-ca-loss]"
      echo "  --skip-db-backup                  do not dump the database (only with an independently verified backup)"
      echo "  --accept-legacy-external-ca-loss  upgrade although active legacy external CA configuration"
      echo "                                    would be dropped (see check-legacy-external-ca.sh)"
      exit 0 ;;
    *) echo "Unknown: $1"; exit 1 ;;
  esac
done

# ── Colour helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; CYN='\033[0;36m'; RST='\033[0m'
info()  { echo -e "${CYN}[INFO]${RST}  $*"; }
ok()    { echo -e "${GRN}[OK]${RST}    $*"; }
warn()  { echo -e "${YLW}[WARN]${RST}  $*"; }
die()   { echo -e "${RED}[ERR]${RST}   $*" >&2; exit 1; }

# ── Pre-flight ──────────────────────────────────────────────────────────────
[[ "$(id -u)" -eq 0 ]] || die "Run as root."
[[ -d "${INSTALL_DIR}" ]] || die "Install dir ${INSTALL_DIR} not found."
[[ -f "${INSTALL_DIR}/.env" ]] || die ".env not found in ${INSTALL_DIR}"

# Detect runtime
if command -v docker &>/dev/null; then
  COMPOSE_CMD="docker compose"
  docker compose version &>/dev/null || COMPOSE_CMD="docker-compose"
elif command -v podman &>/dev/null; then
  COMPOSE_CMD="podman-compose"
else
  die "No container runtime found."
fi

cd "${INSTALL_DIR}"
set -a; source .env; set +a

CURRENT_VERSION="${IMAGE_TAG:-unknown}"
[[ -n "${TARGET_VERSION}" ]] || die "Target version required. Use --version v1.3.0"

info "Upgrading MazeVault: ${CURRENT_VERSION} → ${TARGET_VERSION}"

# Runs one read-only statement against the MazeVault database and prints the bare result.
db_query() {
  ${COMPOSE_CMD} -p "${COMPOSE_PROJECT}" exec -T postgres \
    psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -X -q -At -v ON_ERROR_STOP=1 <<SQL
BEGIN TRANSACTION READ ONLY;
$1
ROLLBACK;
SQL
}

# A usable dump is a valid gzip stream that ends with pg_dump's completion marker.
verify_db_dump() {
  local dump="$1"
  [[ -s "${dump}" ]] || return 1
  gzip -t "${dump}" 2>/dev/null || return 1
  gunzip -c "${dump}" | tail -n 20 | grep -q "PostgreSQL database dump complete"
}

# ── Step 0: Pre-flight data checks ─────────────────────────────────────────
# Migration 000208 (first shipped in 1.0.62) drops the legacy external CA
# configuration tables. Refuse to continue while they still hold active rows.
info "Checking for legacy external CA configuration..."
LEGACY_TABLE="$(db_query "SELECT (to_regclass('public.external_ca_configs') IS NOT NULL)::int;")" \
  || die "Cannot query the database for the pre-flight check. Is the postgres service running?"
if [[ "${LEGACY_TABLE}" == "1" ]]; then
  LEGACY_ACTIVE="$(db_query "SELECT count(*) FROM external_ca_configs WHERE deleted_at IS NULL;")" \
    || die "Cannot count rows in external_ca_configs."
  [[ "${LEGACY_ACTIVE}" =~ ^[0-9]+$ ]] || die "Unexpected answer from the database during the pre-flight check."
  if [[ "${LEGACY_ACTIVE}" != "0" ]]; then
    if [[ "${ACCEPT_LEGACY_EXTERNAL_CA_LOSS}" == "true" ]]; then
      warn "${LEGACY_ACTIVE} active legacy external CA configuration(s) will be dropped by this upgrade (--accept-legacy-external-ca-loss)."
    else
      die "${LEGACY_ACTIVE} active legacy external CA configuration(s) would be dropped by this upgrade. Run ./check-legacy-external-ca.sh for details and migrate them to organization CA accounts first."
    fi
  else
    ok "No active legacy external CA configuration"
  fi
else
  ok "Legacy external CA tables already removed"
fi

# ── Step 1: Pre-upgrade backup ─────────────────────────────────────────────
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="${BACKUP_DIR}/pre-upgrade_${TIMESTAMP}"
# The backup holds .env (master key) and the database dump: owner-only access.
( umask 077; mkdir -p "${BACKUP_PATH}" )
chmod 700 "${BACKUP_PATH}"

info "Backing up configuration..."
cp .env "${BACKUP_PATH}/.env"
chmod 600 "${BACKUP_PATH}/.env"
cp docker-compose.yml "${BACKUP_PATH}/docker-compose.yml" 2>/dev/null || true
echo "${CURRENT_VERSION}" > "${BACKUP_PATH}/version.txt"

if [[ "${SKIP_DB_BACKUP}" == "true" ]]; then
  warn "Database backup skipped (--skip-db-backup). Rollback of the database will not be possible from ${BACKUP_PATH}."
else
  info "Backing up database..."
  DB_DUMP="${BACKUP_PATH}/db_backup.sql.gz"
  DB_DUMP_LOG="${BACKUP_PATH}/db_backup.log"
  if ! ( umask 077; ${COMPOSE_CMD} -p "${COMPOSE_PROJECT}" exec -T postgres \
        pg_dump -U "${POSTGRES_USER}" "${POSTGRES_DB}" 2>"${DB_DUMP_LOG}" | gzip > "${DB_DUMP}.partial" ); then
    rm -f "${DB_DUMP}.partial"
    die "Database backup failed (see ${DB_DUMP_LOG}). Upgrade aborted; nothing was changed."
  fi
  if ! verify_db_dump "${DB_DUMP}.partial"; then
    rm -f "${DB_DUMP}.partial"
    die "Database backup did not verify (see ${DB_DUMP_LOG}). Upgrade aborted; nothing was changed."
  fi
  mv "${DB_DUMP}.partial" "${DB_DUMP}"
  ok "Database backup verified ($(du -h "${DB_DUMP}" | cut -f1))"
fi

info "Backing up certificates..."
cp -r certs/ "${BACKUP_PATH}/certs/" 2>/dev/null || true

ok "Backup saved to ${BACKUP_PATH}"

# ── Step 2: Pull/load new images ───────────────────────────────────────────
if [[ -n "${OFFLINE_BUNDLE:-}" ]]; then
  info "Loading images from offline bundle: ${OFFLINE_BUNDLE}"
  TMPDIR=$(mktemp -d)
  tar xzf "${OFFLINE_BUNDLE}" -C "${TMPDIR}"
  for tarball in "${TMPDIR}"/images/*.tar.gz; do
    [[ -f "$tarball" ]] || continue
    info "  Loading $(basename "$tarball")..."
    docker load < <(gunzip -c "$tarball")
  done
  rm -rf "${TMPDIR}"
else
  info "Pulling images for ${TARGET_VERSION}..."
  sed -i "s/^IMAGE_TAG=.*/IMAGE_TAG=${TARGET_VERSION}/" .env
  set -a; source .env; set +a
  ${COMPOSE_CMD} -p "${COMPOSE_PROJECT}" pull
fi

# ── Step 3: Update .env version ────────────────────────────────────────────
sed -i "s/^IMAGE_TAG=.*/IMAGE_TAG=${TARGET_VERSION}/" .env

# ── Step 4: Rolling restart ────────────────────────────────────────────────
info "Restarting services..."
${COMPOSE_CMD} -p "${COMPOSE_PROJECT}" up -d --remove-orphans

# ── Step 5: Health check ───────────────────────────────────────────────────
info "Verifying health..."
TRIES=0; MAX=30
while [[ $TRIES -lt $MAX ]]; do
  if curl -sk "https://localhost:${FRONTEND_PORT:-443}/api/v1/health" 2>/dev/null | grep -q "ok"; then
    ok "Services healthy after upgrade"
    break
  fi
  TRIES=$((TRIES+1)); sleep 2
done
if [[ $TRIES -ge $MAX ]]; then
  warn "Health check failed — consider rollback: ./rollback-mazevault.sh ${BACKUP_PATH}"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  ✅ Upgrade complete: ${CURRENT_VERSION} → ${TARGET_VERSION}"
echo "  Rollback: sudo ./rollback-mazevault.sh ${BACKUP_PATH}"
echo "═══════════════════════════════════════════════════════════════"
