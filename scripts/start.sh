#!/bin/bash

echo "[INFO] Starting Container..."

# ==========================================
# 1. 硬编码配置区域 (非敏感信息)
# ==========================================
# Tailscale 设置
export TS_SOCKET=/tmp/tailscaled.sock
export TS_NAME="npm"  # 你的 Tailscale 设备名

# R2 配置 (非敏感部分)
export R2_ACCESS_KEY_ID="75e72cddecc51b32deab13873c967000"
export R2_ENDPOINT="https://6e84f688bfe062834470070a2d946be5.r2.cloudflarestorage.com"
export R2_BUCKET="hf-backups/npm"

# ==========================================
# 2. 检查敏感变量 (必须在 HF 后台填入)
# ==========================================
if [ -z "$R2_SECRET_ACCESS_KEY" ]; then
    echo "[WARNING] R2_SECRET_ACCESS_KEY is missing! Backup/Restore will fail."
fi

if [ -z "$TS_AUTH_KEY" ]; then
    echo "[WARNING] TS_AUTH_KEY is missing! Tailscale will not start."
fi

# ==========================================
# 3. 生成 Rclone 配置文件
# ==========================================
# 只有当 Secret Key 存在时才生成配置
if [ -n "$R2_SECRET_ACCESS_KEY" ]; then
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

# ==========================================
# 4. 恢复数据
# ==========================================
if [ -n "$R2_SECRET_ACCESS_KEY" ] && [ -n "$R2_BUCKET" ]; then
    if rclone lsf "r2:$R2_BUCKET/npm_backup.tar.gz" >/dev/null 2>&1; then
        echo "[INFO] Restoring backup from R2..."
        rclone copy "r2:$R2_BUCKET/npm_backup.tar.gz" /tmp/
        tar -xzf /tmp/npm_backup.tar.gz -C /
        rm /tmp/npm_backup.tar.gz
        echo "[INFO] Restore complete."
    else
        echo "[INFO] No remote backup found. Starting fresh."
    fi
fi

# ==========================================
# 5. 启动 Tailscale
# ==========================================
mkdir -p /var/lib/tailscale /var/run/tailscale

# 启动守护进程
tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state --socket=$TS_SOCKET &
sleep 5

# 仅当提供了 Auth Key 时才启动 Client
if [ -n "$TS_AUTH_KEY" ]; then
    # 组装参数
    TS_ARGS="--authkey=${TS_AUTH_KEY} --hostname=${TS_NAME} --ssh --accept-routes"
    
    # 如果有 Tags 变量，则添加 (可选)
    if [ -n "$TS_TAGS" ]; then
        TS_ARGS="$TS_ARGS --advertise-tags=${TS_TAGS}"
    fi

    # 启动 (带 --reset 防止状态冲突)
    tailscale up $TS_ARGS --reset
    echo "[INFO] Tailscale up command executed."
else
    echo "[WARNING] Tailscale skipped because TS_AUTH_KEY is not set."
fi

# ==========================================
# 6. 启动定时备份循环 (每4小时)
# ==========================================
(
    while true; do
        sleep 14400
        /bin/bash /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1
    done
) &

# ==========================================
# 7. 端口映射 (HF 7860 -> NPM 80)
# ==========================================
socat TCP-LISTEN:7860,fork,bind=0.0.0.0 TCP:127.0.0.1:80 &
echo "[INFO] Port 80 mapped to 7860 via socat."

# ==========================================
# 8. 启动 NPM
# ==========================================
echo "[INFO] Starting NPM..."
exec /init
