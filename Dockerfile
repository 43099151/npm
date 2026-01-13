# 基础镜像
FROM jc21/nginx-proxy-manager:latest

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive

# === 核心修复开始 ===
# 1. rm /etc/apt/sources.list.d/* : 删除 NPM 自带的第三方源(OpenResty等)，解决 exit code 100
# 2. rm /var/lib/apt/lists/* : 清理旧缓存
# 3. apt-get update : 现在只更新 Debian 官方源，这下一定能通
# === 核心修复结束 ===
RUN rm -rf /etc/apt/sources.list.d/* && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    openssh-server \
    cron \
    socat \
    gnupg \
    iptables \
    iproute2 \
    unzip \
    xz-utils \
    && \
    # === 安装 Tailscale (静态二进制) ===
    echo "Installing Tailscale..." && \
    curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_1.92.5_amd64.tgz" -o tailscale.tgz && \
    tar -xzf tailscale.tgz && \
    mv tailscale_1.92.5_amd64/tailscale /usr/bin/tailscale && \
    mv tailscale_1.92.5_amd64/tailscaled /usr/bin/tailscaled && \
    rm -rf tailscale.tgz tailscale_1.92.5_amd64 && \
    # === 安装 Rclone (静态二进制) ===
    echo "Installing Rclone..." && \
    curl -fsSL "https://downloads.rclone.org/v1.72.1/rclone-v1.72.1-linux-amd64.zip" -o rclone.zip && \
    unzip rclone.zip && \
    mv rclone-v1.72.1-linux-amd64/rclone /usr/bin/rclone && \
    chmod +x /usr/bin/rclone && \
    rm -rf rclone.zip rclone-v1.72.1-linux-amd64 && \
    # === 配置 SSH ===
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    # === 清理瘦身 ===
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 复制脚本
COPY scripts/start.sh /usr/local/bin/start.sh
COPY scripts/backup.sh /usr/local/bin/backup.sh

# 赋予权限
RUN chmod +x /usr/local/bin/start.sh /usr/local/bin/backup.sh

# 暴露端口
EXPOSE 7860 80 81 443

# 启动入口
ENTRYPOINT ["/usr/local/bin/start.sh"]
