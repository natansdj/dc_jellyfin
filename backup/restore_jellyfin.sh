#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================================
# Jellyfin Manual Restore Script (Docker, NUC14)
# ----------------------------------------------------------------------------
# Purpose
# - Automate Jellyfin's official manual restore workflow:
#   1) Stop Jellyfin
#   2) Move current data/config out of the way (backup .bak copy)
#   3) Copy data/config from a known-good backup
#   4) Start Jellyfin again
#
# Supported backup input formats
# - Snapshot directory produced by backup_jellyfin.sh:
#   /path/to/jellyfin.<timestamp>_<version>/
# - Archive produced by backup_jellyfin.sh:
#   /path/to/jellyfin.<timestamp>_<version>.tar.gz
#
# Safety controls
# - This script refuses to proceed unless both data and config exist in backup.
# - Existing host directories are moved to timestamped .bak locations.
# - Original runtime state is restored (container restarted) on script exit,
#   unless KEEP_STOPPED=1.
#
# Important operational note
# - Restoring across incompatible Jellyfin versions may fail.
# - If required, run the same Jellyfin version that created the backup first.
#
# How to execute (step-by-step)
# 1) Ensure you have a known-good backup path (directory or .tar.gz).
# 2) Open terminal in repository root.
# 3) Run restore from backup directory:
#      ./backup/restore_jellyfin.sh backup/snapshots/jellyfin.YYYYMMDDHHMMSS_VERSION
# 4) Or restore from archive:
#      ./backup/restore_jellyfin.sh backup/snapshots/jellyfin.YYYYMMDDHHMMSS_VERSION.tar.gz
# 5) Optional safe inspection mode (do not auto-start container):
#      KEEP_STOPPED=1 ./backup/restore_jellyfin.sh <backup-path>
# 6) Optional skip cache/log restore:
#      RESTORE_CACHE=0 RESTORE_LOG=0 ./backup/restore_jellyfin.sh <backup-path>
# 7) Validate service health:
#      docker ps --filter name=jellyfin
#      docker logs --tail 200 jellyfin
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Docker container to stop/start during restore.
CONTAINER_NAME="${CONTAINER_NAME:-jellyfin}"
# Set KEEP_STOPPED=1 to leave container stopped after restore.
KEEP_STOPPED="${KEEP_STOPPED:-0}"

# Destination paths used by your compose bind mounts (host side).
JELLYFIN_CONFIG_DST="${JELLYFIN_CONFIG_DST:-/mnt/lxc/jellyfin_data/etc}"
JELLYFIN_DATA_DST="${JELLYFIN_DATA_DST:-/mnt/lxc/jellyfin_data/lib}"
JELLYFIN_CACHE_DST="${JELLYFIN_CACHE_DST:-/mnt/lxc/jellyfin_data/cache}"
JELLYFIN_LOG_DST="${JELLYFIN_LOG_DST:-/mnt/lxc/jellyfin_data/log}"

# Optional restores for cache/log from backup if available.
RESTORE_CACHE="${RESTORE_CACHE:-1}"
RESTORE_LOG="${RESTORE_LOG:-1}"

# Temporary extraction root for .tar.gz inputs.
WORK_ROOT="${WORK_ROOT:-${REPO_ROOT}/backup/.restore_work}"

REQUIRED_BINS=(docker cp mv mkdir rm tar date basename dirname)

was_running=0
extracted_backup_dir=""

usage() {
  cat <<'EOF'
Usage:
  ./backup/restore_jellyfin.sh <backup-path>

Where <backup-path> is one of:
  1) Snapshot directory:
     backup/snapshots/jellyfin.YYYYMMDDHHMMSS_VERSION
  2) Archive file:
     backup/snapshots/jellyfin.YYYYMMDDHHMMSS_VERSION.tar.gz

Environment overrides:
  CONTAINER_NAME=<name>       Docker container name (default: jellyfin)
  KEEP_STOPPED=1              Do not restart container after restore
  RESTORE_CACHE=0             Skip cache restore
  RESTORE_LOG=0               Skip log restore
  JELLYFIN_CONFIG_DST=<path>  Override config destination path
  JELLYFIN_DATA_DST=<path>    Override data destination path
  JELLYFIN_CACHE_DST=<path>   Override cache destination path
  JELLYFIN_LOG_DST=<path>     Override log destination path
EOF
}

