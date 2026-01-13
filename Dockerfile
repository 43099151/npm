# ==========================================
# 阶段 1: 下载工具 (使用干净的 Debian 镜像)
# ==========================================
FROM debian:bookworm-slim AS builder

# 安装下载工具 (这里使用官方源，肯定没问题)
RUN apt-get update && apt-get install -y curl tar unzip

# 1. 下载并解压 Tailscale (静态二进制)
WORKDIR /tmp/tailscale
RUN curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_1.92.5_amd64.tgz" -o tailscale.tgz && \
    tar -xzf tailscale.tgz && \
    mv tailscale_1.92.5_amd64/tailscale /tmp/tailscale/tailscale && \
    mv tailscale_1.92.5_amd64/tailscaled /tmp/tailscale/tailscaled

# 2. 下载并解压 Rclone
WORKDIR /tmp/rclone
RUN curl -fsSL "https://downloads.rclone.org/v1.72.1/rclone-v1.72.1-linux-amd64.zip" -o rclone.zip && \
    unzip rclone.zip && \
    mv rclone-v1.72.1-linux-amd64/rclone /tmp/rclone/rclone

# ==========================================
# 阶段 2: 构建最终镜像 (基于 NPM)
# ==========================================
FROM jc21/nginx-proxy-manager:latest

# 【核心修复 1】必须显式声明 USER root，否则 apt 根本没权限跑
USER root

# 设置非交互模式
ENV DEBIAN_FRONTEND=noninteractive

# 【核心修复 2】原子化操作：将换源、清理、更新、安装合并为一条指令
# 这样可以避免 "exit code 100" 这种中间层锁死的问题
RUN echo "Running atomic install script..." && \
    # 1. 清理潜在的干扰 (代理配置、旧列表)
    rm -f /etc/apt/apt.conf.d/*proxy* && \
    rm -rf /var/lib/apt/lists/* && \
    # 2. 暴力重写源 (确保使用 Debian 官方源)
    echo "deb http://deb.debian.org/debian bookworm main contrib non-free-firmware" > /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian-security bookworm-security main contrib non-free-firmware" >> /etc/apt/sources.list && \
    echo "deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware" >> /etc/apt/sources.list && \
    rm -rf /etc/apt/sources.list.d/* && \
    # 3. 更新并安装 (添加 || true 防止 update 返回非致命错误码)
    (apt-get update || true) && \
    apt-get install -y --no-install-recommends \
        openssh-server \
        cron \
        socat \
        iptables \
        iproute2 \
        ca-certificates \
        && \
    # 4. 配置 SSH
    mkdir -p /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    # 5. 最后清理
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
