#!/bin/bash

echo "[INFO] Starting Container Initialization..."

# 1. 配置 Rclone (通过环境变量动态生成配置)
# 只要提供了 R2 的变量，就生成配置文件
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
else
    echo "[WARNING] R2 credentials not found. Skipping backup/restore setup."
fi

# 2. 数据恢复 (Restore)
# 在 NPM 启动前恢复数据，防止覆盖
if [ -n "$R2_BUCKET" ]; then
    echo "[INFO] Checking for backup in R2..."
    # 尝试下载最新的备份包
    if rclone lsf "r2:$R2_BUCKET/npm_backup.tar.gz" >/dev/null 2>&1; then
        echo "[INFO] Backup found. Restoring..."
        rclone copy "r2:$R2_BUCKET/npm_backup.tar.gz" /tmp/
        
        # 解压数据到根目录 (会覆盖 /data, /etc/letsencrypt, /var/lib/tailscale)
        tar -xzf /tmp/npm_backup.tar.gz -C /
        rm /tmp/npm_backup.tar.gz
        echo "[INFO] Restore complete."
    else
        echo "[INFO] No backup found. Starting fresh."
    fi
fi

# 3. 配置 SSH
if [ -n "$ROOT_PASSWORD" ]; then
    echo "root:$ROOT_PASSWORD" | chpasswd
    echo "[INFO] Root password set."
else
    echo "[WARNING] ROOT_PASSWORD not set. SSH login might fail."
fi
service ssh start

# 4. 启动 Tailscale
# 确保目录存在
mkdir -p /var/lib/tailscale
mkdir -p /var/run/tailscale

# 启动 tailscaled 守护进程 (后台运行)
tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/tmp/tailscaled.sock &
sleep 5

# 启动 Tailscale 上线 (使用提供的 socket 和参数)
if [ -n "$TS_AUTH_KEY" ]; then
    tailscale --socket=/tmp/tailscaled.sock up \
        --authkey="${TS_AUTH_KEY}" \
        --hostname="${TS_NAME:-npm-hf}" \
        --accept-routes \
        --advertise-exit-node
    echo "[INFO] Tailscale started."
fi

# 5. 配置定时备份任务 (Crontab)
echo "0 */4 * * * /bin/bash /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1" > /etc/cron.d/npm-backup
chmod 0644 /etc/cron.d/npm-backup
crontab /etc/cron.d/npm-backup
service cron start

# 6. 端口映射 (Hugging Face 专供)
# HF 只开放 7860。用户要求将 NPM 的 443 映射到 7860。
# 这样访问 HF 的 URL 实际上是访问 NPM 的 HTTPS 反代服务。
# 注意：NPM 的管理后台(81端口)将无法通过公网访问，只能通过 Tailscale 内网 IP 访问。
socat TCP-LISTEN:7860,fork,bind=0.0.0.0 TCP:127.0.0.1:443 &
echo "[INFO] Port 443 mapped to 7860 via socat."

# 7. 启动 NPM (转交控制权给 S6 Overlay)
echo "[INFO] Starting Nginx Proxy Manager..."
# NPM 原始镜像的 CMD 或 ENTRYPOINT 是 /init
exec /init

