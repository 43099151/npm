#!/bin/bash

echo "[INFO] Starting Container..."

# 1. Rclone 配置 (保持不变)
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
fi

# 2. 恢复数据 (保持不变)
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

# 3. 启动 Tailscale (关键修改)
# 确保目录存在
mkdir -p /var/lib/tailscale /var/run/tailscale

# 启动守护进程
tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state --socket=/tmp/tailscaled.sock &
sleep 5

if [ -n "$TS_AUTH_KEY" ]; then
    # 构建参数
    TS_ARGS="--socket=/tmp/tailscaled.sock --authkey=${TS_AUTH_KEY} --hostname=${TS_NAME:-npm-hf} --ssh --accept-routes --advertise-exit-node"
    
    # 如果设置了 TS_TAGS 环境变量，则添加 (解决 tags 400 错误)
    if [ -n "$TS_TAGS" ]; then
        TS_ARGS="$TS_ARGS --advertise-tags=${TS_TAGS}"
    fi

    # 强制重新登录 (防止状态文件与新 Key 冲突)
    tailscale up $TS_ARGS --reset
    echo "[INFO] Tailscale up command executed."
fi

# 4. 启动定时备份 (保持不变)
(
    while true; do
        sleep 14400
        /bin/bash /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1
    done
) &

# 5. 端口映射 (关键修改：改为 TCP:127.0.0.1:80)
# HF (HTTPS) -> HF LoadBalancer (HTTP 7860) -> Socat -> NPM (HTTP 80)
socat TCP-LISTEN:7860,fork,bind=0.0.0.0 TCP:127.0.0.1:80 &
echo "[INFO] Port 80 mapped to 7860 via socat."

# 6. 启动 NPM
echo "[INFO] Starting NPM..."
exec /init
