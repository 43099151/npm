# ==========================================
# 阶段 1: 下载工具 (使用干净的 Debian 镜像)
# ==========================================
FROM debian:bookworm-slim AS builder

# 安装下载工具
RUN apt-get update && apt-get install -y curl tar unzip

# 1. 下载并解压 Tailscale (静态二进制 v1.92.5)
WORKDIR /tmp/tailscale
RUN curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_1.92.5_amd64.tgz" -o tailscale.tgz && \
    tar -xzf tailscale.tgz && \
    mv tailscale_1.92.5_amd64/tailscale /tmp/tailscale/tailscale && \
    mv tailscale_1.92.5_amd64/tailscaled /tmp/tailscale/tailscaled

# 2. 下载并解压 Rclone (更新为 v1.72.1)
WORKDIR /tmp/rclone
# 注意：这里更新了下载链接和解压后的目录名
RUN curl -fsSL "https://downloads.rclone.org/v1.72.1/rclone-v1.72.1-linux-amd64.zip" -o rclone.zip && \
    unzip rclone.zip && \
    mv rclone-v1.72.1-linux-amd64/rclone /tmp/rclone/rclone

# ==========================================
# 阶段 2: 构建最终镜像 (基于 NPM)
# ==========================================
FROM jc21/nginx-proxy-manager:latest

# 【关键修复】强制使用 root 用户，解决权限导致的 exit code 100
USER root

# 设置非交互模式
ENV DEBIAN_FRONTEND=noninteractive

# 【关键修复】彻底重写 sources.list 为官方源，解决源损坏问题
RUN echo "deb http://deb.debian.org/debian bookworm main contrib non-free-firmware" > /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian-security bookworm-security main contrib non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware" >> /etc/apt/sources.list && \
    # 删除所有第三方干扰源
    rm -rf /etc/apt/sources.list.d/* && \
    rm -rf /var/lib/apt/lists/*

# 安装运行时依赖 (SSH, Cron, Socat, Iptables)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    openssh-server \
    cron \
    socat \
    iptables \
    iproute2 \
    ca-certificates \
    && \
    # 配置 SSH
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    # 清理垃圾
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 从构建阶段复制二进制文件
COPY --from=builder /tmp/tailscale/tailscale /usr/bin/tailscale
COPY --from=builder /tmp/tailscale/tailscaled /usr/bin/tailscaled
COPY --from=builder /tmp/rclone/rclone /usr/bin/rclone

# 赋予可执行权限
RUN chmod +x /usr/bin/tailscale /usr/bin/tailscaled /usr/bin/rclone

# 复制你的脚本
COPY scripts/start.sh /usr/local/bin/start.sh
COPY scripts/backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/start.sh /usr/local/bin/backup.sh

# 端口和入口
EXPOSE 7860 80 81 443
ENTRYPOINT ["/usr/local/bin/start.sh"]
