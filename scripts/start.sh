#!/bin/bash

echo "[INFO] Starting Container Initialization..."

# 1. 生成 Rclone 配置
if [ -n "$R2_ACCESS_KEY_ID" ]; then
    mkdir -p /root/.config/rclone
    cat <<EOF > /root/.config/rclone/rclone.conf
[r2]
type = s3
provider = Cloudflare
access_key_id = $R2_ACCESS_KEY_ID
secret_access_key = $R2_SECRET_ACCESS_KEY
endpoint = $R2_ENDPOINT
acl = private
EOF
    echo "[INFO] Rclone config generated."
fi

# 2. 恢复数据
if [ -n "$R2_BUCKET" ]; then
    echo "[INFO] Checking for backup in R2..."
    if rclone lsf "r2:$R2_BUCKET/npm_backup.tar.gz" >/dev/null 2>&1; then
        echo "[INFO] Backup found. Restoring..."
        rclone copy "r2:$R2_BUCKET/npm_backup.tar.gz" /tmp/
        tar -xzf /tmp/npm_backup.tar.gz -C /
        rm /tmp/npm_backup.tar.gz
        echo "[INFO] Restore complete."
    else
        echo "[INFO] No backup found. Starting fresh."
    fi
fi

# 3. 启动 SSH 服务
if [ -n "$ROOT_PASSWORD" ]; then
    echo "root:$ROOT_PASSWORD" | chpasswd
    echo "[INFO] Root password set."
fi
service ssh start

# 4. 启动 Tailscale
mkdir -p /var/lib/tailscale
mkdir -p /var/run/tailscale

# 启动守护进程
tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/tmp/tailscaled.sock &
sleep 5

# 启动 Tailscale (开启 --ssh 功能，推荐使用)
if [ -n "$TS_AUTH_KEY" ]; then
    tailscale --socket=/tmp/tailscaled.sock up \
        --authkey="${TS_AUTH_KEY}" \
        --hostname="${TS_NAME:-npm-hf}" \
        --accept-routes \
        --advertise-exit-node \
        --ssh  # 开启 Tailscale 内置 SSH，比普通 SSH 更方便
    echo "[INFO] Tailscale started."
fi

# 5. 启动后台定时备份循环 (替代 Crontab)
# 每 4 小时 (14400 秒) 执行一次
(
    while true; do
        sleep 14400
        /bin/bash /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1
    done
) &
echo "[INFO] Backup loop started."

# 6. 端口映射 (NPM 443 -> HF 7860)
socat TCP-LISTEN:7860,fork,bind=0.0.0.0 TCP:127.0.0.1:443 &
echo "[INFO] Port 443 mapped to 7860 via socat."

# 7. 启动 NPM
echo "[INFO] Starting Nginx Proxy Manager..."
exec /init
