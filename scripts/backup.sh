#!/bin/bash

# ==========================================
# 1. 配置区域 (硬编码 Bucket 名称)
# ==========================================
# 必须与 start.sh 中的设置保持一致
R2_BUCKET="hf-backups/npm"

# ==========================================
# 2. 执行备份
# ==========================================
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
echo "[$TIMESTAMP] Starting backup..."

BACKUP_FILE="/tmp/npm_backup.tar.gz"

# 打包关键数据
# 增加了 /root/.config/rclone 以防 Rclone 配置丢失
# 2>/dev/null 忽略一些非致命的读取错误
tar -czf "$BACKUP_FILE" \
    /data \
    /etc/letsencrypt \
    /var/lib/tailscale \
    /root/.ssh \
    /root/.config/rclone 2>/dev/null

# 上传到 R2
if [ -f "$BACKUP_FILE" ]; then
    # 使用硬编码的 R2_BUCKET 变量
    # 增加 --retries 防止网络波动
    if rclone copy "$BACKUP_FILE" "r2:$R2_BUCKET/" --overwrite --retries 3; then
        echo "[$TIMESTAMP] Backup uploaded to R2 successfully."
        rm "$BACKUP_FILE"
    else
        echo "[$TIMESTAMP] Error: Upload to R2 failed."
    fi
else
    echo "[$TIMESTAMP] Error: Backup file creation failed."
fi
