# 基础镜像使用 Nginx Proxy Manager 官方镜像
FROM jc21/nginx-proxy-manager:latest

# 设置环境变量，防止交互式安装卡住
ENV DEBIAN_FRONTEND=noninteractive

# 安装必要的工具：Tailscale, Rclone, SSH, Cron, Socat, Vim
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    openssh-server \
    cron \
    socat \
    gnupg \
    && \
    # 安装 Tailscale
    mkdir -p --mode=0755 /usr/share/keyrings && \
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.noarmor.gpg | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null && \
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/jammy.tailscale-keyring.list | tee /etc/apt/sources.list.d/tailscale.list && \
    apt-get update && \
    apt-get install -y tailscale && \
    # 安装 Rclone
    curl https://rclone.org/install.sh | bash && \
    # 配置 SSH 允许 Root 登录
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    # 清理缓存减小镜像体积
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 复制脚本到容器
COPY scripts/start.sh /usr/local/bin/start.sh
COPY scripts/backup.sh /usr/local/bin/backup.sh

# 赋予执行权限
RUN chmod +x /usr/local/bin/start.sh /usr/local/bin/backup.sh

# 暴露端口 (HF 需要 7860)
EXPOSE 7860 80 81 443

# 设置自定义入口点
ENTRYPOINT ["/usr/local/bin/start.sh"]
