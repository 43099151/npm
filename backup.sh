#!/bin/sh
set -e

export RCLONE_CONFIG=/data/rclone/rclone.conf

echo "Backup $(date)"

tar czf /backup/data.tar.gz \
  /data/npm \
  /data/tailscale \
  /data/rclone

rclone copy /backup/data.tar.gz r2:${R2_BUCKET}/backup --immutable
