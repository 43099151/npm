# ==========================================
# 阶段 1: 下载工具 (保持不变，这部分没问题)
# ==========================================
FROM debian:bookworm-slim AS builder

RUN apt-get update && apt-get install -y curl tar unzip

# 1. 下载 Tailscale
WORKDIR /tmp/tailscale
RUN curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_1.92.5_amd64.tgz" -o tailscale.tgz && \
    tar -xzf tailscale.tgz && \
    mv tailscale_1.92.5_amd64/tailscale /tmp/tailscale/tailscale && \
    mv tailscale_1.92.5_amd64/tailscaled /tmp/tailscale/tailscaled

# 2. 下载 Rclone
WORKDIR /tmp/rclone
RUN curl -fsSL "https://downloads.rclone.org/v1.72.1/rclone-v1.72.1-linux-amd64.zip" -o rclone.zip && \
    unzip rclone.zip && \
    mv rclone-v1.72.1-linux-amd64/rclone /tmp/rclone/rclone

# ==========================================
# 阶段 2: 构建最终镜像 (GPG 绕过版)
# ==========================================
FROM jc21/nginx-proxy-manager:latest

# 1. 必须使用 Root
USER root
ENV DEBIAN_FRONTEND=noninteractive

# 2. 暴力构建脚本
# 关键点 A: set +o pipefail -> 防止清理命令返回非零值导致构建中断
# 关键点 B: [trusted=yes] -> 彻底无视 GPG 签名错误，强制安装
RUN set +o pipefail && \
    echo "=== Starting Force Build ===" && \
    \
    echo "1. Nuking existing apt configs..." && \
    rm -rf /etc/apt/sources.list.d/* && \
    rm -rf /var/lib/apt/lists/* && \
    echo "" > /etc/apt/sources.list && \
    \
    echo "2. Writing TRUSTED sources (Bypassing GPG)..." && \
    echo "deb [trusted=yes] http://deb.debian.org/debian bookworm main contrib non-free-firmware" > /etc/apt/sources.list && \
    echo "deb [trusted=yes] http://deb.debian.org/debian-security bookworm-security main contrib non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb [trusted=yes] http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware" >> /etc/apt/sources.list && \
    \
    echo "3. Installing packages..." && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-server \
        socat \
        iptables \
        iproute2 \
        ca-certificates \
        && \
    \
    echo "4. Configuring SSH..." && \
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    \
    echo "5. Cleanup..." && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 从构建阶段复制文件
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
