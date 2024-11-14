#!/bin/bash

TIMESTAMP=$(date +%Y%m%d%H%M%S)
VERSION=10.9
BACKUP_DIR=jellyfin.${TIMESTAMP}_${VERSION}

echo "## creating /${BACKUP_DIR}"
sudo mkdir -p ./${BACKUP_DIR}  # Or change the path wherever in your system makes sense to you

echo "## copy data ${BACKUP_DIR}/data"
sudo cp -a /var/lib/jellyfin ./${BACKUP_DIR}/data

echo "## copy config ${BACKUP_DIR}/config"
sudo cp -a /etc/jellyfin ./${BACKUP_DIR}/config

echo "## tar ${BACKUP_DIR}_data"
sudo tar -czf ${BACKUP_DIR}_data.tar.gz ./${BACKUP_DIR}/data

echo "## tar ${BACKUP_DIR}_config"
sudo tar -czf ${BACKUP_DIR}_config.tar.gz ./${BACKUP_DIR}/config

echo "## removing ${BACKUP_DIR}"
sudo rm -rf ./${BACKUP_DIR}
