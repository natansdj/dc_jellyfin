#!/usr/bin/env bash

set -Eeuo pipefail

# Jellyfin backup healthcheck
# - Validates that latest backup artifacts exist (snapshot dir, archive, checksum)
# - Verifies archive integrity via sha256 checksum
# - Exits non-zero for missing/invalid artifacts so cron/systemd can alert
#
# Usage:
#   ./backup/healthcheck_backup.sh
#   BACKUP_ROOT=/path/to/backups ./backup/healthcheck_backup.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
BACKUP_ROOT="${BACKUP_ROOT:-${REPO_ROOT}/backup/snapshots}"

REQUIRED_BINS=(find basename sha256sum date)

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

require_bin() {
  local bin
  for bin in "${REQUIRED_BINS[@]}"; do
    command -v "${bin}" >/dev/null 2>&1 || die "Missing required command: ${bin}"
  done
}

latest_archive() {
  find "${BACKUP_ROOT}" -maxdepth 1 -type f -name 'jellyfin.*_*.tar.gz' -printf '%f\n' \
    | LC_ALL=C sort \
    | tail -n1
}

main() {
  local archive_name
  local base_name
  local archive_path
  local checksum_path
  local snapshot_path

  require_bin

  [[ -d "${BACKUP_ROOT}" ]] || die "Backup root does not exist: ${BACKUP_ROOT}"

  archive_name="$(latest_archive || true)"
  [[ -n "${archive_name}" ]] || die "No backup archive found in ${BACKUP_ROOT}"

  base_name="${archive_name%.tar.gz}"
  archive_path="${BACKUP_ROOT}/${archive_name}"
  checksum_path="${BACKUP_ROOT}/${archive_name}.sha256"
  snapshot_path="${BACKUP_ROOT}/${base_name}"

  [[ -f "${archive_path}" ]] || die "Missing backup archive: ${archive_path}"
  [[ -f "${checksum_path}" ]] || die "Missing checksum file: ${checksum_path}"
  [[ -d "${snapshot_path}" ]] || die "Missing snapshot directory: ${snapshot_path}"

  log "Validating checksum: ${checksum_path}"
  (
    cd "${BACKUP_ROOT}"
    sha256sum -c "${archive_name}.sha256" >/dev/null
  ) || die "Checksum validation failed for ${archive_name}"

  log "Healthcheck OK for latest backup set: ${base_name}"
}

main "$@"
