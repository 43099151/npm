# 基础镜像
FROM jc21/nginx-proxy-manager:latest

# 设置环境变量
ENV DEBIAN_FRONTEND=noninteractive

# 1. 安装系统基础依赖
# 新增: unzip (Rclone 脚本必须)
# 新增: apt-transport-https (防止某些源报错)
# 修改: apt-get update 后面加上 || true 防止偶发报错中断构建
RUN (apt-get update || true) && \
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
    apt-transport-https \
    && \
    # 2. 手动安装 Tailscale (静态二进制包)
    curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_1.92.5_amd64.tgz" -o tailscale.tgz && \
    tar -xzf tailscale.tgz && \
    mv tailscale_1.92.5_amd64/tailscale /usr/bin/tailscale && \
    mv tailscale_1.92.5_amd64/tailscaled /usr/bin/tailscaled && \
    rm -rf tailscale.tgz tailscale_1.92.5_amd64 && \
    # 3. 安装 Rclone (现在有了 unzip，这里可以通过了)
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
