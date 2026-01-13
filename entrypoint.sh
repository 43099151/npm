#!/bin/bash
set -e

export RCLONE_CONFIG=/data/rclone/rclone.conf

echo "[1/6] Restore from R2"
bash /scripts/restore.sh || echo "No backup found"

echo "[2/6] Start tailscaled"
tailscaled \
  --state=/data/tailscale/tailscaled.state \
  --socket=${TS_SOCKET} \
  --tun=userspace-networking &

sleep 5

echo "[3/6] Tailscale up (SSH enabled)"
tailscale --socket=${TS_SOCKET} up \
  --authkey="${TS_AUTH_KEY}" \
  --hostname="${TS_NAME}" \
  --accept-routes \
  --advertise-exit-node \
  --ssh

echo "[4/6] Enable cron backup"
echo "0 */4 * * * /scripts/backup.sh >> /var/log/backup.log 2>&1" > /etc/crontabs/root
crond

echo "[5/6] Start Nginx Proxy Manager"
export NPM_DB_SQLITE_FILE=/data/npm/database.sqlite
export NPM_PORT=443
export NPM_LISTEN_PORT=7860
npm run start &

echo "[6/6] Keep alive"
tail -f /dev/null
