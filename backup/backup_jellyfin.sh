#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================================
# Jellyfin Manual Backup Script (Docker, NUC14)
# ----------------------------------------------------------------------------
# Purpose
# - Create a consistent filesystem-level Jellyfin backup by following the
#   official manual backup flow:
#   1) Stop Jellyfin
#   2) Copy persistent directories
#   3) Start Jellyfin again
#
# Why this script exists
# - Jellyfin databases are SQLite based; copying while the server is active can
#   produce locked/inconsistent backups.
# - This script enforces stop-before-copy and captures metadata/checksums to
#   make restoration and verification easier.
#
# Output artifacts
# - Snapshot directory: ${BACKUP_ROOT}/jellyfin.<timestamp>_<version>/
# - Compressed archive: ${BACKUP_ROOT}/jellyfin.<timestamp>_<version>.tar.gz
# - Integrity file: ${BACKUP_ROOT}/jellyfin.<timestamp>_<version>.tar.gz.sha256
#
# Safe behavior
# - If Jellyfin was running when the script started, it is started again on
#   script exit (success or failure), unless KEEP_STOPPED=1.
#
# How to execute (step-by-step)
# 1) Open terminal in repository root.
# 2) Optional: verify target container is correct (default: jellyfin).
# 3) Run backup:
#      ./backup/backup_jellyfin.sh
# 4) Optional version label in backup name:
#      ./backup/backup_jellyfin.sh 10.10.7
# 5) Optional destination override:
#      BACKUP_ROOT=/path/to/backups ./backup/backup_jellyfin.sh
# 6) Verify outputs:
#      - backup directory
#      - .tar.gz archive
#      - .sha256 checksum file
#
# Retention policy
# - Retention is automatic after each successful backup.
# - Keep count is controlled by RETENTION_COUNT (default: 14).
# - Retention applies to snapshot directories and archive/checksum files.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TIMESTAMP="$(date +%Y%m%d%H%M%S)"
# Optional positional argument used only as a backup label.
# It does not change installed Jellyfin version.
VERSION="${1:-10.10}"

# Base output path for all backups. Override with BACKUP_ROOT env var.
BACKUP_ROOT="${BACKUP_ROOT:-${REPO_ROOT}/backup/snapshots}"
BACKUP_NAME="jellyfin.${TIMESTAMP}_${VERSION}"
BACKUP_DIR="${BACKUP_ROOT}/${BACKUP_NAME}"

# Docker container settings.
CONTAINER_NAME="${CONTAINER_NAME:-jellyfin}"
# Set KEEP_STOPPED=1 when you want to leave Jellyfin down after backup.
KEEP_STOPPED="${KEEP_STOPPED:-0}"
# Keep only N most recent backups in BACKUP_ROOT.
RETENTION_COUNT="${RETENTION_COUNT:-14}"

# Source paths currently used by docker-compose.nuc14.yml.
# These are host-side bind mount paths, not paths inside the container.
JELLYFIN_CONFIG_SRC="${JELLYFIN_CONFIG_SRC:-/mnt/lxc/jellyfin_data/etc}"
JELLYFIN_DATA_SRC="${JELLYFIN_DATA_SRC:-/mnt/lxc/jellyfin_data/lib}"
JELLYFIN_CACHE_SRC="${JELLYFIN_CACHE_SRC:-/mnt/lxc/jellyfin_data/cache}"
JELLYFIN_LOG_SRC="${JELLYFIN_LOG_SRC:-/mnt/lxc/jellyfin_data/log}"

# Required programs. Failing early avoids partial/ambiguous backups.
REQUIRED_BINS=(docker cp mkdir tar sha256sum date hostname)

# Tracks whether container was running before backup started.
was_running=0

