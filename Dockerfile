# ==========================================
# 阶段 1: 资源获取 (在干净的 Debian 中准备所有文件)
# ==========================================
FROM debian:bookworm-slim AS builder

# 安装下载工具
RUN apt-get update && apt-get install -y curl tar unzip socat

# 1. 提取 Socat (直接找 binary)
# 我们直接把 apt 安装好的 socat 复制出来，Debian 之间的 glibc 兼容性很好
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
# 阶段 2: 最终组装 (不运行 apt，避开所有错误)
# ==========================================
FROM jc21/nginx-proxy-manager:latest

# 切换 Root 以便移动文件
USER root

# 1. 复制所有二进制文件
COPY --from=builder /tmp/tailscale/tailscale /usr/bin/tailscale
COPY --from=builder /tmp/tailscale/tailscaled /usr/bin/tailscaled
COPY --from=builder /tmp/rclone/rclone /usr/bin/rclone
COPY --from=builder /tmp/socat /usr/bin/socat

# 2. 赋予权限
RUN chmod +x /usr/bin/tailscale /usr/bin/tailscaled /usr/bin/rclone /usr/bin/socat

# 3. 创建必要的目录 (手动创建，因为不装 sshd 了)
RUN mkdir -p /var/run/tailscale /var/lib/tailscale /root/.config/rclone

# 复制脚本
COPY scripts/start.sh /usr/local/bin/start.sh
COPY scripts/backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/start.sh /usr/local/bin/backup.sh

# 端口
EXPOSE 7860 80 81 443

# 启动
ENTRYPOINT ["/usr/local/bin/start.sh"]
