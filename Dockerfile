# ==========================================
# 阶段 1: 资源获取 (保持不变)
# ==========================================
FROM debian:bookworm-slim AS builder

# 安装下载工具
RUN apt-get update && apt-get install -y curl tar unzip socat

# 1. 提取 Socat
RUN cp /usr/bin/socat /tmp/socat

# 2. 下载 Tailscale
WORKDIR /tmp/tailscale
RUN curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_1.92.5_amd64.tgz" -o tailscale.tgz && \
    tar -xzf tailscale.tgz && \
    mv tailscale_1.92.5_amd64/tailscale /tmp/tailscale/tailscale && \
    mv tailscale_1.92.5_amd64/tailscaled /tmp/tailscale/tailscaled

# 3. 下载 Rclone
WORKDIR /tmp/rclone
RUN curl -fsSL "https://downloads.rclone.org/v1.72.1/rclone-v1.72.1-linux-amd64.zip" -o rclone.zip && \
    unzip rclone.zip && \
    mv rclone-v1.72.1-linux-amd64/rclone /tmp/rclone/rclone

# ==========================================
# 阶段 2: 最终组装 (破解启动检查)
# ==========================================
FROM jc21/nginx-proxy-manager:latest

# 切换 Root 进行修改
USER root

# ---------------------------------------------------
# 【关键修复】破解 NPM 的强制挂载检查
# ---------------------------------------------------
# NPM 的启动脚本中有一段代码强制检查 /data 和 /etc/letsencrypt 是否挂载
# 下面的命令会找到这个检查脚本，并将 exit 1 (退出) 改为 true (放行)
# 或者直接把检查挂载的逻辑删掉
RUN echo "Patching startup scripts to disable mount checks..." && \
    # 查找包含报错信息的文件 (通常在 /etc/s6-overlay 或 /etc/cont-init.d 下)
    # 我们直接暴力替换：只要看到检查 mountpoint 失败就退出 1 的逻辑，统统干掉
    find /etc -type f -exec sed -i 's/if ! mountpoint -q/if false; then #/g' {} + || true && \
    # 针对具体的报错字符串进行屏蔽 (双重保险)
    find /etc -type f -exec sed -i 's/echo "ERROR: .* is not mounted/echo "WARNING: Mount check bypassed/g' {} + || true && \
    find /etc -type f -exec sed -i 's/exit 1/true/g' {} + || true

# 1. 复制二进制文件
COPY --from=builder /tmp/tailscale/tailscale /usr/bin/tailscale
COPY --from=builder /tmp/tailscale/tailscaled /usr/bin/tailscaled
COPY --from=builder /tmp/rclone/rclone /usr/bin/rclone
COPY --from=builder /tmp/socat /usr/bin/socat

# 2. 赋予权限
RUN chmod +x /usr/bin/tailscale /usr/bin/tailscaled /usr/bin/rclone /usr/bin/socat

# 3. 创建必要的目录
# 既然绕过了挂载检查，我们必须手动创建这些目录，否则程序可能会找不到
RUN mkdir -p /var/run/tailscale /var/lib/tailscale /root/.config/rclone \
    /data /etc/letsencrypt

# 复制脚本
COPY scripts/start.sh /usr/local/bin/start.sh
COPY scripts/backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/start.sh /usr/local/bin/backup.sh

# 端口
EXPOSE 7860 80 81 443

# 启动
ENTRYPOINT ["/usr/local/bin/start.sh"]