# Standard timestamped logger for readable console output.
log() {
	printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

# Ensure all expected CLI dependencies are available.
require_bin() {
	local bin
	for bin in "${REQUIRED_BINS[@]}"; do
		if ! command -v "${bin}" >/dev/null 2>&1; then
			echo "Missing required command: ${bin}" >&2
			exit 1
		fi
	done
}

# Validate source directories exist before stopping service.
# This prevents unnecessary downtime when host paths are wrong/unmounted.
validate_paths() {
	local p
	for p in \
		"${JELLYFIN_CONFIG_SRC}" \
		"${JELLYFIN_DATA_SRC}" \
		"${JELLYFIN_CACHE_SRC}" \
		"${JELLYFIN_LOG_SRC}"; do
		if [[ ! -d "${p}" ]]; then
			echo "Source directory not found: ${p}" >&2
			exit 1
		fi
	done
}

# Return success only when the target container exists and is running.
container_is_running() {
	local running
	running="$(docker inspect -f '{{.State.Running}}' "${CONTAINER_NAME}" 2>/dev/null || true)"
	[[ "${running}" == "true" ]]
}

# Stop Jellyfin to satisfy official manual backup recommendation.
shutdown_jellyfin() {
	if container_is_running; then
		was_running=1
		log "Stopping container: ${CONTAINER_NAME}"
		docker stop "${CONTAINER_NAME}" >/dev/null
	else
		log "Container ${CONTAINER_NAME} is already stopped"
	fi
}

# Restore previous runtime state unless explicitly told otherwise.
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

# EXIT trap handler.
# Guarantees startup logic executes even when backup fails mid-way.
finalize() {
	local exit_code=$?
	if [[ ${exit_code} -ne 0 ]]; then
		log "Backup failed (exit code ${exit_code})"
	fi
	startup_jellyfin
	exit ${exit_code}
}

# Copy all selected Jellyfin state and create distributable artifacts.
create_backup() {
	log "Creating backup directory: ${BACKUP_DIR}"
	mkdir -p "${BACKUP_DIR}"

	log "Copying data directory"
	cp -a "${JELLYFIN_DATA_SRC}" "${BACKUP_DIR}/data"

	log "Copying config directory"
	cp -a "${JELLYFIN_CONFIG_SRC}" "${BACKUP_DIR}/config"

	log "Copying cache directory"
	cp -a "${JELLYFIN_CACHE_SRC}" "${BACKUP_DIR}/cache"

	log "Copying log directory"
	cp -a "${JELLYFIN_LOG_SRC}" "${BACKUP_DIR}/log"

	# Store the exact compose variant used by this machine for reproducibility.
	if [[ -f "${REPO_ROOT}/docker-compose.nuc14.yml" ]]; then
		cp -a "${REPO_ROOT}/docker-compose.nuc14.yml" "${BACKUP_DIR}/docker-compose.nuc14.yml"
	fi

	# BACKUP_INFO provides enough context to identify compatibility during restore.
	log "Writing metadata"
	cat > "${BACKUP_DIR}/BACKUP_INFO.txt" <<EOF
Backup name: ${BACKUP_NAME}
Created at: $(date -Is)
Host: $(hostname)
Container: ${CONTAINER_NAME}
Version label: ${VERSION}
Config source: ${JELLYFIN_CONFIG_SRC}
Data source: ${JELLYFIN_DATA_SRC}
Cache source: ${JELLYFIN_CACHE_SRC}
Log source: ${JELLYFIN_LOG_SRC}
EOF

	# Archive simplifies off-host transfer and long-term storage.
	log "Generating compressed archive"
	tar -C "${BACKUP_ROOT}" -czf "${BACKUP_ROOT}/${BACKUP_NAME}.tar.gz" "${BACKUP_NAME}"

	# Checksum enables integrity verification after copy/sync.
	log "Generating checksums"
	(
		cd "${BACKUP_ROOT}"
		sha256sum "${BACKUP_NAME}.tar.gz" > "${BACKUP_NAME}.tar.gz.sha256"
	)

	log "Backup completed"
	log "Directory backup: ${BACKUP_DIR}"
	log "Archive backup: ${BACKUP_ROOT}/${BACKUP_NAME}.tar.gz"
	log "Checksum file: ${BACKUP_ROOT}/${BACKUP_NAME}.tar.gz.sha256"
}

# Retention cleanup by backup naming convention.
# The backup naming format starts with timestamp, so lexical order maps to age.
prune_old_backups() {
	if [[ ! "${RETENTION_COUNT}" =~ ^[0-9]+$ ]]; then
		echo "RETENTION_COUNT must be a non-negative integer, got: ${RETENTION_COUNT}" >&2
		exit 1
	fi

	if [[ "${RETENTION_COUNT}" == "0" ]]; then
		log "RETENTION_COUNT=0, skipping retention pruning"
		return
	fi

	local path
	local old_count
	local -a dir_list=()
	local -a archive_list=()
	local -a checksum_list=()

	shopt -s nullglob
	for path in "${BACKUP_ROOT}"/jellyfin.*_*; do
		[[ -d "${path}" ]] && dir_list+=("${path}")
	done
	for path in "${BACKUP_ROOT}"/jellyfin.*_*.tar.gz; do
		[[ -f "${path}" ]] && archive_list+=("${path}")
	done
	for path in "${BACKUP_ROOT}"/jellyfin.*_*.tar.gz.sha256; do
		[[ -f "${path}" ]] && checksum_list+=("${path}")
	done
	shopt -u nullglob

	if (( ${#dir_list[@]} > RETENTION_COUNT )); then
		old_count=$(( ${#dir_list[@]} - RETENTION_COUNT ))
		for ((i=0; i<old_count; i++)); do
			log "Pruning old snapshot directory: ${dir_list[$i]}"
			rm -rf "${dir_list[$i]}"
		done
	fi

	if (( ${#archive_list[@]} > RETENTION_COUNT )); then
		old_count=$(( ${#archive_list[@]} - RETENTION_COUNT ))
		for ((i=0; i<old_count; i++)); do
			log "Pruning old archive: ${archive_list[$i]}"
			rm -f "${archive_list[$i]}"
		done
	fi

	if (( ${#checksum_list[@]} > RETENTION_COUNT )); then
		old_count=$(( ${#checksum_list[@]} - RETENTION_COUNT ))
		for ((i=0; i<old_count; i++)); do
			log "Pruning old checksum: ${checksum_list[$i]}"
			rm -f "${checksum_list[$i]}"
		done
	fi
}

# Entry point:
# - Validate environment
# - Ensure output root exists
# - Register EXIT trap for recovery/startup behavior
# - Perform stop + backup
main() {
	require_bin
	validate_paths

	mkdir -p "${BACKUP_ROOT}"
	trap finalize EXIT

	shutdown_jellyfin
	create_backup
	prune_old_backups
}

main
