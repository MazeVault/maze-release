#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# MazeVault — Legacy external CA configuration check (READ-ONLY)
#
# MazeVault 1.0.62 (database migration 000208) removes the tables
#   external_ca_configs
#   external_ca_template_mappings
# that backed the legacy "Configure External CA" flow of a certificate authority.
# The flow was replaced by organization CA accounts. The migration drops both
# tables unconditionally, so run this check BEFORE upgrading an installation
# that runs 1.0.61 or older.
#
# The script only reads. Every query runs in a READ ONLY transaction and the
# encrypted provider configuration (config_enc) is never selected or printed.
#
# Usage:
#   ./check-legacy-external-ca.sh [--dir /opt/mazevault] [--project mazevault]
#       Compose installation: queries the "postgres" service of the project.
#
#   DATABASE_URL='postgres://user@host:5432/mazevault' ./check-legacy-external-ca.sh --database-url
#       External database (Helm / managed PostgreSQL): uses the local psql client.
#       Provide the password through PGPASSWORD or ~/.pgpass, not on the command line.
#
# Exit codes:
#   0  safe to upgrade (tables absent, empty, or holding only soft-deleted rows)
#   2  active legacy configuration found — do NOT upgrade before migrating it
#   1  the check itself could not be completed
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

INSTALL_DIR="${MAZEVAULT_INSTALL_DIR:-/opt/mazevault}"
COMPOSE_PROJECT="mazevault"
USE_DATABASE_URL=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)          INSTALL_DIR="${2:?--dir requires a path}"; shift 2 ;;
    --project)      COMPOSE_PROJECT="${2:?--project requires a name}"; shift 2 ;;
    --database-url) USE_DATABASE_URL=true; shift ;;
    --help|-h)      sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; CYN='\033[0;36m'; RST='\033[0m'
info()  { echo -e "${CYN}[INFO]${RST}  $*"; }
ok()    { echo -e "${GRN}[OK]${RST}    $*"; }
warn()  { echo -e "${YLW}[WARN]${RST}  $*"; }
die()   { echo -e "${RED}[ERR]${RST}   $*" >&2; exit 1; }

# ── Database access ─────────────────────────────────────────────────────────
if [[ "${USE_DATABASE_URL}" == "true" ]]; then
  [[ -n "${DATABASE_URL:-}" ]] || die "--database-url requires the DATABASE_URL environment variable."
  command -v psql &>/dev/null || die "psql client not found."
  run_psql() { psql "${DATABASE_URL}" -X -q -v ON_ERROR_STOP=1 "$@"; }
  info "Target: database from DATABASE_URL (local psql client)"
else
  [[ -d "${INSTALL_DIR}" ]] || die "Install dir ${INSTALL_DIR} not found. Use --dir or --database-url."
  [[ -f "${INSTALL_DIR}/.env" ]] || die ".env not found in ${INSTALL_DIR}"

  if command -v docker &>/dev/null; then
    COMPOSE_CMD="docker compose"
    docker compose version &>/dev/null || COMPOSE_CMD="docker-compose"
  elif command -v podman &>/dev/null; then
    COMPOSE_CMD="podman-compose"
  else
    die "No container runtime found."
  fi

  cd "${INSTALL_DIR}"
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
  [[ -n "${POSTGRES_USER:-}" && -n "${POSTGRES_DB:-}" ]] || die "POSTGRES_USER / POSTGRES_DB missing in .env"
  run_psql() {
    ${COMPOSE_CMD} -p "${COMPOSE_PROJECT}" exec -T postgres \
      psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" -X -q -v ON_ERROR_STOP=1 "$@"
  }
  info "Target: compose project '${COMPOSE_PROJECT}' in ${INSTALL_DIR} (version ${IMAGE_TAG:-unknown})"
fi

# Runs one statement in a READ ONLY transaction and prints unaligned tuples.
query() {
  run_psql -At -F '|' <<SQL
BEGIN TRANSACTION READ ONLY;
$1
ROLLBACK;
SQL
}

# Same, but as a human-readable table.
query_table() {
  run_psql <<SQL
BEGIN TRANSACTION READ ONLY;
$1
ROLLBACK;
SQL
}

query "SELECT 1;" >/dev/null || die "Cannot query the database."

