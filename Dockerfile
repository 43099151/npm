# 基础镜像
FROM jc21/nginx-proxy-manager:latest

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive

# 1. 安装系统依赖
# 关键修复：先删除 /var/lib/apt/lists/* 以解决 "exit code 100" 的列表损坏问题
# 安装 unzip 用于解压 rclone
RUN rm -rf /var/lib/apt/lists/* && \
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
    # 2. 安装 Tailscale (静态二进制)
    echo "Installing Tailscale..." && \
    curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_1.92.5_amd64.tgz" -o tailscale.tgz && \
    tar -xzf tailscale.tgz && \
    mv tailscale_1.92.5_amd64/tailscale /usr/bin/tailscale && \
    mv tailscale_1.92.5_amd64/tailscaled /usr/bin/tailscaled && \
    rm -rf tailscale.tgz tailscale_1.92.5_amd64 && \
    # 3. 安装 Rclone (静态二进制 - 避免脚本错误)
    echo "Installing Rclone..." && \
    curl -fsSL "https://downloads.rclone.org/v1.72.1/rclone-v1.72.1-linux-amd64.zip" -o rclone.zip && \
    unzip rclone.zip && \
    mv rclone-v1.72.1-linux-amd64/rclone /usr/bin/rclone && \
    chmod +x /usr/bin/rclone && \
    rm -rf rclone.zip rclone-v1.72.1-linux-amd64 && \
    # 4. 配置 SSH
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    # 5. 清理缓存
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
