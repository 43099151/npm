#!/bin/bash

echo "[INFO] Starting Container..."

# ==========================================
# 1. 硬编码配置区域
# ==========================================
export TS_SOCKET=/tmp/tailscaled.sock
export TS_NAME="npm"
export R2_ACCESS_KEY_ID="75e72cddecc51b32deab13873c967000"
export R2_ENDPOINT="https://6e84f688bfe062834470070a2d946be5.r2.cloudflarestorage.com"
export R2_BUCKET="hf-backups/npm"

# ==========================================
# 2. 检查敏感变量
# ==========================================
if [ -z "$R2_SECRET_ACCESS_KEY" ]; then
    echo "[WARNING] R2_SECRET_ACCESS_KEY is missing! Backup/Restore will fail."
fi
if [ -z "$TS_AUTH_KEY" ]; then
    echo "[WARNING] TS_AUTH_KEY is missing! Tailscale will not start."
fi

# ==========================================
# 3. 生成 Rclone 配置
# ==========================================
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
# 4. 恢复数据 (优化版：先检查文件是否存在)
# ==========================================
if [ -n "$R2_SECRET_ACCESS_KEY" ] && [ -n "$R2_BUCKET" ]; then
    # 尝试下载
    if rclone copy "r2:$R2_BUCKET/npm_backup.tar.gz" /tmp/ 2>/dev/null; then
        if [ -f "/tmp/npm_backup.tar.gz" ]; then
            echo "[INFO] Backup downloaded. Restoring..."
            tar -xzf /tmp/npm_backup.tar.gz -C /
            rm /tmp/npm_backup.tar.gz
            echo "[INFO] Restore complete."
        else
            echo "[INFO] Remote file not found (Fresh install)."
        fi
    else
        echo "[INFO] Rclone download skipped (Fresh install or R2 error)."
    fi
fi

# ==========================================
# 5. 启动 Tailscale (关键修复)
# ==========================================
mkdir -p /var/lib/tailscale /var/run/tailscale

# 启动守护进程
tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state --socket=$TS_SOCKET &
sleep 5

if [ -n "$TS_AUTH_KEY" ]; then
    # 组装命令
    TS_CMD="tailscale --socket=$TS_SOCKET up --authkey=${TS_AUTH_KEY} --hostname=${TS_NAME} --ssh --accept-routes --reset"
    
    if [ -n "$TS_TAGS" ]; then
        TS_CMD="$TS_CMD --advertise-tags=${TS_TAGS}"
    fi

    echo "[INFO] Running Tailscale up..."
    
    # 运行并捕获错误
    if $TS_CMD; then
        echo "[SUCCESS] Tailscale is ONLINE!"
    else
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        echo "[ERROR] Tailscale failed to connect! Check your Key below:"
        echo "1. Is the key 'Reusable'?"
        echo "2. Did you set Tags in the key but not in the script?"
        echo "3. Is the key expired?"
        echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
        # 不退出，让 NPM 继续运行，方便查看日志
    fi
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
