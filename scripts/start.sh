#!/bin/bash

echo "[INFO] Starting Container..."

# 1. Rclone 配置
if [ -n "$R2_ACCESS_KEY_ID" ]; then
    cat <<EOF > /root/.config/rclone/rclone.conf
[r2]
type = s3
provider = Cloudflare
access_key_id = $R2_ACCESS_KEY_ID
secret_access_key = $R2_SECRET_ACCESS_KEY
endpoint = $R2_ENDPOINT
acl = private
EOF
fi

# 2. 恢复数据
if [ -n "$R2_BUCKET" ]; then
    if rclone lsf "r2:$R2_BUCKET/npm_backup.tar.gz" >/dev/null 2>&1; then
        echo "[INFO] Restoring backup..."
        rclone copy "r2:$R2_BUCKET/npm_backup.tar.gz" /tmp/
        tar -xzf /tmp/npm_backup.tar.gz -C /
        rm /tmp/npm_backup.tar.gz
    else
        echo "[INFO] No backup found."
    fi
fi

# 3. 启动 Tailscale (用户态模式 + 自带SSH)
# 注意：移除了 --advertise-exit-node，添加了 --tun=userspace-networking
tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state --socket=/tmp/tailscaled.sock &
sleep 5

if [ -n "$TS_AUTH_KEY" ]; then
    tailscale --socket=/tmp/tailscaled.sock up \
        --authkey="${TS_AUTH_KEY}" \
        --hostname="${TS_NAME:-npm-hf}" \
        --ssh \
        --accept-routes
    echo "[INFO] Tailscale up."
fi

# 4. 定时备份循环
(
    while true; do
        sleep 14400
        /bin/bash /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1
    done
) &

# 5. 端口映射 (使用提取进来的 socat)
socat TCP-LISTEN:7860,fork,bind=0.0.0.0 TCP:127.0.0.1:443 &

# 6. 启动 NPM
echo "[INFO] Starting NPM..."
exec /init
