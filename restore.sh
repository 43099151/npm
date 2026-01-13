#!/bin/sh
set -e

export RCLONE_CONFIG=/data/rclone/rclone.conf

rclone copy r2:${R2_BUCKET}/backup/data.tar.gz /backup/ || exit 0

tar xzf /backup/data.tar.gz -C /