log() {
  printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

require_bin() {
  local bin
  for bin in "${REQUIRED_BINS[@]}"; do
    if ! command -v "${bin}" >/dev/null 2>&1; then
      echo "Missing required command: ${bin}" >&2
      exit 1
    fi
  done
}

container_is_running() {
  local running
  running="$(docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null || true)"
  [[ "${running}" == "true" ]]
}

shutdown_jellyfin() {
  if container_is_running; then
    was_running=1
    log "Stopping container: ${CONTAINER_NAME}"
    docker stop "${CONTAINER_NAME}" >/dev/null
  else
    log "Container ${CONTAINER_NAME} is already stopped"
  fi
}

startup_jellyfin() {
  if [[ "${KEEP_STOPPED}" == "1" ]]; then
    log "KEEP_STOPPED=1, leaving container stopped"
    return
  fi

  if [[ "${was_running}" == "1" ]]; then
    log "Starting container: ${CONTAINER_NAME}"
    docker start "${CONTAINER_NAME}" >/dev/null
  fi
}

cleanup_temp() {
  if [[ -n "${extracted_backup_dir}" && -d "${extracted_backup_dir}" ]]; then
    log "Cleaning temporary extracted backup: ${extracted_backup_dir}"
    rm -rf "${extracted_backup_dir}"
  fi
}

finalize() {
  local exit_code=$?
  if [[ ${exit_code} -ne 0 ]]; then
    log "Restore failed (exit code ${exit_code})"
  fi
  cleanup_temp
  startup_jellyfin
  exit ${exit_code}
}

# Convert user input path into a concrete backup directory containing
# required data/config folders.
resolve_backup_dir() {
  local backup_input="$1"
  local base_name

  if [[ -d "${backup_input}" ]]; then
    echo "${backup_input}"
    return
  fi

  if [[ -f "${backup_input}" && "${backup_input}" == *.tar.gz ]]; then
    mkdir -p "${WORK_ROOT}"
    base_name="$(basename "${backup_input}" .tar.gz)"
    extracted_backup_dir="${WORK_ROOT}/${base_name}.extracted.$(date +%s)"

    log "Extracting archive to temporary directory"
    mkdir -p "${extracted_backup_dir}"
    tar -C "${extracted_backup_dir}" -xzf "${backup_input}"

    # backup_jellyfin.sh archives one top-level folder named like backup set.
    if [[ -d "${extracted_backup_dir}/${base_name}" ]]; then
      echo "${extracted_backup_dir}/${base_name}"
      return
    fi

    # Fallback for archives with unknown top-level folder name.
    local first_dir
    first_dir="$(find "${extracted_backup_dir}" -mindepth 1 -maxdepth 1 -type d | head -n1 || true)"
    if [[ -n "${first_dir}" ]]; then
      echo "${first_dir}"
      return
    fi
  fi

  echo "Invalid backup input: ${backup_input}" >&2
  exit 1
}

validate_backup_content() {
  local source_dir="$1"

  if [[ ! -d "${source_dir}/data" ]]; then
    echo "Backup is missing required folder: ${source_dir}/data" >&2
    exit 1
  fi

  if [[ ! -d "${source_dir}/config" ]]; then
    echo "Backup is missing required folder: ${source_dir}/config" >&2
    exit 1
  fi
}

move_aside_if_exists() {
  local target_path="$1"
  local ts
  ts="$(date +%Y%m%d%H%M%S)"

  if [[ -e "${target_path}" ]]; then
    local bak_path="${target_path}.bak.${ts}"
    log "Moving existing path to backup: ${bak_path}"
    mv "${target_path}" "${bak_path}"
  fi
}

restore_optional_dir() {
  local source_path="$1"
  local dest_path="$2"
  local enabled="$3"
  local label="$4"

  if [[ "${enabled}" != "1" ]]; then
    log "Skipping ${label} restore by configuration"
    return
  fi

  if [[ -d "${source_path}" ]]; then
    move_aside_if_exists "${dest_path}"
    log "Restoring ${label}"
    cp -a "${source_path}" "${dest_path}"
  else
    log "Backup does not include ${label}; skipping"
  fi
}

perform_restore() {
  local source_dir="$1"

  log "Validating backup content"
  validate_backup_content "${source_dir}"

  log "Preparing destination directories"
  mkdir -p "$(dirname "${JELLYFIN_DATA_DST}")"
  mkdir -p "$(dirname "${JELLYFIN_CONFIG_DST}")"
  mkdir -p "$(dirname "${JELLYFIN_CACHE_DST}")"
  mkdir -p "$(dirname "${JELLYFIN_LOG_DST}")"

  # Official flow: move current directories out of the way before copy.
  move_aside_if_exists "${JELLYFIN_DATA_DST}"
  move_aside_if_exists "${JELLYFIN_CONFIG_DST}"

  log "Restoring data directory"
  cp -a "${source_dir}/data" "${JELLYFIN_DATA_DST}"

  log "Restoring config directory"
  cp -a "${source_dir}/config" "${JELLYFIN_CONFIG_DST}"

  # Cache/log are optional in official guidance; useful if present in backup.
  restore_optional_dir "${source_dir}/cache" "${JELLYFIN_CACHE_DST}" "${RESTORE_CACHE}" "cache"
  restore_optional_dir "${source_dir}/log" "${JELLYFIN_LOG_DST}" "${RESTORE_LOG}" "log"

  log "Restore completed successfully"
}

main() {
  local backup_input="${1:-}"
  local backup_dir

  if [[ -z "${backup_input}" ]]; then
    usage
    exit 1
  fi

  require_bin
  trap finalize EXIT

  shutdown_jellyfin

  backup_dir="$(resolve_backup_dir "${backup_input}")"
  log "Resolved backup source: ${backup_dir}"

  perform_restore "${backup_dir}"
}

main "$@"
