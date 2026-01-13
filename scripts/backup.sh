#!/bin/bash

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
echo "[$TIMESTAMP] Starting backup..."

# 定义备份路径
BACKUP_FILE="/tmp/npm_backup.tar.gz"

# 打包关键目录
# /data: NPM 数据库和配置
# /etc/letsencrypt: SSL 证书
# /var/lib/tailscale: Tailscale 身份状态 (避免重启后变成新设备)
# /root/.ssh: SSH 配置(可选)
tar -czf "$BACKUP_FILE" \
    /data \
    /etc/letsencrypt \
    /var/lib/tailscale \
    /root/.ssh 2>/dev/null

# 上传到 R2
if [ -f "$BACKUP_FILE" ]; then
    rclone copy "$BACKUP_FILE" "r2:$R2_BUCKET/" --overwrite
    echo "[$TIMESTAMP] Backup uploaded to R2 successfully."
    rm "$BACKUP_FILE"
else
    echo "[$TIMESTAMP] Error: Backup file creation failed."
fi