# ── Where the installation stands ───────────────────────────────────────────
LAST_MIGRATION="$(query "SELECT COALESCE(max(version), 'none') FROM schema_migrations;" 2>/dev/null || echo "unknown")"
DROP_APPLIED="$(query "SELECT count(*) FROM schema_migrations WHERE version = '000208_drop_external_ca_configs';" 2>/dev/null || echo "0")"
info "Last applied migration: ${LAST_MIGRATION}"

table_exists() {
  [[ "$(query "SELECT (to_regclass('public.$1') IS NOT NULL)::int;")" == "1" ]]
}

if ! table_exists external_ca_configs; then
  if [[ "${DROP_APPLIED}" != "0" ]]; then
    ok "Migration 000208 is already applied; the legacy tables are gone. Nothing to check."
  else
    ok "Table external_ca_configs does not exist in this database. Nothing to check."
  fi
  exit 0
fi

# ── Counts ──────────────────────────────────────────────────────────────────
ACTIVE_CONFIGS="$(query "SELECT count(*) FROM external_ca_configs WHERE deleted_at IS NULL;")" || die "Cannot count external_ca_configs."
DELETED_CONFIGS="$(query "SELECT count(*) FROM external_ca_configs WHERE deleted_at IS NOT NULL;")" || die "Cannot count external_ca_configs."
[[ "${ACTIVE_CONFIGS}" =~ ^[0-9]+$ && "${DELETED_CONFIGS}" =~ ^[0-9]+$ ]] || die "Unexpected answer from the database."
MAPPINGS=0
ACTIVE_MAPPINGS=0
if table_exists external_ca_template_mappings; then
  MAPPINGS="$(query "SELECT count(*) FROM external_ca_template_mappings;")" || die "Cannot count external_ca_template_mappings."
  ACTIVE_MAPPINGS="$(query "SELECT count(*) FROM external_ca_template_mappings m JOIN external_ca_configs c ON c.id = m.ca_config_id WHERE c.deleted_at IS NULL;")" || die "Cannot count external_ca_template_mappings."
fi

echo ""
echo "  external_ca_configs            active: ${ACTIVE_CONFIGS}   soft-deleted: ${DELETED_CONFIGS}"
echo "  external_ca_template_mappings  total:  ${MAPPINGS}   of active configs: ${ACTIVE_MAPPINGS}"
echo ""

if [[ "${ACTIVE_CONFIGS}" == "0" ]]; then
  if [[ "${DELETED_CONFIGS}" != "0" || "${MAPPINGS}" != "0" ]]; then
    warn "Only soft-deleted configurations (and their mappings) remain. They are not used by MazeVault."
  fi
  ok "No active legacy external CA configuration. Safe to upgrade past 1.0.61."
  exit 0
fi

# ── Details of what would be lost (no secrets) ──────────────────────────────
warn "Active legacy external CA configuration found:"
query_table "
SELECT c.id                                   AS config_id,
       c.provider_type,
       c.status,
       ca.name                                AS certificate_authority,
       ca.type                                AS ca_type,
       c.created_at::date                     AS created,
       c.last_connected_at::date              AS last_connected,
       (SELECT count(*) FROM external_ca_template_mappings m WHERE m.ca_config_id = c.id) AS template_mappings,
       (SELECT count(*) FROM certificates x
         WHERE x.ca_id = c.ca_id AND x.archived_at IS NULL AND x.deleted_at IS NULL)     AS certificates_on_this_ca,
       (SELECT count(*) FROM certificates x
         WHERE x.ca_id = c.ca_id AND x.archived_at IS NULL AND x.deleted_at IS NULL
           AND x.organization_ca_account_id IS NULL)                                     AS certificates_without_ca_account
FROM external_ca_configs c
LEFT JOIN certificate_authorities ca ON ca.id = c.ca_id
WHERE c.deleted_at IS NULL
ORDER BY c.created_at;" || warn "Could not list the details; the counts above still apply."

echo ""
echo -e "${RED}[STOP]${RST}  Do NOT upgrade this installation past 1.0.61 yet."
echo "        Migration 000208 would drop the configuration listed above."
echo "        Before upgrading:"
echo "          1. Create an organization CA account for each provider listed"
echo "             (organization detail → Certificate Authorities) and verify it connects."
echo "          2. Assign that CA account to the certificate templates that used"
echo "             the legacy authority, so renewals keep working."
echo "          3. Certificates counted in 'certificates_without_ca_account' have"
echo "             no CA account yet; re-bind them through their template."
echo "          4. Run this check again; it must report no active configuration."
exit 2
