#!/bin/bash

echo "[INFO] Starting Container..."

# ==========================================
# 1. 硬编码配置区域
# ==========================================
export TS_SOCKET=/tmp/tailscaled.sock
export TS_NAME="npm"
export R2_ACCESS_KEY_ID="75e72cddecc51b32deab13873c967000"
export R2_ENDPOINT="https://6e84f688bfe062834470070a2d946be5.r2.cloudflarestorage.com"
export R2_BUCKET="hf--backups/npm"

# ==========================================
# 2. 检查敏感变量
# ==========================================
if [ -z "$R2_SECRET_ACCESS_KEY" ]; then
    echo "[WARNING] R2_SECRET_ACCESS_KEY is missing!"
fi
if [ -z "$TS_AUTH_KEY" ]; then
    echo "[WARNING] TS_AUTH_KEY is missing!"
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
fi

# ==========================================
# 4. 恢复数据
# ==========================================
if [ -n "$R2_SECRET_ACCESS_KEY" ] && [ -n "$R2_BUCKET" ]; then
    if rclone copy "r2:$R2_BUCKET/npm_backup.tar.gz" /tmp/ 2>/dev/null; then
        if [ -f "/tmp/npm_backup.tar.gz" ]; then
            echo "[INFO] Restoring backup..."
            tar -xzf /tmp/npm_backup.tar.gz -C /
            rm /tmp/npm_backup.tar.gz
        fi
    else
        echo "[INFO] Fresh install (no backup found)."
    fi
fi

# ==========================================
# 5. 启动 Tailscale
# ==========================================
mkdir -p /var/lib/tailscale /var/run/tailscale
tailscaled --tun=userspace-networking --state=/var/lib/tailscale/tailscaled.state --socket=$TS_SOCKET &
sleep 5

if [ -n "$TS_AUTH_KEY" ]; then
    TS_CMD="tailscale --socket=$TS_SOCKET up --authkey=${TS_AUTH_KEY} --hostname=${TS_NAME} --ssh --accept-routes --reset"
    if [ -n "$TS_TAGS" ]; then
        TS_CMD="$TS_CMD --advertise-tags=${TS_TAGS}"
    fi
    echo "[INFO] Tailscale up..."
    $TS_CMD
fi

# ==========================================
# 6. 后台任务：定时备份 & 端口转发
# ==========================================

# 6.1 定时备份循环
(
    while true; do
        sleep 14400
        /bin/bash /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1
    done
) &

# 6.2 智能端口转发 (关键修改)
# 将这部分逻辑放入后台，不阻塞主进程启动 NPM
(
    echo "[INFO] Waiting for NPM port 80..."
    # 使用 Bash 内置功能检测端口，不需要 nc
    timeout=60
    while ! (echo > /dev/tcp/127.0.0.1/80) >/dev/null 2>&1; do
        sleep 1
        timeout=$((timeout - 1))
        if [ $timeout -le 0 ]; then
            echo "[ERROR] NPM port 80 check timeout!"
            break
        fi
    done
    
    echo "[INFO] Port 80 is UP! Starting Socat..."
    socat TCP-LISTEN:7860,fork,bind=0.0.0.0 TCP:127.0.0.1:80
) &

# ==========================================
# 7. 启动 NPM (必须作为 PID 1)
# ==========================================
echo "[INFO] Starting NPM (Exec PID 1)..."
# 使用 exec 让 NPM 替代当前 Shell 成为 PID 1，解决 s6 报错
exec /init
