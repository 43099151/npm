# 基础镜像
FROM jc21/nginx-proxy-manager:latest

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive

# 1. 安装系统基础依赖
# 注意：必须显式安装 iptables，否则 --advertise-exit-node 会报错
# ca-certificates 用于 HTTPS 验证
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    openssh-server \
    cron \
    socat \
    gnupg \
    iptables \
    iproute2 \
    && \
    # 2. 手动安装 Tailscale (静态二进制包)
    # 直接下载你指定的版本
    curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_1.92.5_amd64.tgz" -o tailscale.tgz && \
    tar -xzf tailscale.tgz && \
    # 将二进制文件移动到系统路径
    mv tailscale_1.92.5_amd64/tailscale /usr/bin/tailscale && \
    mv tailscale_1.92.5_amd64/tailscaled /usr/bin/tailscaled && \
    # 清理下载文件
    rm -rf tailscale.tgz tailscale_1.92.5_amd64 && \
    # 3. 安装 Rclone
    curl https://rclone.org/install.sh | bash && \
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
