# ==========================================
# 阶段 1: 下载工具 (使用纯净 Debian 环境)
# ==========================================
FROM debian:bookworm-slim AS builder

# 安装下载工具
RUN apt-get update && apt-get install -y curl tar unzip

# 1. 下载 Tailscale (使用静态二进制)
WORKDIR /tmp/tailscale
RUN curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_1.92.5_amd64.tgz" -o tailscale.tgz && \
    tar -xzf tailscale.tgz && \
    mv tailscale_1.92.5_amd64/tailscale /tmp/tailscale/tailscale && \
    mv tailscale_1.92.5_amd64/tailscaled /tmp/tailscale/tailscaled

# 2. 下载 Rclone (使用静态二进制)
WORKDIR /tmp/rclone
RUN curl -fsSL "https://downloads.rclone.org/v1.72.1/rclone-v1.72.1-linux-amd64.zip" -o rclone.zip && \
    unzip rclone.zip && \
    mv rclone-v1.72.1-linux-amd64/rclone /tmp/rclone/rclone

# ==========================================
# 阶段 2: 构建最终镜像 (基于 NPM)
# ==========================================
FROM jc21/nginx-proxy-manager:latest

# 强制切换到 Root
USER root
ENV DEBIAN_FRONTEND=noninteractive

# 【核心修复脚本】
# 1. rm -f ... || true: 忽略清理过程中的"文件不存在"错误
# 2. --allow-insecure-repositories: 允许首次更新时忽略签名错误(Exit 100的克星)
# 3. install debian-archive-keyring: 修复签名链
RUN echo "Running comprehensive install script..." && \
    rm -f /var/lib/dpkg/lock* || true && \
    rm -f /var/lib/apt/lists/lock || true && \
    rm -rf /etc/apt/sources.list.d/* || true && \
    rm -rf /var/lib/apt/lists/* || true && \
    \
    echo "Writing Bookworm Sources..." && \
    echo "deb http://deb.debian.org/debian bookworm main contrib non-free-firmware" > /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian-security bookworm-security main contrib non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware" >> /etc/apt/sources.list && \
    \
    echo "Updating APT (Allowing Insecure for Keyring fix)..." && \
    apt-get update --allow-insecure-repositories || true && \
    apt-get install -y --allow-unauthenticated debian-archive-keyring && \
    \
    echo "Installing Dependencies..." && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        openssh-server \
        socat \
        iptables \
        iproute2 \
        ca-certificates \
        && \
    \
    echo "Configuring SSH..." && \
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    \
    echo "Cleaning up..." && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 从构建阶段复制二进制文件
COPY --from=builder /tmp/tailscale/tailscale /usr/bin/tailscale
COPY --from=builder /tmp/tailscale/tailscaled /usr/bin/tailscaled
COPY --from=builder /tmp/rclone/rclone /usr/bin/rclone

# 赋予可执行权限
RUN chmod +x /usr/bin/tailscale /usr/bin/tailscaled /usr/bin/rclone

# 复制脚本
COPY scripts/start.sh /usr/local/bin/start.sh
COPY scripts/backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/start.sh /usr/local/bin/backup.sh

# 端口和入口
EXPOSE 7860 80 81 443
ENTRYPOINT ["/usr/local/bin/start.sh"]
