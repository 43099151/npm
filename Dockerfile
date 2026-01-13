# ==========================================
# 阶段 1: 下载工具 (保持不变，这部分很稳定)
# ==========================================
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y curl tar unzip

WORKDIR /tmp/tailscale
RUN curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_1.92.5_amd64.tgz" -o tailscale.tgz && \
    tar -xzf tailscale.tgz && \
    mv tailscale_1.92.5_amd64/tailscale /tmp/tailscale/tailscale && \
    mv tailscale_1.92.5_amd64/tailscaled /tmp/tailscale/tailscaled

WORKDIR /tmp/rclone
RUN curl -fsSL "https://downloads.rclone.org/v1.72.1/rclone-v1.72.1-linux-amd64.zip" -o rclone.zip && \
    unzip rclone.zip && \
    mv rclone-v1.72.1-linux-amd64/rclone /tmp/rclone/rclone

# ==========================================
# 阶段 2: 构建最终镜像 (动态适配版)
# ==========================================
FROM jc21/nginx-proxy-manager:latest

# 1. 强制 Root 权限
USER root
ENV DEBIAN_FRONTEND=noninteractive

# 2. 智能安装脚本
# 使用 /bin/bash 但去掉了 -o pipefail，防止清理命令因找不到文件报错
RUN /bin/bash -c 'set -e; \
    echo "=== Starting Build Process ==="; \
    \
    echo "1. Cleaning up potential locks and bad configs..."; \
    rm -f /var/lib/dpkg/lock*; \
    rm -f /var/cache/apt/archives/lock; \
    rm -f /var/lib/apt/lists/lock; \
    # 使用 || true 防止文件不存在时报错 \
    rm -f /etc/apt/apt.conf.d/*proxy* || true; \
    rm -rf /etc/apt/sources.list.d/* || true; \
    rm -rf /var/lib/apt/lists/*; \
    \
    echo "2. Detecting OS Codename..."; \
    # 动态获取系统代号 (bullseye 或 bookworm) \
    . /etc/os-release; \
    echo "Detected Debian version: $VERSION_CODENAME"; \
    \
    echo "3. Generating valid sources.list..."; \
    # 根据检测到的代号写入官方源 \
    echo "deb http://deb.debian.org/debian $VERSION_CODENAME main contrib non-free" > /etc/apt/sources.list; \
    echo "deb http://deb.debian.org/debian-security $VERSION_CODENAME-security main contrib non-free" >> /etc/apt/sources.list; \
    echo "deb http://deb.debian.org/debian $VERSION_CODENAME-updates main contrib non-free" >> /etc/apt/sources.list; \
    \
    echo "4. Installing dependencies..."; \
    # 尝试修复可能损坏的 dpkg 状态 \
    dpkg --configure -a || true; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        openssh-server \
        cron \
        socat \
        iptables \
        iproute2 \
        ca-certificates; \
    \
    echo "5. Configuring SSH..."; \
    mkdir -p /var/run/sshd; \
    sed -i "s/#PermitRootLogin prohibit-password/PermitRootLogin yes/" /etc/ssh/sshd_config; \
    \
    echo "6. Final cleanup..."; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*'

# 复制二进制文件
COPY --from=builder /tmp/tailscale/tailscale /usr/bin/tailscale
COPY --from=builder /tmp/tailscale/tailscaled /usr/bin/tailscaled
COPY --from=builder /tmp/rclone/rclone /usr/bin/rclone

# 赋予权限
RUN chmod +x /usr/bin/tailscale /usr/bin/tailscaled /usr/bin/rclone

# 复制脚本
COPY scripts/start.sh /usr/local/bin/start.sh
COPY scripts/backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/start.sh /usr/local/bin/backup.sh

# 端口和入口
EXPOSE 7860 80 81 443
ENTRYPOINT ["/usr/local/bin/start.sh"]
